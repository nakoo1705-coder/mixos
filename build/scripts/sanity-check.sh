#!/bin/bash
# ============================================================================
# MixOS-GO Sanity Check Script
# Validates build environment and prerequisites
# ============================================================================

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/env.sh"

log_header "MixOS-GO Sanity Check"

print_build_info

# ============================================================================
# Check Required Tools
# ============================================================================

log_step "Checking required tools..."

REQUIRED_TOOLS=(
    "gcc:C compiler"
    "make:Build system"
    "tar:Archive tool"
    "gzip:Compression"
    "cpio:Archive tool"
    "curl:Download tool"
    "patch:Patch tool"
)

OPTIONAL_TOOLS=(
    "go:Go compiler (for mix-cli)"
    "mksquashfs:SquashFS tools (for rootfs)"
    "xorriso:ISO creation (for ISO)"
    "parted:Partition tool (for VISO)"
    "qemu-system-x86_64:QEMU (for testing)"
    "qemu-img:QEMU image tool (for VISO)"
    "grub-install:GRUB bootloader (for VISO)"
    "losetup:Loop device (for VISO)"
)

MISSING_REQUIRED=0
MISSING_OPTIONAL=0

for tool_desc in "${REQUIRED_TOOLS[@]}"; do
    tool="${tool_desc%%:*}"
    desc="${tool_desc#*:}"
    if command -v "$tool" >/dev/null 2>&1; then
        log_ok "$tool - $desc"
    else
        log_error "$tool - $desc [MISSING]"
        MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
    fi
done

echo ""
log_step "Checking optional tools..."

for tool_desc in "${OPTIONAL_TOOLS[@]}"; do
    tool="${tool_desc%%:*}"
    desc="${tool_desc#*:}"
    if command -v "$tool" >/dev/null 2>&1; then
        log_ok "$tool - $desc"
    else
        log_warn "$tool - $desc [MISSING]"
        MISSING_OPTIONAL=$((MISSING_OPTIONAL + 1))
    fi
done

# ============================================================================
# Check Directory Structure
# ============================================================================

echo ""
log_step "Checking directory structure..."

REQUIRED_DIRS=(
    "$REPO_ROOT/build/scripts"
    "$REPO_ROOT/src/mix-cli"
    "$REPO_ROOT/src/installer"
    "$REPO_ROOT/docs"
)

REQUIRED_FILES=(
    "$REPO_ROOT/Makefile"
    "$REPO_ROOT/build/scripts/common.sh"
    "$REPO_ROOT/build/scripts/env.sh"
)

# Check for new structure (after migration)
NEW_STRUCTURE_DIRS=(
    "$REPO_ROOT/kernel/config"
    "$REPO_ROOT/rootfs/init"
    "$REPO_ROOT/rootfs/skeleton"
    "$REPO_ROOT/packages"
)

NEW_STRUCTURE_FILES=(
    "$REPO_ROOT/kernel/config/mixos_defconfig"
    "$REPO_ROOT/rootfs/init/init"
)

# Check for old structure (before migration)
OLD_STRUCTURE_FILES=(
    "$REPO_ROOT/configs/kernel/mixos_defconfig"
    "$REPO_ROOT/initramfs/init"
)

STRUCTURE_OK=1

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_ok "Directory: ${dir#$REPO_ROOT/}"
    else
        log_error "Directory missing: ${dir#$REPO_ROOT/}"
        STRUCTURE_OK=0
    fi
done

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        log_ok "File: ${file#$REPO_ROOT/}"
    else
        log_error "File missing: ${file#$REPO_ROOT/}"
        STRUCTURE_OK=0
    fi
done

echo ""
log_step "Checking structure migration status..."

NEW_STRUCTURE_FOUND=0
OLD_STRUCTURE_FOUND=0

for file in "${NEW_STRUCTURE_FILES[@]}"; do
    if [ -f "$file" ]; then
        NEW_STRUCTURE_FOUND=$((NEW_STRUCTURE_FOUND + 1))
    fi
done

for file in "${OLD_STRUCTURE_FILES[@]}"; do
    if [ -f "$file" ]; then
        OLD_STRUCTURE_FOUND=$((OLD_STRUCTURE_FOUND + 1))
    fi
done

if [ $NEW_STRUCTURE_FOUND -eq ${#NEW_STRUCTURE_FILES[@]} ]; then
    log_ok "New canonical structure detected"
elif [ $OLD_STRUCTURE_FOUND -gt 0 ]; then
    log_warn "Old structure detected - migration needed"
    echo ""
    echo "  Old files found:"
    for file in "${OLD_STRUCTURE_FILES[@]}"; do
        if [ -f "$file" ]; then
            echo "    - ${file#$REPO_ROOT/}"
        fi
    done
else
    log_warn "Mixed or incomplete structure"
fi

# ============================================================================
# Check Kernel Config
# ============================================================================

echo ""
log_step "Checking kernel configuration..."

# Try new location first, then old
if [ -f "$KERNEL_CONFIG" ]; then
    log_ok "Kernel config found: ${KERNEL_CONFIG#$REPO_ROOT/}"
    
    # Check for essential kernel options
    ESSENTIAL_OPTIONS=(
        "CONFIG_BLK_DEV_INITRD=y"
        "CONFIG_SQUASHFS=y"
        "CONFIG_EXT4_FS=y"
        "CONFIG_VIRTIO_BLK=y"
    )
    
    for opt in "${ESSENTIAL_OPTIONS[@]}"; do
        if grep -q "^$opt" "$KERNEL_CONFIG"; then
            log_ok "  $opt"
        else
            log_warn "  $opt [NOT FOUND]"
        fi
    done
elif [ -f "$REPO_ROOT/configs/kernel/mixos_defconfig" ]; then
    log_warn "Kernel config at old location: configs/kernel/mixos_defconfig"
    log_info "Should be at: kernel/config/mixos_defconfig"
else
    log_error "Kernel config not found!"
fi

# ============================================================================
# Check Init Script
# ============================================================================

echo ""
log_step "Checking init script..."

if [ -f "$ROOTFS_INIT/init" ]; then
    log_ok "Init script found: ${ROOTFS_INIT#$REPO_ROOT/}/init"
elif [ -f "$REPO_ROOT/initramfs/init" ]; then
    log_warn "Init script at old location: initramfs/init"
    log_info "Should be at: rootfs/init/init"
else
    log_error "Init script not found!"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
log_header "Sanity Check Summary"

if [ $MISSING_REQUIRED -gt 0 ]; then
    log_error "$MISSING_REQUIRED required tools missing"
    echo ""
    echo "Install missing tools before building."
    exit 1
fi

if [ $MISSING_OPTIONAL -gt 0 ]; then
    log_warn "$MISSING_OPTIONAL optional tools missing"
    echo "Some build targets may fail."
fi

if [ $STRUCTURE_OK -eq 1 ]; then
    log_ok "Directory structure OK"
else
    log_warn "Directory structure has issues"
fi

if [ $OLD_STRUCTURE_FOUND -gt 0 ] && [ $NEW_STRUCTURE_FOUND -lt ${#NEW_STRUCTURE_FILES[@]} ]; then
    echo ""
    log_warn "Repository needs migration to canonical structure"
    echo ""
    echo "Run the following to migrate:"
    echo "  make migrate-structure"
    echo ""
fi

echo ""
log_ok "Sanity check complete"
echo ""
