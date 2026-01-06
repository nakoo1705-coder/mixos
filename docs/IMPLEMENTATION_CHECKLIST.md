# MixOS-GO Implementation Checklist
## Step-by-Step Rebuild Guide

> **Status:** Ready for implementation
> **Priority:** Execute in order, do not skip

---

## Phase 0: Preparation

- [ ] Backup current state
- [ ] Create new branch for rebuild
- [ ] Review all changes before commit

---

## Phase 1: Create Missing Infrastructure

### 1.1 Create common.sh
```bash
# File: build/scripts/common.sh
```
- [ ] Define REPO_ROOT, BUILD_DIR, OUTPUT_DIR
- [ ] Define KERNEL_VERSION, JOBS
- [ ] Create log functions (log_info, log_ok, log_warn, log_error)
- [ ] Create die() function

### 1.2 Create env.sh
```bash
# File: build/scripts/env.sh
```
- [ ] Export all environment variables
- [ ] Source common.sh

### 1.3 Create sanity-check.sh
```bash
# File: build/scripts/sanity-check.sh
```
- [ ] Check required tools (gcc, make, go, etc.)
- [ ] Check directory structure
- [ ] Validate kernel config exists

---

## Phase 2: Restructure Repository

### 2.1 Move Kernel Config
```bash
mkdir -p kernel/config kernel/patches
mv configs/kernel/mixos_defconfig kernel/config/
mv build/patches/* kernel/patches/ 2>/dev/null || true
```
- [ ] Create kernel/ directory
- [ ] Move mixos_defconfig
- [ ] Move patches

### 2.2 Move Init Script
```bash
mkdir -p rootfs/init rootfs/skeleton rootfs/overlays
mv initramfs/init rootfs/init/
mv initramfs/scripts/* rootfs/init/ 2>/dev/null || true
```
- [ ] Create rootfs/ structure
- [ ] Move init script
- [ ] Move helper scripts

### 2.3 Move Packages
```bash
mv src/packages packages
```
- [ ] Move packages to root level

### 2.4 Move Security Config
```bash
mv configs/security rootfs/overlays/
```
- [ ] Move security configs to overlays

### 2.5 Create Skeleton
```bash
# rootfs/skeleton/ - base filesystem structure
```
- [ ] Create basic directory structure
- [ ] Create fstab template

---

## Phase 3: Fix Critical Bugs

### 3.1 Fix setup_rootfs_virtio() [CRITICAL]

**File:** `rootfs/init/init` (was initramfs/init)

**Change from:**
```bash
setup_rootfs_virtio() {
    setup_rootfs_sdisk "/dev/vda"
}
```

**Change to:**
```bash
setup_rootfs_virtio() {
    local device="/dev/vda"
    
    log_step "Setting up VIRTIO root filesystem..."
    
    # Try partitions first (VISO has partition table)
    for part in "${device}1" "${device}2" "$device"; do
        if [ -b "$part" ]; then
            log_info "Trying device: $part"
            local result
            result=$(setup_rootfs_sdisk "$part")
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                echo "$result"
                return 0
            fi
        fi
    done
    
    log_error "Failed to setup VIRTIO root filesystem"
    return 1
}
```

- [ ] Update setup_rootfs_virtio()
- [ ] Test partition detection

### 3.2 Fix Makefile Circular Dependency [CRITICAL]

**File:** `Makefile`

**Change from:**
```makefile
viso: rootfs initramfs sdisk vram
sdisk: viso
```

**Change to:**
```makefile
viso: rootfs initramfs
	@echo -e "$(CYAN)Building VISO...$(NC)"
	@bash build/scripts/build-viso.sh

sdisk: viso
	@echo "SDISK ready - use SDISK=mixos-go-v$(VERSION).VISO"

vram: rootfs
	@echo -e "$(CYAN)Building VRAM package...$(NC)"
	# ... vram build logic
```

- [ ] Remove circular dependency
- [ ] Update viso target
- [ ] Update sdisk target
- [ ] Update vram target

---

## Phase 4: Update Build Scripts

### 4.1 Update build-kernel.sh
- [ ] Source common.sh
- [ ] Use kernel/config/mixos_defconfig
- [ ] Output to .tmp/kernel/
- [ ] Create modules tarball

### 4.2 Update build-rootfs.sh
- [ ] Source common.sh
- [ ] Use rootfs/skeleton/
- [ ] Copy mix-cli to /usr/bin/mix
- [ ] Copy packages to /var/lib/mix/packages/
- [ ] Copy installer to /usr/bin/mixos-install
- [ ] Create squashfs

### 4.3 Update build-initramfs.sh
- [ ] Source common.sh
- [ ] Use rootfs/init/init
- [ ] Copy subset of modules
- [ ] Output to artifacts/boot/

### 4.4 Update build-iso.sh
- [ ] Source common.sh
- [ ] Add sanity checks
- [ ] Use correct input paths

### 4.5 Update build-viso.sh
- [ ] Source common.sh
- [ ] Add sanity checks
- [ ] Use correct input paths

---

## Phase 5: Update Makefile

### 5.1 Fix Build Order
```makefile
# Correct dependency chain
all: toolchain-check iso viso

kernel: toolchain-check
mix-cli: toolchain-check
packages: mix-cli
installer: toolchain-check
rootfs: kernel mix-cli packages installer
initramfs: rootfs
iso: rootfs initramfs
viso: rootfs initramfs
```

- [ ] Update all target
- [ ] Fix dependency chain
- [ ] Remove circular dependencies

### 5.2 Update Paths
- [ ] Update CONFIG_FILE path
- [ ] Update INITRAMFS_SRC path
- [ ] Update all script paths

---

## Phase 6: Testing

### 6.1 Unit Tests
- [ ] Test kernel build
- [ ] Test rootfs build
- [ ] Test initramfs build

### 6.2 Integration Tests
- [ ] Test ISO boot in QEMU
- [ ] Test VISO boot in QEMU
- [ ] Test VRAM mode

### 6.3 Verification
- [ ] Verify mix-cli is in rootfs
- [ ] Verify packages are in rootfs
- [ ] Verify installer is in rootfs
- [ ] Verify boot to shell works

---

## Phase 7: Cleanup

- [ ] Remove old directories (configs/, initramfs/)
- [ ] Remove .old files
- [ ] Update documentation
- [ ] Commit changes

---

## Quick Reference: New Paths

| Old Path | New Path |
|----------|----------|
| `configs/kernel/mixos_defconfig` | `kernel/config/mixos_defconfig` |
| `configs/security/` | `rootfs/overlays/security/` |
| `initramfs/init` | `rootfs/init/init` |
| `initramfs/scripts/` | `rootfs/init/scripts/` |
| `src/packages/` | `packages/` |
| `build/patches/` | `kernel/patches/` |

---

## Debugging Rules

1. **Debug satu layer** - Jangan loncat
2. **Kalau error** - Tanya "Layer mana?"
3. **Jika satu rusak** - STOP, jangan lanjut

---

*Document created: 2026-01-06*
*Status: READY FOR IMPLEMENTATION*
