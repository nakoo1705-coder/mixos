#!/bin/sh
# ============================================================================
# MixOS-GO Init Bottom Script
# Runs after mounting root filesystem, before switch_root
# ============================================================================

. /scripts/functions.sh

log_step "Running init-bottom hooks..."

# Prepare the new root
prepare_newroot() {
    local newroot=$1
    
    log_info "Preparing new root: $newroot"
    
    # Create essential directories
    for dir in dev proc sys run tmp var/run var/lock; do
        ensure_dir "$newroot/$dir"
    done
    
    # Set permissions
    chmod 1777 "$newroot/tmp" 2>/dev/null || true
    chmod 755 "$newroot/var/run" 2>/dev/null || true
}

# Copy resolv.conf if network was configured
copy_network_config() {
    local newroot=$1
    
    if [ -f /etc/resolv.conf ]; then
        ensure_dir "$newroot/etc"
        cp /etc/resolv.conf "$newroot/etc/resolv.conf" 2>/dev/null || true
    fi
}

# Write boot info for the new system
write_boot_info() {
    local newroot=$1
    
    ensure_dir "$newroot/run/initramfs"
    
    # Write boot mode
    echo "$BOOT_MODE" > "$newroot/run/initramfs/boot-mode" 2>/dev/null || true
    
    # Write VRAM status
    if [ -n "$VRAM_ACTIVE" ]; then
        echo "active" > "$newroot/run/initramfs/vram-status"
        echo "$VRAM_SIZE_MB" > "$newroot/run/initramfs/vram-size"
    fi
    
    # Write boot timestamp
    date +%s > "$newroot/run/initramfs/boot-time" 2>/dev/null || true
}

# Clean up initramfs mounts
cleanup_initramfs() {
    log_info "Cleaning up initramfs..."
    
    # Unmount temporary mounts that won't be moved
    safe_umount /dev/pts
    safe_umount /dev/shm
}

# Main execution
main() {
    local newroot=${1:-/mnt/root}
    
    prepare_newroot "$newroot"
    copy_network_config "$newroot"
    write_boot_info "$newroot"
    cleanup_initramfs
    
    log_ok "Init-bottom complete"
}

main "$@"
