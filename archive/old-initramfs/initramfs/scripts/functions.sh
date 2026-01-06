#!/bin/sh
# ============================================================================
# MixOS-GO Init Helper Functions
# Common utilities for init scripts
# ============================================================================

# Color codes
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
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
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_debug() {
    if [ -n "$DEBUG_MODE" ]; then
        echo -e "[DEBUG] $1"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a module is loaded
module_loaded() {
    grep -q "^$1 " /proc/modules 2>/dev/null
}

# Load a kernel module
load_module() {
    local mod_name=$1
    local mod_path=$2
    
    if module_loaded "$mod_name"; then
        log_debug "Module already loaded: $mod_name"
        return 0
    fi
    
    if [ -n "$mod_path" ] && [ -f "$mod_path" ]; then
        insmod "$mod_path" 2>/dev/null && return 0
    fi
    
    modprobe "$mod_name" 2>/dev/null && return 0
    
    return 1
}

# Get memory info in MB
get_mem_total_mb() {
    awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
}

get_mem_free_mb() {
    awk '/MemFree/ {print int($2/1024)}' /proc/meminfo
}

get_mem_available_mb() {
    awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo
}

# Get file size in MB
get_file_size_mb() {
    local file=$1
    if [ -f "$file" ]; then
        local size=$(stat -c %s "$file" 2>/dev/null || ls -l "$file" | awk '{print $5}')
        echo $((size / 1024 / 1024))
    else
        echo "0"
    fi
}

# Get block device size in MB
get_block_size_mb() {
    local device=$1
    if [ -b "$device" ]; then
        local size=$(blockdev --getsize64 "$device" 2>/dev/null)
        if [ -n "$size" ]; then
            echo $((size / 1024 / 1024))
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Wait for a file to exist
wait_for_file() {
    local file=$1
    local timeout=${2:-10}
    local count=0
    
    while [ $count -lt $timeout ]; do
        if [ -e "$file" ]; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    return 1
}

# Wait for a block device
wait_for_block() {
    local device=$1
    local timeout=${2:-15}
    local count=0
    
    while [ $count -lt $timeout ]; do
        if [ -b "$device" ]; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    return 1
}

# Parse kernel command line
parse_cmdline_param() {
    local param=$1
    local cmdline=$(cat /proc/cmdline)
    
    if echo "$cmdline" | grep -q "${param}="; then
        echo "$cmdline" | sed -n "s/.*${param}=\([^ ]*\).*/\1/p"
    fi
}

# Check if parameter exists in cmdline
cmdline_has() {
    local param=$1
    grep -q "$param" /proc/cmdline
}

# Create directory if not exists
ensure_dir() {
    local dir=$1
    local mode=${2:-0755}
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod "$mode" "$dir"
    fi
}

# Safe mount (check if already mounted)
safe_mount() {
    local source=$1
    local target=$2
    local fstype=${3:-auto}
    local options=${4:-defaults}
    
    # Check if already mounted
    if grep -q " $target " /proc/mounts 2>/dev/null; then
        log_debug "Already mounted: $target"
        return 0
    fi
    
    ensure_dir "$target"
    mount -t "$fstype" -o "$options" "$source" "$target"
}

# Safe umount
safe_umount() {
    local target=$1
    
    if grep -q " $target " /proc/mounts 2>/dev/null; then
        umount "$target" 2>/dev/null || umount -l "$target" 2>/dev/null
    fi
}

# Copy with progress (for large files)
copy_with_progress() {
    local src=$1
    local dst=$2
    
    if command_exists pv; then
        pv "$src" > "$dst"
    elif command_exists dd; then
        dd if="$src" of="$dst" bs=4M status=progress 2>/dev/null || \
        dd if="$src" of="$dst" bs=4M
    else
        cp "$src" "$dst"
    fi
}

# Detect filesystem type
detect_fstype() {
    local device=$1
    
    if command_exists blkid; then
        blkid -s TYPE -o value "$device" 2>/dev/null
    elif [ -f /proc/filesystems ]; then
        # Try common types
        for fs in ext4 ext3 ext2 squashfs iso9660 vfat xfs btrfs; do
            if mount -t "$fs" -o ro "$device" /mnt/probe 2>/dev/null; then
                umount /mnt/probe
                echo "$fs"
                return 0
            fi
        done
    fi
}

# Print a banner
print_banner() {
    local text=$1
    local width=${2:-50}
    
    printf "╔"
    printf '═%.0s' $(seq 1 $width)
    printf "╗\n"
    
    printf "║ %-$((width-2))s ║\n" "$text"
    
    printf "╚"
    printf '═%.0s' $(seq 1 $width)
    printf "╝\n"
}

# Print a progress bar
print_progress() {
    local current=$1
    local total=$2
    local width=${3:-40}
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf '█%.0s' $(seq 1 $filled) 2>/dev/null
    printf '░%.0s' $(seq 1 $empty) 2>/dev/null
    printf "] %3d%%" "$percent"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "An error occurred. Cleaning up..."
    
    # Unmount any temporary mounts
    for mount in /mnt/vram /mnt/squash /mnt/viso /mnt/cdrom /mnt/disk; do
        safe_umount "$mount"
    done
}

# Set up error trap
setup_error_trap() {
    trap cleanup_on_error ERR
}
