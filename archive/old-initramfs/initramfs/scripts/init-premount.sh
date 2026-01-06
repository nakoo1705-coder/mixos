#!/bin/sh
# ============================================================================
# MixOS-GO Init Pre-mount Script
# Runs before mounting root filesystem
# ============================================================================

. /scripts/functions.sh

log_step "Running init-premount hooks..."

# Scan for block devices
scan_block_devices() {
    log_info "Scanning for block devices..."
    
    # Trigger udev events if available
    if [ -x /sbin/udevadm ]; then
        udevadm trigger --type=subsystems --action=add
        udevadm trigger --type=devices --action=add
        udevadm settle --timeout=10
    fi
    
    # Alternative: manually scan /sys for block devices
    for block in /sys/class/block/*; do
        if [ -d "$block" ]; then
            local dev_name=$(basename "$block")
            local dev_path="/dev/$dev_name"
            
            if [ ! -b "$dev_path" ]; then
                local major=$(cat "$block/dev" 2>/dev/null | cut -d: -f1)
                local minor=$(cat "$block/dev" 2>/dev/null | cut -d: -f2)
                
                if [ -n "$major" ] && [ -n "$minor" ]; then
                    mknod "$dev_path" b "$major" "$minor" 2>/dev/null || true
                fi
            fi
        fi
    done
}

# Load additional modules based on detected hardware
load_hardware_modules() {
    log_info "Loading hardware-specific modules..."
    
    # Check for virtio
    if [ -d /sys/bus/virtio ]; then
        load_module virtio_blk
        load_module virtio_net
        load_module virtio_pci
    fi
    
    # Check for AHCI/SATA
    if [ -d /sys/bus/pci ]; then
        for dev in /sys/bus/pci/devices/*; do
            local class=$(cat "$dev/class" 2>/dev/null)
            case "$class" in
                0x010601*) # AHCI
                    load_module ahci
                    ;;
                0x010180*) # IDE
                    load_module ata_piix
                    ;;
                0x010700*) # SAS
                    load_module mpt3sas 2>/dev/null || true
                    ;;
            esac
        done
    fi
    
    # Always try to load common modules
    load_module sd_mod
    load_module sr_mod
    load_module cdrom
}

# Set up loop devices
setup_loop_devices() {
    log_info "Setting up loop devices..."
    
    load_module loop
    
    # Create loop device nodes
    for i in 0 1 2 3 4 5 6 7; do
        [ -b /dev/loop$i ] || mknod -m 660 /dev/loop$i b 7 $i 2>/dev/null || true
    done
}

# Main execution
main() {
    scan_block_devices
    load_hardware_modules
    setup_loop_devices
    
    log_ok "Init-premount complete"
}

main "$@"
