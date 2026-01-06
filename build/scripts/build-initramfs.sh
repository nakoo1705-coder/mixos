#!/bin/bash
# ============================================================================
# MixOS-GO Enhanced Initramfs Builder
# Builds professional initramfs with VISO/SDISK/VRAM support
# 
# Initramfs is the early boot environment that:
# 1. Loads kernel modules
# 2. Detects boot media (ISO, VISO, SDISK)
# 3. Mounts rootfs (squashfs)
# 4. Switches to real root
# ============================================================================

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
else
    echo "ERROR: common.sh not found"
    exit 1
fi

# Initramfs configuration
INITRAMFS_BUILD="$BUILD_DIR/initramfs-build"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"

# Init script location - try new location first, then old
if [ -f "${REPO_ROOT}/rootfs/init/init" ]; then
    INIT_SCRIPT="${REPO_ROOT}/rootfs/init/init"
elif [ -f "${REPO_ROOT}/initramfs/init" ]; then
    INIT_SCRIPT="${REPO_ROOT}/initramfs/init"
else
    die "Init script not found!"
fi

# Kernel modules location
KERNEL_BUILD="${BUILD_DIR}/kernel"
MODULES_DIR="${KERNEL_BUILD}/modules"

log_header "MixOS-GO Enhanced Initramfs Builder"

log_info "Build Directory: $BUILD_DIR"
log_info "Output Directory: $OUTPUT_DIR"
log_info "Init Script: $INIT_SCRIPT"
log_info "Kernel Version: $KERNEL_VERSION"
log_info "Modules Directory: $MODULES_DIR"
echo ""

# Create directories
ensure_dir "$BUILD_DIR"
ensure_dir "$OUTPUT_DIR/boot"

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
log_step "Installing init scripts..."

# Copy main init script (use INIT_SCRIPT variable set at top)
if [ -f "$INIT_SCRIPT" ]; then
    cp "$INIT_SCRIPT" "$INITRAMFS_BUILD/init"
    chmod +x "$INITRAMFS_BUILD/init"
    log_ok "Main init script installed from $INIT_SCRIPT"
else
    die "Init script not found: $INIT_SCRIPT"
fi

# Copy helper scripts from new location first, then old
HELPER_SCRIPTS_DIR=""
if [ -d "${REPO_ROOT}/rootfs/init/scripts" ]; then
    HELPER_SCRIPTS_DIR="${REPO_ROOT}/rootfs/init/scripts"
elif [ -d "${REPO_ROOT}/initramfs/scripts" ]; then
    HELPER_SCRIPTS_DIR="${REPO_ROOT}/initramfs/scripts"
fi

if [ -n "$HELPER_SCRIPTS_DIR" ] && [ -d "$HELPER_SCRIPTS_DIR" ]; then
    cp -r "$HELPER_SCRIPTS_DIR"/* "$INITRAMFS_BUILD/scripts/" 2>/dev/null || true
    chmod +x "$INITRAMFS_BUILD/scripts"/*.sh 2>/dev/null || true
    log_ok "Helper scripts installed from $HELPER_SCRIPTS_DIR"
fi

# ============================================================================
# Step 4: Copy kernel modules
# ============================================================================
log_step "Installing kernel modules..."

# Modules can be in multiple locations (in order of preference):
# 1. KERNEL_BUILD/modules/lib/modules/$KERNEL_VERSION (from build-kernel.sh)
# 2. BUILD_DIR/rootfs/lib/modules/$KERNEL_VERSION (if rootfs was built with modules)
# 3. OUTPUT_DIR/modules-mixos.tar.gz (kernel modules archive)

MODULES_DST="$INITRAMFS_BUILD/lib/modules/$KERNEL_VERSION"

# Try to find modules source
MODULES_SRC=""
if [ -d "$MODULES_DIR/lib/modules" ]; then
    # Find the actual kernel version directory
    for kver_dir in "$MODULES_DIR/lib/modules"/*; do
        if [ -d "$kver_dir" ]; then
            MODULES_SRC="$kver_dir"
            KERNEL_VERSION="$(basename "$kver_dir")"
            MODULES_DST="$INITRAMFS_BUILD/lib/modules/$KERNEL_VERSION"
            log_info "Found modules at $MODULES_SRC"
            break
        fi
    done
fi

if [ -z "$MODULES_SRC" ] && [ -d "$BUILD_DIR/rootfs/lib/modules" ]; then
    for kver_dir in "$BUILD_DIR/rootfs/lib/modules"/*; do
        if [ -d "$kver_dir" ]; then
            MODULES_SRC="$kver_dir"
            KERNEL_VERSION="$(basename "$kver_dir")"
            MODULES_DST="$INITRAMFS_BUILD/lib/modules/$KERNEL_VERSION"
            log_info "Found modules in rootfs at $MODULES_SRC"
            break
        fi
    done
fi

MODULES_TARBALL="${KERNEL_BUILD}/modules-mixos.tar.gz"
if [ -z "$MODULES_SRC" ] && [ ! -f "$MODULES_TARBALL" ]; then
    MODULES_TARBALL="$OUTPUT_DIR/modules-mixos.tar.gz"
fi

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
