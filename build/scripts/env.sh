#!/bin/bash
# ============================================================================
# MixOS-GO Environment Variables
# Source this file to set up build environment
# ============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Path Configuration
# ============================================================================

# Kernel paths
KERNEL_CONFIG="${REPO_ROOT}/kernel/config/mixos_defconfig"
KERNEL_PATCHES="${REPO_ROOT}/kernel/patches"
KERNEL_BUILD="${BUILD_DIR}/kernel"

# RootFS paths
ROOTFS_SKELETON="${REPO_ROOT}/rootfs/skeleton"
ROOTFS_OVERLAYS="${REPO_ROOT}/rootfs/overlays"
ROOTFS_INIT="${REPO_ROOT}/rootfs/init"
ROOTFS_BUILD="${BUILD_DIR}/rootfs"
ROOTFS_SQUASHFS="${BUILD_DIR}/rootfs.squashfs"

# Source paths
SRC_MIX_CLI="${REPO_ROOT}/src/mix-cli"
SRC_INSTALLER="${REPO_ROOT}/src/installer"
SRC_AGENT="${REPO_ROOT}/src/agent"

# Package paths
PACKAGES_DIR="${REPO_ROOT}/packages"

# Output paths
OUTPUT_BOOT="${OUTPUT_DIR}/boot"
OUTPUT_PACKAGES="${OUTPUT_DIR}/packages"

# Export all paths
export KERNEL_CONFIG KERNEL_PATCHES KERNEL_BUILD
export ROOTFS_SKELETON ROOTFS_OVERLAYS ROOTFS_INIT ROOTFS_BUILD ROOTFS_SQUASHFS
export SRC_MIX_CLI SRC_INSTALLER SRC_AGENT
export PACKAGES_DIR
export OUTPUT_BOOT OUTPUT_PACKAGES

# ============================================================================
# Build Artifact Names
# ============================================================================

KERNEL_IMAGE="vmlinuz-mixos"
INITRAMFS_IMAGE="initramfs-mixos.img"
ISO_NAME="mixos-go-v${VERSION}.iso"
VISO_NAME="mixos-go-v${VERSION}.viso"

export KERNEL_IMAGE INITRAMFS_IMAGE ISO_NAME VISO_NAME

# ============================================================================
# Print Environment
# ============================================================================

print_env() {
    echo ""
    echo "MixOS-GO Build Environment"
    echo "=========================="
    echo ""
    echo "Directories:"
    echo "  REPO_ROOT:        $REPO_ROOT"
    echo "  BUILD_DIR:        $BUILD_DIR"
    echo "  OUTPUT_DIR:       $OUTPUT_DIR"
    echo ""
    echo "Kernel:"
    echo "  KERNEL_CONFIG:    $KERNEL_CONFIG"
    echo "  KERNEL_BUILD:     $KERNEL_BUILD"
    echo "  KERNEL_VERSION:   $KERNEL_VERSION"
    echo ""
    echo "RootFS:"
    echo "  ROOTFS_SKELETON:  $ROOTFS_SKELETON"
    echo "  ROOTFS_BUILD:     $ROOTFS_BUILD"
    echo "  ROOTFS_SQUASHFS:  $ROOTFS_SQUASHFS"
    echo ""
    echo "Sources:"
    echo "  SRC_MIX_CLI:      $SRC_MIX_CLI"
    echo "  SRC_INSTALLER:    $SRC_INSTALLER"
    echo "  PACKAGES_DIR:     $PACKAGES_DIR"
    echo ""
    echo "Outputs:"
    echo "  KERNEL_IMAGE:     $KERNEL_IMAGE"
    echo "  INITRAMFS_IMAGE:  $INITRAMFS_IMAGE"
    echo "  ISO_NAME:         $ISO_NAME"
    echo "  VISO_NAME:        $VISO_NAME"
    echo ""
}

# If run directly, print environment
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_env
fi
