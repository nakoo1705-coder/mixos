#!/bin/bash
# ============================================================================
# MixOS-GO VISO Builder v2.0
# Creates BOOTABLE VISO (Virtual ISO) images
# ============================================================================
# VISO adalah format disk image yang lebih handal dari ISO:
#   - Bootable standalone (dengan GRUB)
#   - Bootable via external kernel (-kernel/-initrd)
#   - Optimized untuk virtio (paravirtualization)
#   - Support VRAM mode (load ke RAM)
#   - Support SDISK parameter
# ============================================================================

set -e

# Directory structure
BUILD_DIR="${BUILD_DIR:-$(pwd)/.tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
VERSION="${VERSION:-1.0.0}"

# VISO Configuration
VISO_NAME="mixos-go-v${VERSION}"
VISO_SIZE_MB="${VISO_SIZE_MB:-2048}"  # 2GB default

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$VISO_MOUNT" 2>/dev/null; then
        umount "$VISO_MOUNT" 2>/dev/null || true
    fi
    
    # Detach loop device
    if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO VISO Builder v2.0                               ║"
echo "║     Bootable Virtual ISO - Better than ISO!                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log_info "Version: $VERSION"
log_info "VISO Name: $VISO_NAME"
log_info "VISO Size: ${VISO_SIZE_MB}MB"
log_info "Build Dir: $BUILD_DIR"
log_info "Output Dir: $OUTPUT_DIR"
echo ""

# Create directories
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# ============================================================================
# Step 1: Verify prerequisites
# ============================================================================
log_step "Step 1: Verifying prerequisites..."

ROOTFS_DIR="$BUILD_DIR/rootfs"

# Check rootfs
if [ ! -d "$ROOTFS_DIR" ]; then
    log_error "Rootfs not found at $ROOTFS_DIR"
    log_info "Run 'make rootfs' first"
    exit 1
fi
log_ok "Rootfs found: $ROOTFS_DIR"

# Check kernel
KERNEL_PATH=""
for kpath in "$OUTPUT_DIR/boot/vmlinuz-mixos" "$OUTPUT_DIR/vmlinuz-mixos"; do
    if [ -f "$kpath" ]; then
        KERNEL_PATH="$kpath"
        break
    fi
done

if [ -z "$KERNEL_PATH" ]; then
    log_error "Kernel not found!"
    log_info "Run 'make kernel' first"
    exit 1
fi
log_ok "Kernel found: $KERNEL_PATH"

# Check initramfs
INITRAMFS_PATH=""
if [ -f "$OUTPUT_DIR/boot/initramfs-mixos.img" ]; then
    INITRAMFS_PATH="$OUTPUT_DIR/boot/initramfs-mixos.img"
fi

if [ -z "$INITRAMFS_PATH" ]; then
    log_error "Initramfs not found!"
    log_info "Run 'make initramfs' first"
    exit 1
fi
log_ok "Initramfs found: $INITRAMFS_PATH"

# Check required tools
MISSING_TOOLS=0
for tool in parted mkfs.ext4 losetup grub-install mksquashfs qemu-img; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "Required tool not found: $tool"
        MISSING_TOOLS=1
    fi
done

if [ $MISSING_TOOLS -eq 1 ]; then
    log_error "Please install missing tools"
    exit 1
fi
log_ok "All required tools available"

# ============================================================================
# Step 2: Create squashfs rootfs
# ============================================================================
log_step "Step 2: Creating squashfs rootfs..."

SQUASHFS_PATH="$BUILD_DIR/rootfs.squashfs"

# Remove old squashfs
rm -f "$SQUASHFS_PATH"

# Create squashfs with maximum compression
mksquashfs "$ROOTFS_DIR" "$SQUASHFS_PATH" \
    -comp xz \
    -Xbcj x86 \
    -b 1M \
    -no-xattrs \
    -noappend \
    -quiet

SQUASHFS_SIZE=$(du -m "$SQUASHFS_PATH" | cut -f1)
log_ok "Squashfs created: ${SQUASHFS_SIZE}MB"

# ============================================================================
# Step 3: Calculate VISO size
# ============================================================================
log_step "Step 3: Calculating VISO size..."

