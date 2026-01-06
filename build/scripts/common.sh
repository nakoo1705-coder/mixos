#!/bin/bash
# ============================================================================
# MixOS-GO Common Build Functions
# Source this file in all build scripts
# ============================================================================

# Strict mode - but allow for sourcing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly"
    exit 1
fi

# ============================================================================
# Directory Setup
# ============================================================================

# Determine repo root (relative to this script)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Standard directories
BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/.tmp}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/artifacts}"

# Version
VERSION="${VERSION:-1.0.0}"
KERNEL_VERSION="${KERNEL_VERSION:-6.6.8}"

# Build parallelism
JOBS="${JOBS:-$(nproc)}"

# Export all
export REPO_ROOT BUILD_DIR OUTPUT_DIR VERSION KERNEL_VERSION JOBS

# ============================================================================
# Colors
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# Utility Functions
# ============================================================================

# Exit with error message
die() {
    log_error "$1"
    exit 1
}

# Check if command exists
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "Required command not found: $cmd"
    fi
}

# Check if file exists
require_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        die "Required file not found: $file"
    fi
}

# Check if directory exists
require_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        die "Required directory not found: $dir"
    fi
}

# Create directory if not exists
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

# Get file size in human readable format
file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        du -h "$file" | cut -f1
    else
        echo "N/A"
    fi
}

# ============================================================================
# Build State Functions
# ============================================================================

# Check if a build step is complete
is_built() {
    local marker="$BUILD_DIR/.built_$1"
    [ -f "$marker" ]
}

# Mark a build step as complete
mark_built() {
    local marker="$BUILD_DIR/.built_$1"
    ensure_dir "$BUILD_DIR"
    touch "$marker"
}

# Clear build marker
clear_built() {
    local marker="$BUILD_DIR/.built_$1"
    rm -f "$marker"
}

# ============================================================================
# Sanity Checks
# ============================================================================

# Basic sanity check for build environment
sanity_check_basic() {
    log_step "Running basic sanity checks..."
    
    # Check we're in repo root
    if [ ! -f "$REPO_ROOT/Makefile" ]; then
        die "Not in MixOS repository root"
    fi
    
    # Check essential tools
    local tools="gcc make tar gzip cpio"
    for tool in $tools; do
        require_cmd "$tool"
    done
    
    log_ok "Basic sanity checks passed"
}

# Full sanity check including optional tools
sanity_check_full() {
    sanity_check_basic
    
    log_step "Running full sanity checks..."
    
    # Check Go
    if ! command -v go >/dev/null 2>&1; then
        log_warn "Go not found - mix-cli build will fail"
    fi
    
    # Check squashfs tools
    if ! command -v mksquashfs >/dev/null 2>&1; then
        log_warn "mksquashfs not found - rootfs compression will fail"
    fi
    
    # Check QEMU (for testing)
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        log_warn "QEMU not found - testing will be limited"
    fi
    
    # Check xorriso (for ISO)
    if ! command -v xorriso >/dev/null 2>&1; then
        log_warn "xorriso not found - ISO build will fail"
    fi
    
    # Check parted (for VISO)
    if ! command -v parted >/dev/null 2>&1; then
        log_warn "parted not found - VISO build will fail"
    fi
    
    log_ok "Full sanity checks passed"
}

# ============================================================================
# Print Build Info
# ============================================================================

print_build_info() {
    echo ""
    echo "Build Configuration:"
    echo "  REPO_ROOT:      $REPO_ROOT"
    echo "  BUILD_DIR:      $BUILD_DIR"
    echo "  OUTPUT_DIR:     $OUTPUT_DIR"
    echo "  VERSION:        $VERSION"
    echo "  KERNEL_VERSION: $KERNEL_VERSION"
    echo "  JOBS:           $JOBS"
    echo ""
}
