#!/bin/bash
# ============================================================================
# MixOS-GO Enhanced Initramfs Builder
# Builds professional initramfs with VISO/SDISK/VRAM support
# ============================================================================

set -e

# Standardized directory structure
# BUILD_DIR: temporary build files
# BUILD_DIR/rootfs: the rootfs being built (contains lib/modules)
# OUTPUT_DIR: final artifacts
# OUTPUT_DIR/boot: kernel and initramfs output
# OUTPUT_DIR/modules-mixos.tar.gz: kernel modules archive
BUILD_DIR="${BUILD_DIR:-$(pwd)/.tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
INITRAMFS_SRC="$REPO_ROOT/initramfs"
INITRAMFS_BUILD="$BUILD_DIR/initramfs-build"
KERNEL_VERSION="${KERNEL_VERSION:-6.6.8-mixos}"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO Enhanced Initramfs Builder                      ║"
echo "║     VISO/SDISK/VRAM Support                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log_info "Build Directory: $BUILD_DIR"
log_info "Output Directory: $OUTPUT_DIR"
log_info "Initramfs Source: $INITRAMFS_SRC"
log_info "Kernel Version: $KERNEL_VERSION"
echo ""

# Create directories
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$OUTPUT_DIR/boot"

# Clean previous build
rm -rf "$INITRAMFS_BUILD"
mkdir -p "$INITRAMFS_BUILD"

# ============================================================================
# Step 1: Create directory structure
# ============================================================================
log_info "Creating initramfs directory structure..."

mkdir -p "$INITRAMFS_BUILD"/{bin,sbin,usr/{bin,sbin},lib,lib64}
mkdir -p "$INITRAMFS_BUILD"/lib/modules/"$KERNEL_VERSION"
mkdir -p "$INITRAMFS_BUILD"/etc/{modprobe.d,udev/rules.d}
mkdir -p "$INITRAMFS_BUILD"/{proc,sys,dev,run,tmp}
mkdir -p "$INITRAMFS_BUILD"/mnt/{viso,vram,cdrom,disk,squash,root}
mkdir -p "$INITRAMFS_BUILD"/scripts

log_ok "Directory structure created"

# ============================================================================
# Step 2: Install BusyBox
# ============================================================================
log_info "Installing BusyBox..."

BUSYBOX_TARBALL="$BUILD_DIR/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_SRC="$BUILD_DIR/busybox-${BUSYBOX_VERSION}"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

# Download if needed
if [ ! -f "$BUSYBOX_TARBALL" ]; then
    log_info "Downloading BusyBox $BUSYBOX_VERSION..."
    curl -L -o "$BUSYBOX_TARBALL" "$BUSYBOX_URL"
fi

# Extract if needed
if [ ! -d "$BUSYBOX_SRC" ]; then
    log_info "Extracting BusyBox..."
    tar -xf "$BUSYBOX_TARBALL" -C "$BUILD_DIR"
fi

# Build BusyBox for initramfs (static)
cd "$BUSYBOX_SRC"

# Apply patches if available
PATCH_DIR="$REPO_ROOT/build/patches"
if [ -d "$PATCH_DIR" ]; then
    for patch in "$PATCH_DIR"/busybox-*.patch; do
        if [ -f "$patch" ]; then
            log_info "Applying patch: $(basename "$patch")"
            patch -p1 < "$patch" 2>/dev/null || true
        fi
    done
fi

# Configure for static build with all features needed for initramfs
log_info "Configuring BusyBox for initramfs..."
make defconfig

# Enable static build
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Enable features needed for initramfs
cat >> .config << 'EOF'
CONFIG_FEATURE_INSTALLER=y
CONFIG_INSTALL_APPLET_SYMLINKS=y
CONFIG_INSTALL_APPLET_HARDLINKS=n
CONFIG_MODPROBE_SMALL=y
CONFIG_INSMOD=y
CONFIG_RMMOD=y
CONFIG_LSMOD=y
CONFIG_MODINFO=y
CONFIG_SWITCH_ROOT=y
CONFIG_MOUNT=y
CONFIG_UMOUNT=y
CONFIG_LOSETUP=y
CONFIG_MKNOD=y
CONFIG_MKDIR=y
CONFIG_SLEEP=y
CONFIG_CAT=y
CONFIG_ECHO=y
CONFIG_SH_IS_ASH=y
CONFIG_ASH=y
CONFIG_ASH_BASH_COMPAT=y
CONFIG_FEATURE_SH_STANDALONE=n
EOF

# Normalize config for any new options with defaults
log_info "Normalizing BusyBox configuration..."
yes "" | make oldconfig > /dev/null 2>&1 || true

# Build
log_info "Building BusyBox..."
make -j"$(nproc)" 2>/dev/null || make

# Install to initramfs
log_info "Installing BusyBox to initramfs..."
make CONFIG_PREFIX="$INITRAMFS_BUILD" install

cd "$REPO_ROOT"
log_ok "BusyBox installed"