KERNEL_SIZE=$(du -m "$KERNEL_PATH" | cut -f1)
INITRAMFS_SIZE=$(du -m "$INITRAMFS_PATH" | cut -f1)

# Total content size + overhead for filesystem and GRUB
CONTENT_SIZE=$((SQUASHFS_SIZE + KERNEL_SIZE + INITRAMFS_SIZE + 50))  # 50MB overhead
VISO_SIZE_MB=$((CONTENT_SIZE + 100))  # Extra 100MB buffer

# Minimum 512MB
if [ $VISO_SIZE_MB -lt 512 ]; then
    VISO_SIZE_MB=512
fi

log_info "Content size: ${CONTENT_SIZE}MB"
log_info "VISO size: ${VISO_SIZE_MB}MB"

# ============================================================================
# Step 4: Create raw disk image with partition table
# ============================================================================
log_step "Step 4: Creating raw disk image..."

VISO_RAW="$BUILD_DIR/viso.raw"
VISO_MOUNT="$BUILD_DIR/viso-mount"

# Remove old files
rm -f "$VISO_RAW"
rm -rf "$VISO_MOUNT"
mkdir -p "$VISO_MOUNT"

# Create raw image
log_info "Creating ${VISO_SIZE_MB}MB raw image..."
dd if=/dev/zero of="$VISO_RAW" bs=1M count="$VISO_SIZE_MB" status=progress 2>&1 | tail -1

log_ok "Raw image created"

# ============================================================================
# Step 5: Create partition table
# ============================================================================
log_step "Step 5: Creating partition table..."

# Create MBR partition table with single bootable partition
parted -s "$VISO_RAW" \
    mklabel msdos \
    mkpart primary ext4 1MiB 100% \
    set 1 boot on

log_ok "Partition table created (MBR, 1 bootable partition)"

# ============================================================================
# Step 6-12: Create filesystem and copy files
# ============================================================================
# We'll try multiple methods:
# 1. Loop device (requires root/privileged)
# 2. guestfish (works without root)
# 3. Direct raw manipulation (fallback)

USE_GUESTFISH=0
USE_LOOP=0

# Check if loop device is available
if losetup -f >/dev/null 2>&1; then
    # Try to setup loop device
    LOOP_DEV=$(losetup -f --show -P "$VISO_RAW" 2>/dev/null) || true
    if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ]; then
        USE_LOOP=1
        log_ok "Loop device available: $LOOP_DEV"
    fi
fi

# If loop device not available, try guestfish
if [ $USE_LOOP -eq 0 ]; then
    if command -v guestfish >/dev/null 2>&1; then
        USE_GUESTFISH=1
        log_info "Loop device not available, using guestfish"
    else
        log_error "Neither loop device nor guestfish available!"
        log_info "Please run with sudo or install libguestfs-tools"
        exit 1
    fi
fi

if [ $USE_GUESTFISH -eq 1 ]; then
    # ========================================================================
    # GUESTFISH METHOD (works without root)
    # ========================================================================
    log_step "Step 6-10: Using guestfish to create VISO..."
    
    # Prepare files to copy
    VISO_STAGING="$BUILD_DIR/viso-staging"
    rm -rf "$VISO_STAGING"
    mkdir -p "$VISO_STAGING"/{boot/grub,rootfs,config}
    
    # Copy files to staging
    cp "$KERNEL_PATH" "$VISO_STAGING/boot/vmlinuz-mixos"
    cp "$INITRAMFS_PATH" "$VISO_STAGING/boot/initramfs-mixos.img"
    cp "$SQUASHFS_PATH" "$VISO_STAGING/rootfs/rootfs.squashfs"
    
    # Create metadata
    cat > "$VISO_STAGING/config/viso.json" << EOF
{
    "name": "MixOS-GO",
    "version": "$VERSION",
    "format": "VISO",
    "created": "$(date -Iseconds)",
    "features": {
        "vram_support": true,
        "sdisk_boot": true,
        "virtio_optimized": true,
        "standalone_boot": true
    },
    "boot": {
        "kernel": "/boot/vmlinuz-mixos",
        "initramfs": "/boot/initramfs-mixos.img",
        "cmdline": "console=ttyS0 console=tty0 quiet"
    },
    "rootfs": {
        "path": "/rootfs/rootfs.squashfs",
        "format": "squashfs",
        "compression": "xz"
    }
}
EOF

    # Create GRUB config
    cat > "$VISO_STAGING/boot/grub/grub.cfg" << 'GRUBEOF'
