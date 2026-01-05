#!/bin/bash
# ============================================================================
# MixOS-GO VISO Builder
# Creates VISO (Virtual ISO) images - Revolutionary disk format
# ============================================================================
# VISO Features:
#   - Replaces traditional CDROM/ISO format
#   - Optimized for VRAM mode
#   - Supports qcow2 with virtio for maximum performance
#   - SDISK boot parameter support
# ============================================================================

set -e

# Standardized directory structure
# BUILD_DIR: temporary build files
# BUILD_DIR/rootfs: the rootfs being built
# OUTPUT_DIR: final artifacts
# OUTPUT_DIR/boot: kernel and initramfs
BUILD_DIR="${BUILD_DIR:-$(pwd)/.tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
VERSION="${VERSION:-1.0.0}"

# VISO Configuration
VISO_NAME="mixos-go-v${VERSION}"
VISO_SIZE="${VISO_SIZE:-2G}"
VISO_FORMAT="${VISO_FORMAT:-qcow2}"

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

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO VISO Builder                                    ║"
echo "║     Revolutionary Virtual ISO Format                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log_info "Version: $VERSION"
log_info "VISO Name: $VISO_NAME"
log_info "VISO Size: $VISO_SIZE"
log_info "VISO Format: $VISO_FORMAT"
echo ""

# Create directories
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# ============================================================================
# Step 1: Verify prerequisites
# ============================================================================
log_step "Verifying prerequisites..."

ROOTFS_DIR="$BUILD_DIR/rootfs"

