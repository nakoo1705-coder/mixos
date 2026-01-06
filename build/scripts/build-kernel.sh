#!/bin/bash
# ============================================================================
# MixOS-GO Kernel Build Script
# Downloads and compiles Linux kernel
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

# Kernel configuration
KERNEL_MAJOR="6"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"

# Kernel build directory
KERNEL_BUILD="${BUILD_DIR}/kernel"

# Config file - try new location first, then old
if [ -f "${REPO_ROOT}/kernel/config/mixos_defconfig" ]; then
    CONFIG_FILE="${REPO_ROOT}/kernel/config/mixos_defconfig"
elif [ -f "${REPO_ROOT}/configs/kernel/mixos_defconfig" ]; then
    CONFIG_FILE="${REPO_ROOT}/configs/kernel/mixos_defconfig"
    log_warn "Using old config location: configs/kernel/mixos_defconfig"
else
    die "Kernel config not found!"
fi

log_header "MixOS-GO Kernel Build"

log_info "Kernel Version: $KERNEL_VERSION"
log_info "Build Directory: $KERNEL_BUILD"
log_info "Output Directory: $OUTPUT_DIR"
log_info "Config File: $CONFIG_FILE"
log_info "Parallel Jobs: $JOBS"
echo ""

# Create directories
ensure_dir "$KERNEL_BUILD"
ensure_dir "$OUTPUT_DIR/boot"

# Download kernel source if not present
KERNEL_TARBALL="$KERNEL_BUILD/linux-${KERNEL_VERSION}.tar.xz"
KERNEL_SRC="$KERNEL_BUILD/linux-${KERNEL_VERSION}"

if [ ! -f "$KERNEL_TARBALL" ]; then
    log_step "Downloading Linux kernel $KERNEL_VERSION..."
    curl -L -o "$KERNEL_TARBALL" "$KERNEL_URL"
fi

# Extract kernel source
if [ ! -d "$KERNEL_SRC" ]; then
    log_step "Extracting kernel source..."
    tar -xf "$KERNEL_TARBALL" -C "$KERNEL_BUILD"
fi

cd "$KERNEL_SRC"

# Clean previous build
log_step "Cleaning previous build..."
make mrproper

# Copy configuration
log_step "Applying MixOS kernel configuration..."
cp "$CONFIG_FILE" .config

# Update config with defaults for any new options
make olddefconfig

# Build kernel
log_step "Building kernel (this may take a while)..."
make -j"$JOBS" bzImage

# Build modules
log_step "Building kernel modules..."
make -j"$JOBS" modules

# Install modules to kernel build directory
MODULES_DIR="$KERNEL_BUILD/modules"
rm -rf "$MODULES_DIR"
mkdir -p "$MODULES_DIR"
make INSTALL_MOD_PATH="$MODULES_DIR" modules_install

# Copy kernel image to output
log_step "Copying kernel image..."
cp arch/x86/boot/bzImage "$OUTPUT_DIR/boot/vmlinuz-mixos"
cp arch/x86/boot/bzImage "$KERNEL_BUILD/vmlinuz-mixos"

# Copy System.map
cp System.map "$OUTPUT_DIR/boot/System.map-mixos"

# Create modules tarball for other scripts
log_step "Creating modules tarball..."
cd "$MODULES_DIR"
tar -czf "$KERNEL_BUILD/modules-mixos.tar.gz" lib/
# Also copy to OUTPUT_DIR for backward compatibility
cp "$KERNEL_BUILD/modules-mixos.tar.gz" "$OUTPUT_DIR/"

# Get kernel size
KERNEL_SIZE=$(du -h "$OUTPUT_DIR/boot/vmlinuz-mixos" | cut -f1)

log_header "Kernel Build Complete"

log_ok "Kernel: $OUTPUT_DIR/boot/vmlinuz-mixos ($KERNEL_SIZE)"
log_ok "Modules: $KERNEL_BUILD/modules/"
log_ok "Modules tarball: $KERNEL_BUILD/modules-mixos.tar.gz"

# Verify kernel size target
KERNEL_SIZE_BYTES=$(stat -c%s "$OUTPUT_DIR/boot/vmlinuz-mixos")
KERNEL_SIZE_MB=$((KERNEL_SIZE_BYTES / 1024 / 1024))
if [ "$KERNEL_SIZE_MB" -lt 15 ]; then
    log_ok "Kernel size ($KERNEL_SIZE_MB MB) is within target (<15MB)"
else
    log_warn "Kernel size ($KERNEL_SIZE_MB MB) exceeds target (<15MB)"
fi

# Mark kernel as built
mark_built "kernel"

echo ""
log_info "Output structure:"
echo "  $KERNEL_BUILD/"
echo "  ├── linux-${KERNEL_VERSION}/    # Source"
echo "  ├── modules/                    # Installed modules"
echo "  ├── vmlinuz-mixos               # Kernel image"
echo "  └── modules-mixos.tar.gz        # Modules archive"
echo ""
echo "  $OUTPUT_DIR/boot/"
echo "  ├── vmlinuz-mixos"
echo "  └── System.map-mixos"