# ============================================================================
# Step 3: Copy init scripts
# ============================================================================
log_info "Installing init scripts..."

# Copy main init script
if [ -f "$INITRAMFS_SRC/init" ]; then
    cp "$INITRAMFS_SRC/init" "$INITRAMFS_BUILD/init"
    chmod +x "$INITRAMFS_BUILD/init"
    log_ok "Main init script installed"
else
    log_error "Init script not found: $INITRAMFS_SRC/init"
    exit 1
fi

# Copy helper scripts
if [ -d "$INITRAMFS_SRC/scripts" ]; then
    cp -r "$INITRAMFS_SRC/scripts"/* "$INITRAMFS_BUILD/scripts/"
    chmod +x "$INITRAMFS_BUILD/scripts"/*.sh 2>/dev/null || true
    log_ok "Helper scripts installed"
fi

# ============================================================================
# Step 4: Copy kernel modules
# ============================================================================
log_info "Installing kernel modules..."

# Modules can be in multiple locations:
# 1. BUILD_DIR/rootfs/lib/modules/$KERNEL_VERSION (if rootfs was built with modules)
# 2. OUTPUT_DIR/modules-mixos.tar.gz (kernel modules archive)
# We'll try both approaches

MODULES_SRC="$BUILD_DIR/rootfs/lib/modules/$KERNEL_VERSION"
MODULES_DST="$INITRAMFS_BUILD/lib/modules/$KERNEL_VERSION"
MODULES_TARBALL="$OUTPUT_DIR/modules-mixos.tar.gz"

# Essential modules for boot
ESSENTIAL_MODULES="
    kernel/fs/squashfs/squashfs.ko
    kernel/fs/ext4/ext4.ko
    kernel/fs/overlayfs/overlay.ko
    kernel/fs/isofs/isofs.ko
    kernel/drivers/virtio/virtio.ko
    kernel/drivers/virtio/virtio_ring.ko
    kernel/drivers/virtio/virtio_pci.ko
    kernel/drivers/block/virtio_blk.ko
    kernel/drivers/ata/libata.ko
    kernel/drivers/ata/ata_piix.ko
    kernel/drivers/ata/ahci.ko
    kernel/drivers/scsi/scsi_mod.ko
    kernel/drivers/scsi/sd_mod.ko
    kernel/drivers/scsi/sr_mod.ko
    kernel/drivers/cdrom/cdrom.ko
    kernel/drivers/block/loop.ko
    kernel/drivers/net/virtio_net.ko
    kernel/lib/crc32c_generic.ko
    kernel/crypto/crc32c_generic.ko
"

# If modules tarball exists but rootfs modules don't, extract to a temp location
MODULES_FOUND=0

# Try multiple sources for modules
if [ ! -d "$MODULES_SRC" ] || [ -z "$(ls -A "$MODULES_SRC" 2>/dev/null)" ]; then
    log_info "Modules not found in rootfs, checking alternatives..."
    
    # Try 1: Extract from modules tarball
    if [ -f "$MODULES_TARBALL" ]; then
        log_info "Extracting modules from $MODULES_TARBALL..."
        TEMP_MODULES="$BUILD_DIR/temp-modules"
        rm -rf "$TEMP_MODULES"
        mkdir -p "$TEMP_MODULES"
        tar -xzf "$MODULES_TARBALL" -C "$TEMP_MODULES"
        
        # Find the actual modules directory - try exact version first, then pattern
        EXTRACTED_MODULES=""
        if [ -d "$TEMP_MODULES/lib/modules/$KERNEL_VERSION" ]; then
            EXTRACTED_MODULES="$TEMP_MODULES/lib/modules/$KERNEL_VERSION"
        else
            # Try to find any modules directory
            EXTRACTED_MODULES=$(find "$TEMP_MODULES" -type d -name "$KERNEL_VERSION" 2>/dev/null | head -1)
            if [ -z "$EXTRACTED_MODULES" ]; then
                # Fallback: find any kernel version directory
                EXTRACTED_MODULES=$(find "$TEMP_MODULES" -type d -path "*/lib/modules/*" -name "[0-9]*" 2>/dev/null | head -1)
            fi
        fi
        
        if [ -n "$EXTRACTED_MODULES" ] && [ -d "$EXTRACTED_MODULES" ]; then
            MODULES_SRC="$EXTRACTED_MODULES"
            log_ok "Modules extracted to $MODULES_SRC"
        fi
    fi
    
    # Try 2: Check if kernel build left modules somewhere
    if [ ! -d "$MODULES_SRC" ] || [ -z "$(ls -A "$MODULES_SRC" 2>/dev/null)" ]; then
        KERNEL_BUILD_MODULES="$BUILD_DIR/linux-*/modules_install/lib/modules/$KERNEL_VERSION"
        for kmod in $KERNEL_BUILD_MODULES; do
            if [ -d "$kmod" ]; then
                MODULES_SRC="$kmod"
                log_ok "Found modules in kernel build: $MODULES_SRC"
                break
            fi
        done
    fi