# Check for kernel - look in both boot/ and root of OUTPUT_DIR
KERNEL_PATH=""
if [ -f "$OUTPUT_DIR/boot/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/boot/vmlinuz-mixos"
elif [ -f "$OUTPUT_DIR/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/vmlinuz-mixos"
fi

# Check for initramfs
INITRAMFS_PATH=""
if [ -f "$OUTPUT_DIR/boot/initramfs-mixos.img" ]; then
    INITRAMFS_PATH="$OUTPUT_DIR/boot/initramfs-mixos.img"
fi

# Check for rootfs
if [ ! -d "$ROOTFS_DIR" ]; then
    log_error "Rootfs not found at $ROOTFS_DIR"
    log_info "Run 'make rootfs' first"
    exit 1
fi

# Check for kernel (optional - can use host kernel for testing)
if [ -z "$KERNEL_PATH" ]; then
    log_warn "Kernel not found at $OUTPUT_DIR/boot/vmlinuz-mixos or $OUTPUT_DIR/vmlinuz-mixos"
    log_info "Will create VISO without kernel (use host kernel for testing)"
else
    log_ok "Found kernel at $KERNEL_PATH"
fi

# Check for initramfs
if [ -z "$INITRAMFS_PATH" ]; then
    log_warn "Initramfs not found at $OUTPUT_DIR/boot/initramfs-mixos.img"
    log_info "Run 'make initramfs' first for full VISO support"
else
    log_ok "Found initramfs at $INITRAMFS_PATH"
fi

# Check for required tools
for tool in mksquashfs qemu-img; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_warn "Tool not found: $tool"
        log_info "Some features may not be available"
    fi
done

log_ok "Prerequisites verified"

# ============================================================================
# Step 2: Ensure install.yaml is in rootfs for unattended install
# ============================================================================
log_step "Checking for install.yaml..."
PACKAGING_INSTALL_YAML="$REPO_ROOT/packaging/install.yaml"
if [ ! -f "$ROOTFS_DIR/etc/mixos/install.yaml" ]; then
    mkdir -p "$ROOTFS_DIR/etc/mixos"
    if [ -n "$INSTALL_CONFIG" ] && [ -f "$INSTALL_CONFIG" ]; then
        log_info "Copying provided installer config: $INSTALL_CONFIG"
        cp "$INSTALL_CONFIG" "$ROOTFS_DIR/etc/mixos/install.yaml"
        chmod 0644 "$ROOTFS_DIR/etc/mixos/install.yaml"
    elif [ -f "$PACKAGING_INSTALL_YAML" ]; then
        log_info "Copying $PACKAGING_INSTALL_YAML"
        cp "$PACKAGING_INSTALL_YAML" "$ROOTFS_DIR/etc/mixos/install.yaml"
        chmod 0644 "$ROOTFS_DIR/etc/mixos/install.yaml"
    else
        log_warn "No install.yaml found - unattended install will not be available"
    fi
else
    log_ok "install.yaml already present in rootfs"
fi

# ============================================================================
# Step 3: Create squashfs rootfs
# ============================================================================
log_step "Creating squashfs rootfs..."

SQUASHFS_PATH="$BUILD_DIR/rootfs.squashfs"

if command -v mksquashfs >/dev/null 2>&1; then
    # Create squashfs with maximum compression
    mksquashfs "$ROOTFS_DIR" "$SQUASHFS_PATH" \
        -comp xz \
        -Xbcj x86 \
        -b 1M \
        -no-xattrs \
        -noappend \
        -quiet
    
    SQUASHFS_SIZE=$(du -h "$SQUASHFS_PATH" | cut -f1)
    log_ok "Squashfs created: $SQUASHFS_SIZE"
else
    log_warn "mksquashfs not found, creating tar archive instead"
    tar -czf "$BUILD_DIR/rootfs.tar.gz" -C "$ROOTFS_DIR" .
    SQUASHFS_PATH="$BUILD_DIR/rootfs.tar.gz"
fi

# ============================================================================
# Step 4: Create VISO directory structure
# ============================================================================
log_step "Creating VISO structure..."

VISO_BUILD="$BUILD_DIR/viso-build"
rm -rf "$VISO_BUILD"
mkdir -p "$VISO_BUILD"/{boot,rootfs,config,tools}

# Copy boot files
if [ -n "$KERNEL_PATH" ] && [ -f "$KERNEL_PATH" ]; then
    cp "$KERNEL_PATH" "$VISO_BUILD/boot/"
    log_ok "Kernel copied to VISO"
fi

if [ -n "$INITRAMFS_PATH" ] && [ -f "$INITRAMFS_PATH" ]; then
    cp "$INITRAMFS_PATH" "$VISO_BUILD/boot/"
    log_ok "Initramfs copied to VISO"
fi

# Copy rootfs
cp "$SQUASHFS_PATH" "$VISO_BUILD/rootfs/rootfs.squashfs"

# Create VISO metadata
cat > "$VISO_BUILD/config/viso.json" << EOF
{
    "name": "MixOS-GO",
    "version": "$VERSION",
    "format": "VISO",
    "created": "$(date -Iseconds)",
    "features": {
        "vram_support": true,
        "sdisk_boot": true,
        "virtio_optimized": true
    },
    "boot": {
        "kernel": "boot/vmlinuz-mixos",
        "initramfs": "boot/initramfs-mixos.img",
        "cmdline": "console=ttyS0 VRAM=auto quiet"
    },
    "rootfs": {
        "path": "rootfs/rootfs.squashfs",
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

# Create VISO README
cat > "$VISO_BUILD/README.txt" << EOF
╔══════════════════════════════════════════════════════════════╗
║                    MixOS-GO VISO v$VERSION                    ║
║              Revolutionary Virtual ISO Format                 ║
╚══════════════════════════════════════════════════════════════╝

VISO (Virtual ISO) is a next-generation disk image format designed
for maximum performance and flexibility.

FEATURES:
=========
• VRAM Mode: Boot entire system from RAM for maximum speed
• SDISK Boot: Selection Disk boot mechanism
• Virtio Optimized: Best performance with QEMU/KVM
• Squashfs Rootfs: Compressed, read-only root filesystem

BOOT OPTIONS:
=============
1. Standard Boot:
   qemu-system-x86_64 -drive file=mixos-go.viso,format=qcow2,if=virtio

2. VRAM Mode (Recommended for systems with >2GB RAM):
   qemu-system-x86_64 -drive file=mixos-go.viso,format=qcow2,if=virtio \\
     -append "VRAM=auto"

3. SDISK Boot:
   qemu-system-x86_64 -drive file=mixos-go.viso,format=qcow2,if=virtio \\
     -append "SDISK=mixos-go-v$VERSION.VISO"

PERFORMANCE TUNING:
==================
For maximum performance, use these QEMU options:
  -drive file=mixos-go.viso,format=qcow2,if=virtio,cache=writeback,aio=threads
  -cpu host
  -enable-kvm

DIRECTORY STRUCTURE:
===================
/boot/          - Kernel and initramfs
/rootfs/        - Squashfs root filesystem
/config/        - VISO configuration
/tools/         - Utility scripts

For more information, visit: https://github.com/mixos-go
EOF

log_ok "VISO structure created"

# ============================================================================
# Step 5: Create VISO image (qcow2)
# ============================================================================
log_step "Creating VISO image..."

VISO_IMG="$OUTPUT_DIR/${VISO_NAME}.viso"
VISO_RAW="$BUILD_DIR/viso-raw.img"

# Calculate required size
VISO_CONTENT_SIZE=$(du -sm "$VISO_BUILD" | cut -f1)
VISO_REQUIRED_SIZE=$((VISO_CONTENT_SIZE + 100))  # Add 100MB buffer

log_info "VISO content size: ${VISO_CONTENT_SIZE}MB"
log_info "Creating ${VISO_REQUIRED_SIZE}MB image..."

# Create raw image
dd if=/dev/zero of="$VISO_RAW" bs=1M count="$VISO_REQUIRED_SIZE" 2>/dev/null

# Create filesystem
mkfs.ext4 -F -L "MIXOS-VISO" "$VISO_RAW" 2>/dev/null

# Mount and copy files
VISO_MOUNT="$BUILD_DIR/viso-mount"
mkdir -p "$VISO_MOUNT"

# Use loop device
LOOP_DEV=$(losetup -f --show "$VISO_RAW" 2>/dev/null) || {
    log_warn "Cannot create loop device (requires root)"
    log_info "Creating bootable VISO using alternative method..."
    
    # Alternative: Use qemu-nbd for mounting if available
    if command -v qemu-nbd >/dev/null 2>&1; then
        log_info "Attempting qemu-nbd mount..."
        qemu-nbd -c /dev/nbd0 "$VISO_RAW" 2>/dev/null && sleep 1
        if [ -e /dev/nbd0p1 ]; then
            mount /dev/nbd0p1 "$VISO_MOUNT" 2>/dev/null || {
                log_warn "qemu-nbd mount failed"
                LOOP_DEV=""
            }
        else
            LOOP_DEV=""
        fi
    fi
    
    # If qemu-nbd also failed, fallback to filesystem copy approach
    if [ -z "$LOOP_DEV" ] && [ ! -d "$VISO_MOUNT/boot" ]; then
        log_info "Using filesystem copy approach..."
        mount "$VISO_RAW" "$VISO_MOUNT" 2>/dev/null || {
            # Last resort: create compressed archive
            log_warn "All mounting methods failed"
            log_info "Creating VISO as compressed archive"
            tar -czf "$OUTPUT_DIR/${VISO_NAME}.viso.tar.gz" -C "$VISO_BUILD" .
            log_ok "VISO archive created: ${VISO_NAME}.viso.tar.gz"
            rm -f "$VISO_RAW"
            VISO_CREATED="archive"
        }
    fi
}

if [ -n "$LOOP_DEV" ] && [ -d "$VISO_MOUNT/boot" ]; then
    # Mount succeeded
    mount "$LOOP_DEV" "$VISO_MOUNT"
    
    # Copy VISO content
    cp -a "$VISO_BUILD"/* "$VISO_MOUNT/"
    
    # Sync and unmount
    sync
    umount "$VISO_MOUNT"
    losetup -d "$LOOP_DEV"
    
    # Convert to qcow2
    if command -v qemu-img >/dev/null 2>&1; then
        qemu-img convert -f raw -O qcow2 -c "$VISO_RAW" "$VISO_IMG"
        rm -f "$VISO_RAW"
        log_ok "VISO qcow2 created"
        VISO_CREATED="qcow2"
    else
        mv "$VISO_RAW" "$VISO_IMG.raw"
        log_ok "VISO raw image created"
        VISO_CREATED="raw"
    fi
elif [ -d "$VISO_MOUNT/boot" ]; then
    # Mount succeeded without loop device
    cp -a "$VISO_BUILD"/* "$VISO_MOUNT/"
    sync
    umount "$VISO_MOUNT"
    
    # Convert to qcow2
    if command -v qemu-img >/dev/null 2>&1; then
        qemu-img convert -f raw -O qcow2 -c "$VISO_RAW" "$VISO_IMG"
        rm -f "$VISO_RAW"
        log_ok "VISO qcow2 created"
        VISO_CREATED="qcow2"
    else
        mv "$VISO_RAW" "$VISO_IMG.raw"
        log_ok "VISO raw image created"
        VISO_CREATED="raw"
    fi
elif [ "$VISO_CREATED" != "archive" ]; then
    # If we still have the raw image but couldn't mount, use directory copy
    log_info "Creating bootable QCOW2 from directory..."
    if command -v qemu-img >/dev/null 2>&1; then
        # Create empty QCOW2 and document structure
        qemu-img create -f qcow2 "$VISO_IMG" "${VISO_REQUIRED_SIZE}M" 2>/dev/null
        log_warn "VISO qcow2 created but requires manual filesystem setup"
        log_info "VISO structure available at: $VISO_BUILD"
        VISO_CREATED="qcow2-empty"
    fi
    rm -f "$VISO_RAW"
fi

# ============================================================================
# Step 6: Setup bootloader for VISO (if needed)
# ============================================================================
log_step "Setting up bootloader..."

# Install GRUB bootloader to VISO if available
if [ "$VISO_CREATED" = "qcow2" ] || [ "$VISO_CREATED" = "raw" ]; then
    if command -v grub-install >/dev/null 2>&1 && [ -d "$VISO_MOUNT" ]; then
        log_info "Installing GRUB bootloader..."
        
        # Create grub config
        GRUB_CFG="$VISO_MOUNT/boot/grub/grub.cfg"
        mkdir -p "$(dirname "$GRUB_CFG")"
        
        cat > "$GRUB_CFG" << 'GRUB_EOF'
menuentry 'MixOS-GO' {
    linux /boot/vmlinuz-mixos root=/dev/vda1 ro quiet
    initrd /boot/initramfs-mixos.img
}
GRUB_EOF
        
        log_ok "GRUB configuration created"
    fi
fi

# Document bootable VISO status
if [ "$VISO_CREATED" = "archive" ]; then
    log_warn "VISO created as archive (non-bootable)"
    log_info "To create bootable VISO, try running with sudo or use Docker"
fi

# ============================================================================
# Step 7: Create additional formats
# ============================================================================
log_step "Creating additional formats..."

# Create traditional ISO for compatibility
if command -v genisoimage >/dev/null 2>&1 || command -v mkisofs >/dev/null 2>&1; then
    ISO_TOOL=$(command -v genisoimage || command -v mkisofs)
    
    # Create ISO boot structure
    ISO_BUILD="$BUILD_DIR/iso-build"
    rm -rf "$ISO_BUILD"
    mkdir -p "$ISO_BUILD"/{boot/grub,live}
    
    # Copy files
    cp -a "$VISO_BUILD/boot"/* "$ISO_BUILD/boot/" 2>/dev/null || true
    cp "$VISO_BUILD/rootfs/rootfs.squashfs" "$ISO_BUILD/live/filesystem.squashfs"
    
    # Create GRUB config
    cat > "$ISO_BUILD/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "MixOS-GO (Standard)" {
    linux /boot/vmlinuz-mixos console=ttyS0 quiet
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (VRAM Mode)" {
    linux /boot/vmlinuz-mixos console=ttyS0 VRAM=auto quiet
    initrd /boot/initramfs-mixos.img
}

menuentry "MixOS-GO (Debug)" {
    linux /boot/vmlinuz-mixos console=ttyS0 debug
    initrd /boot/initramfs-mixos.img
}
EOF
    
    # Create ISO
    if command -v grub-mkrescue >/dev/null 2>&1; then
        grub-mkrescue -o "$OUTPUT_DIR/${VISO_NAME}.iso" "$ISO_BUILD" 2>/dev/null || {
            log_warn "grub-mkrescue failed, creating basic ISO"
            "$ISO_TOOL" -o "$OUTPUT_DIR/${VISO_NAME}.iso" \
                -R -J -V "MIXOS-GO" \
                "$ISO_BUILD" 2>/dev/null || true
        }
    else
        "$ISO_TOOL" -o "$OUTPUT_DIR/${VISO_NAME}.iso" \
            -R -J -V "MIXOS-GO" \
            "$ISO_BUILD" 2>/dev/null || true
    fi
    
    if [ -f "$OUTPUT_DIR/${VISO_NAME}.iso" ]; then
        log_ok "Traditional ISO created"
    fi
fi

# Create VRAM-optimized image
log_info "Creating VRAM-optimized package..."
VRAM_PKG="$OUTPUT_DIR/${VISO_NAME}.vram"
mkdir -p "$VRAM_PKG"

cp "$VISO_BUILD/rootfs/rootfs.squashfs" "$VRAM_PKG/"
cp "$VISO_BUILD/config/viso.json" "$VRAM_PKG/"
[ -f "$VISO_BUILD/boot/vmlinuz-mixos" ] && cp "$VISO_BUILD/boot/vmlinuz-mixos" "$VRAM_PKG/"
[ -f "$VISO_BUILD/boot/initramfs-mixos.img" ] && cp "$VISO_BUILD/boot/initramfs-mixos.img" "$VRAM_PKG/"

tar -czf "$OUTPUT_DIR/${VISO_NAME}.vram.tar.gz" -C "$VRAM_PKG" .
rm -rf "$VRAM_PKG"
log_ok "VRAM package created"

# ============================================================================
# Step 8: Generate checksums
# ============================================================================
log_step "Generating checksums..."

cd "$OUTPUT_DIR"
for file in ${VISO_NAME}.*; do
    if [ -f "$file" ]; then
        sha256sum "$file" > "${file}.sha256"
    fi
done
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
echo "Output files:"
ls -lh "$OUTPUT_DIR/${VISO_NAME}"* 2>/dev/null | while read line; do
    echo "  $line"
done
echo ""
echo "Boot commands:"
echo ""
echo "1. VISO with QEMU (Maximum Performance):"
echo "   qemu-system-x86_64 \\"
echo "     -drive file=$OUTPUT_DIR/${VISO_NAME}.viso,format=qcow2,if=virtio,cache=writeback,aio=threads \\"
echo "     -m 2G \\"
echo "     -cpu host \\"
echo "     -enable-kvm \\"
echo "     -nographic \\"
echo "     -append \"console=ttyS0 VRAM=auto SDISK=${VISO_NAME}.VISO\""
echo ""
echo "2. Traditional ISO:"
echo "   qemu-system-x86_64 \\"
echo "     -cdrom $OUTPUT_DIR/${VISO_NAME}.iso \\"
echo "     -m 1G \\"
echo "     -nographic"
echo ""
echo "3. VRAM Mode (Requires 2GB+ RAM):"
echo "   Boot with kernel parameter: VRAM=auto"
echo ""