# MixOS-GO GRUB Configuration
set timeout=5
set default=0

menuentry "MixOS-GO (Standard Boot)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 quiet
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (VRAM Mode - Maximum Performance)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 VRAM=auto quiet
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Verbose Boot)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Debug Mode)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 debug
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Recovery Shell)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 init=/bin/sh
    initrd /boot/initramfs-mixos.img
}
GRUBEOF

    # Create README
    cat > "$VISO_STAGING/README.txt" << EOF
MixOS-GO VISO v$VERSION - Virtual ISO Image
Boot with: qemu-system-x86_64 -drive file=this.viso,format=qcow2,if=virtio -m 2G
EOF

    log_ok "Staging files prepared"
    
    # Use guestfish to create the filesystem
    log_info "Creating filesystem with guestfish..."
    
    # Create guestfish script
    GUESTFISH_SCRIPT="$BUILD_DIR/guestfish.sh"
    cat > "$GUESTFISH_SCRIPT" << GFEOF
# Format partition
mkfs ext4 /dev/sda1
# Mount
mount /dev/sda1 /
# Create directories
mkdir-p /boot/grub
mkdir-p /rootfs
mkdir-p /config
# Copy files
copy-in $VISO_STAGING/boot /
copy-in $VISO_STAGING/rootfs /
copy-in $VISO_STAGING/config /
copy-in $VISO_STAGING/README.txt /
# Sync
sync
GFEOF

    # Run guestfish
    guestfish --rw -a "$VISO_RAW" -i < "$GUESTFISH_SCRIPT" 2>&1 || {
        # If -i fails (no OS), try manual approach
        log_warn "Auto-inspect failed, trying manual mount..."
        guestfish --rw -a "$VISO_RAW" <<GFEOF2
run
mkfs ext4 /dev/sda1
mount /dev/sda1 /
mkdir-p /boot/grub
mkdir-p /rootfs
mkdir-p /config
copy-in $VISO_STAGING/boot /
copy-in $VISO_STAGING/rootfs /
copy-in $VISO_STAGING/config /
copy-in $VISO_STAGING/README.txt /
sync
GFEOF2
    }
    
    log_ok "Filesystem created with guestfish"
    
    # Install GRUB using grub-install with guestfish
    log_info "Installing GRUB bootloader..."
    
    # For GRUB, we need to use virt-rescue or grub-install with special options
    # Since we can't easily run grub-install inside guestfish, we'll copy GRUB modules
    # and create a minimal boot setup
    
    # Copy GRUB modules to the image
    GRUB_MODULES_DIR="/usr/lib/grub/i386-pc"
    if [ -d "$GRUB_MODULES_DIR" ]; then
        mkdir -p "$VISO_STAGING/boot/grub/i386-pc"
        cp "$GRUB_MODULES_DIR"/*.mod "$VISO_STAGING/boot/grub/i386-pc/" 2>/dev/null || true
        cp "$GRUB_MODULES_DIR"/*.lst "$VISO_STAGING/boot/grub/i386-pc/" 2>/dev/null || true
        
        # Copy GRUB modules to image
        guestfish --rw -a "$VISO_RAW" <<GFEOF3
run
mount /dev/sda1 /
mkdir-p /boot/grub/i386-pc
copy-in $VISO_STAGING/boot/grub/i386-pc /boot/grub/
sync
GFEOF3
        log_ok "GRUB modules copied"
    fi
    
    # Install GRUB to MBR using grub-install with --directory
    # This requires the image to be accessible
    log_info "Installing GRUB to MBR..."
    
    # Create a temporary NBD or use grub-mkimage
    # For simplicity, we'll create a bootable image using grub-mkimage
    GRUB_CORE="$BUILD_DIR/core.img"
    GRUB_BOOT="$BUILD_DIR/boot.img"
    
    if [ -f "/usr/lib/grub/i386-pc/boot.img" ]; then
        cp "/usr/lib/grub/i386-pc/boot.img" "$GRUB_BOOT"
        
        # Create core.img with necessary modules
        grub-mkimage \
            -O i386-pc \
            -o "$GRUB_CORE" \
            -p "(hd0,msdos1)/boot/grub" \
            part_msdos ext2 biosdisk normal linux
        
        # Write boot.img to MBR (first 446 bytes)
        dd if="$GRUB_BOOT" of="$VISO_RAW" bs=446 count=1 conv=notrunc 2>/dev/null
        
        # Write core.img after MBR (sector 1 onwards)
        dd if="$GRUB_CORE" of="$VISO_RAW" bs=512 seek=1 conv=notrunc 2>/dev/null
        
        log_ok "GRUB installed to MBR"
    else
        log_warn "GRUB boot.img not found, VISO may not be standalone bootable"
        log_info "Use external kernel boot method instead"
    fi
    
    # Cleanup staging
    rm -rf "$VISO_STAGING"
    rm -f "$GUESTFISH_SCRIPT" "$GRUB_CORE" "$GRUB_BOOT"

else
    # ========================================================================
    # LOOP DEVICE METHOD (requires root)
    # ========================================================================
    log_step "Step 6: Setting up loop device..."
    
    # Wait for partition to appear
    sleep 1
    
    # Check for partition
    LOOP_PART="${LOOP_DEV}p1"
    if [ ! -b "$LOOP_PART" ]; then
        log_warn "Partition ${LOOP_PART} not found, trying alternative..."
        LOOP_PART="${LOOP_DEV}1"
        if [ ! -b "$LOOP_PART" ]; then
            log_error "Partition not found!"
            exit 1
        fi
    fi
    
    log_ok "Partition device: $LOOP_PART"
    
    # ============================================================================
    # Step 7: Format partition
    # ============================================================================
    log_step "Step 7: Formatting partition..."
    
    mkfs.ext4 -F -L "MIXOS-VISO" -O ^metadata_csum "$LOOP_PART"
    
    log_ok "Partition formatted (ext4)"
    
    # ============================================================================
    # Step 8: Mount partition and copy files
    # ============================================================================
    log_step "Step 8: Mounting and copying files..."
    
    mount "$LOOP_PART" "$VISO_MOUNT"
    
    # Create directory structure
    mkdir -p "$VISO_MOUNT"/{boot/grub,rootfs,config}
    
    # Copy kernel
    log_info "Copying kernel..."
    cp "$KERNEL_PATH" "$VISO_MOUNT/boot/vmlinuz-mixos"
    
    # Copy initramfs
    log_info "Copying initramfs..."
    cp "$INITRAMFS_PATH" "$VISO_MOUNT/boot/initramfs-mixos.img"
    
    # Copy squashfs rootfs
    log_info "Copying rootfs.squashfs..."
    cp "$SQUASHFS_PATH" "$VISO_MOUNT/rootfs/rootfs.squashfs"
    
    # Create VISO metadata
    log_info "Creating metadata..."
    cat > "$VISO_MOUNT/config/viso.json" << EOF
{
    "name": "MixOS-GO",
    "version": "$VERSION",
    "format": "VISO",
    "created": "$(date -Iseconds)",
    "features": {
        "vram_support": true,
        "sdisk_boot": true,
        "virtio_optimized": true,
        "standalone_boot": true
    },
    "boot": {
        "kernel": "/boot/vmlinuz-mixos",
        "initramfs": "/boot/initramfs-mixos.img",
        "cmdline": "console=ttyS0 console=tty0 quiet"
    },
    "rootfs": {
        "path": "/rootfs/rootfs.squashfs",
        "format": "squashfs",
        "compression": "xz"
    },
    "requirements": {
        "min_ram_mb": 512,
        "vram_min_ram_mb": 2048,
        "arch": "x86_64"
    }
}
EOF

    # Create README
    cat > "$VISO_MOUNT/README.txt" << EOF
MixOS-GO VISO v$VERSION
=======================
Boot with: qemu-system-x86_64 -drive file=this.viso,format=qcow2,if=virtio -m 2G
EOF

    log_ok "Files copied"
    
    # ============================================================================
    # Step 9: Create GRUB configuration
    # ============================================================================
    log_step "Step 9: Creating GRUB configuration..."
    
    cat > "$VISO_MOUNT/boot/grub/grub.cfg" << 'EOF'
# MixOS-GO GRUB Configuration
set timeout=5
set default=0

menuentry "MixOS-GO (Standard Boot)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 quiet
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (VRAM Mode - Maximum Performance)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 VRAM=auto quiet
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Verbose Boot)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Debug Mode)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 debug
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Recovery Shell)" {
    linux /boot/vmlinuz-mixos console=ttyS0 console=tty0 init=/bin/sh
    initrd /boot/initramfs-mixos.img
}
EOF
    
    log_ok "GRUB configuration created"
    
    # ============================================================================
    # Step 10: Install GRUB bootloader
    # ============================================================================
    log_step "Step 10: Installing GRUB bootloader..."
    
    grub-install \
        --target=i386-pc \
        --boot-directory="$VISO_MOUNT/boot" \
        --modules="part_msdos ext2 biosdisk" \
        "$LOOP_DEV"
    
    log_ok "GRUB installed to MBR"
    
    # ============================================================================
    # Step 11: Sync and unmount
    # ============================================================================
    log_step "Step 11: Syncing and unmounting..."
    
    sync
    umount "$VISO_MOUNT"
    
    log_ok "Unmounted"
    
    # ============================================================================
    # Step 12: Detach loop device
    # ============================================================================
    log_step "Step 12: Detaching loop device..."
    
    losetup -d "$LOOP_DEV"
    LOOP_DEV=""
    
    log_ok "Loop device detached"
fi

# ============================================================================
# Step 13: Convert to qcow2
# ============================================================================
log_step "Step 13: Converting to qcow2..."

VISO_QCOW2="$OUTPUT_DIR/${VISO_NAME}.viso"

# Remove old VISO
rm -f "$VISO_QCOW2"

# Convert with compression
qemu-img convert -f raw -O qcow2 -c "$VISO_RAW" "$VISO_QCOW2"

# Remove raw image
rm -f "$VISO_RAW"

VISO_SIZE=$(du -h "$VISO_QCOW2" | cut -f1)
log_ok "VISO created: $VISO_QCOW2 ($VISO_SIZE)"

# ============================================================================
# Step 14: Generate checksums
# ============================================================================
log_step "Step 14: Generating checksums..."

cd "$OUTPUT_DIR"
sha256sum "${VISO_NAME}.viso" > "${VISO_NAME}.viso.sha256"
cd "$REPO_ROOT"

log_ok "Checksums generated"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     VISO Build Complete!                                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Output: $OUTPUT_DIR/${VISO_NAME}.viso ($VISO_SIZE)"
echo "SHA256: $(cat "$OUTPUT_DIR/${VISO_NAME}.viso.sha256" | cut -d' ' -f1)"
echo ""
echo "VISO Features:"
echo "  ✓ Bootable standalone (GRUB inside)"
echo "  ✓ Bootable via external kernel"
echo "  ✓ VRAM mode support"
echo "  ✓ SDISK parameter support"
echo "  ✓ Virtio optimized (qcow2)"
echo ""
echo "Boot Commands:"
echo ""
echo "1. Standalone Boot:"
echo "   qemu-system-x86_64 \\"
echo "       -drive file=$OUTPUT_DIR/${VISO_NAME}.viso,format=qcow2,if=virtio \\"
echo "       -m 2G -nographic"
echo ""
echo "2. External Kernel Boot:"
echo "   qemu-system-x86_64 \\"
echo "       -kernel $KERNEL_PATH \\"
echo "       -initrd $INITRAMFS_PATH \\"
echo "       -drive file=$OUTPUT_DIR/${VISO_NAME}.viso,format=qcow2,if=virtio \\"
echo "       -append \"console=ttyS0 SDISK=${VISO_NAME}.VISO\" \\"
echo "       -m 2G -nographic"
echo ""
echo "3. VRAM Mode (add to kernel params):"
echo "   VRAM=auto"
echo ""