fi

if [ -d "$MODULES_SRC" ]; then
    mkdir -p "$MODULES_DST/kernel"
    
    for mod in $ESSENTIAL_MODULES; do
        if [ -f "$MODULES_SRC/$mod" ]; then
            mod_dir=$(dirname "$mod")
            mkdir -p "$MODULES_DST/$mod_dir"
            cp "$MODULES_SRC/$mod" "$MODULES_DST/$mod"
            log_info "  Copied: $mod"
            MODULES_FOUND=1
        fi
    done
    
    # Copy modules.dep if exists
    if [ -f "$MODULES_SRC/modules.dep" ]; then
        cp "$MODULES_SRC/modules.dep" "$MODULES_DST/"
    fi
    
    # Generate modules.dep
    if command -v depmod >/dev/null 2>&1; then
        depmod -a -b "$INITRAMFS_BUILD" "$KERNEL_VERSION" 2>/dev/null || true
    fi
    
    if [ "$MODULES_FOUND" -eq 1 ]; then
        log_ok "Kernel modules installed"
    else
        log_warn "No essential modules found in $MODULES_SRC"
    fi
else
    log_warn "Kernel modules not found at $MODULES_SRC"
    log_warn "Also checked for $MODULES_TARBALL"
    log_warn "Initramfs will rely on built-in kernel modules"
fi

# ============================================================================
# Step 5: Create essential files
# ============================================================================
log_info "Creating essential files..."

# Create /etc/fstab
cat > "$INITRAMFS_BUILD/etc/fstab" << 'EOF'
# MixOS-GO Initramfs fstab
proc    /proc   proc    defaults    0 0
sysfs   /sys    sysfs   defaults    0 0
devtmpfs /dev   devtmpfs defaults   0 0
EOF

# Create modprobe.conf
cat > "$INITRAMFS_BUILD/etc/modprobe.d/mixos.conf" << 'EOF'
# MixOS-GO module configuration
options loop max_loop=8
EOF

# Create udev rules for block devices
cat > "$INITRAMFS_BUILD/etc/udev/rules.d/10-mixos.rules" << 'EOF'
# MixOS-GO udev rules
KERNEL=="sd[a-z]", GROUP="disk"
KERNEL=="sr[0-9]", GROUP="cdrom"
KERNEL=="vd[a-z]", GROUP="disk"
KERNEL=="nvme*", GROUP="disk"
KERNEL=="loop[0-9]*", GROUP="disk"
EOF

log_ok "Essential files created"

# ============================================================================
# Step 6: Create symlinks
# ============================================================================
log_info "Creating symlinks..."

# Ensure switch_root is available
if [ ! -e "$INITRAMFS_BUILD/sbin/switch_root" ]; then
    ln -sf ../bin/busybox "$INITRAMFS_BUILD/sbin/switch_root"
fi

# Create linuxrc symlink
ln -sf init "$INITRAMFS_BUILD/linuxrc" 2>/dev/null || true

log_ok "Symlinks created"

# ============================================================================
# Step 7: Build initramfs image
# ============================================================================
log_info "Building initramfs image..."

cd "$INITRAMFS_BUILD"

# Create cpio archive
find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$OUTPUT_DIR/boot/initramfs-mixos.img"

# Also create xz compressed version for smaller size
find . | cpio -H newc -o 2>/dev/null | xz --check=crc32 -9 > "$OUTPUT_DIR/boot/initramfs-mixos.img.xz"

cd "$REPO_ROOT"

# Calculate sizes
INITRAMFS_SIZE=$(du -h "$OUTPUT_DIR/boot/initramfs-mixos.img" | cut -f1)
INITRAMFS_SIZE_XZ=$(du -h "$OUTPUT_DIR/boot/initramfs-mixos.img.xz" | cut -f1)

log_ok "Initramfs built successfully"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Initramfs Build Complete!                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Output files:"
echo "  - $OUTPUT_DIR/boot/initramfs-mixos.img ($INITRAMFS_SIZE)"
echo "  - $OUTPUT_DIR/boot/initramfs-mixos.img.xz ($INITRAMFS_SIZE_XZ)"
echo ""
echo "Features included:"
echo "  ✓ VISO/SDISK boot support"
echo "  ✓ VRAM mode (RAM-based rootfs)"
echo "  ✓ Multi-device support (virtio, SATA, NVMe, CD-ROM)"
echo "  ✓ Automatic device detection"
echo "  ✓ Retry logic for mounts"
echo "  ✓ Rescue shell for debugging"
echo ""
echo "To test with QEMU:"
echo "  qemu-system-x86_64 \\"
echo "    -kernel artifacts/boot/vmlinuz-mixos \\"
echo "    -initrd artifacts/boot/initramfs-mixos.img \\"
echo "    -append \"console=ttyS0 VRAM=auto\" \\"
echo "    -nographic"
echo ""
