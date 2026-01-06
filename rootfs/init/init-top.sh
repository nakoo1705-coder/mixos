#!/bin/sh
# ============================================================================
# MixOS-GO Init Top Script
# Runs before device initialization
# ============================================================================

. /scripts/functions.sh

log_step "Running init-top hooks..."

# Set up kernel parameters
setup_kernel_params() {
    # Enable kernel messages
    echo 7 > /proc/sys/kernel/printk 2>/dev/null || true
    
    # Disable kernel panic on oops (for debugging)
    echo 0 > /proc/sys/kernel/panic_on_oops 2>/dev/null || true
    
    # Set hostname
    echo "mixos" > /proc/sys/kernel/hostname 2>/dev/null || true
}

# Set up console
setup_console() {
    # Redirect console output
    if [ -c /dev/console ]; then
        exec 0</dev/console
        exec 1>/dev/console
        exec 2>/dev/console
    fi
}

# Create essential device nodes if devtmpfs didn't
create_device_nodes() {
    # These should exist from devtmpfs, but create if missing
    [ -c /dev/null ] || mknod -m 666 /dev/null c 1 3
    [ -c /dev/zero ] || mknod -m 666 /dev/zero c 1 5
    [ -c /dev/random ] || mknod -m 666 /dev/random c 1 8
    [ -c /dev/urandom ] || mknod -m 666 /dev/urandom c 1 9
    [ -c /dev/tty ] || mknod -m 666 /dev/tty c 5 0
    [ -c /dev/console ] || mknod -m 600 /dev/console c 5 1
    [ -c /dev/ptmx ] || mknod -m 666 /dev/ptmx c 5 2
}

# Main execution
main() {
    setup_kernel_params
    setup_console
    create_device_nodes
    
    log_ok "Init-top complete"
}

main "$@"
