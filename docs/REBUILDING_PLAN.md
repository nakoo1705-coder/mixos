# MixOS-GO Master Rebuild & Refactor Plan
## Complete System Restructuring

> **Status:** OS-level system rebuild
> **Scope:** Kernel → RootFS → ISO/VISO → AI Agent
> **Design Rule:** Deterministic, boring, predictable, autonomous

---

## 📋 Table of Contents

1. [Prinsip Dasar (WAJIB PAHAM)](#prinsip-dasar)
2. [Struktur Repo Canonical](#struktur-repo-canonical)
3. [Gap Analysis: Current vs Target](#gap-analysis)
4. [Build Order (ABSOLUT)](#build-order)
5. [Global Build Contract](#global-build-contract)
6. [Milestone per Layer](#milestone-per-layer)
7. [Identified Bugs](#identified-bugs)
8. [Implementation Plan](#implementation-plan)
9. [Testing Strategy](#testing-strategy)

---

## 🧠 Prinsip Dasar

### ATURAN MUTLAK (Anti-Galau)

| Elemen | Peran |
|--------|-------|
| Makefile | Orchestrator saja (tidak ada logic OS) |
| Shell scripts | Implementasi nyata |
| Kernel | Hardware enabler |
| **RootFS** | **OS SESUNGGUHNYA** |
| Initramfs | Early boot helper |
| ISO/VISO | Media pembungkus |
| AI Agent | User-space intelligence |

### Kebenaran Fundamental

```
❌ SALAH:
  - mix-cli di luar rootfs = sistem kosong
  - packages di artifacts saja = OS tidak punya software
  - ISO/VISO adalah OS = SALAH! Hanya container

✅ BENAR:
  - ROOTFS adalah INTI OS
  - Semua (mix-cli, packages, installer) HARUS masuk ke rootfs
  - ISO/VISO hanya membungkus rootfs
```

> **Jika sesuatu tidak jelas perannya → salah desain**

---

## 🧱 Struktur Repo Canonical

### Target Structure (FINAL - Tidak Boleh Berubah)

```
mixos-go/
├── Makefile                        # Orchestrator only
├── build/
│   ├── scripts/
│   │   ├── common.sh               # Helper functions (WAJIB ADA)
│   │   ├── env.sh                  # Exported vars
│   │   ├── build-kernel.sh
│   │   ├── build-rootfs.sh
│   │   ├── build-initramfs.sh
│   │   ├── build-iso.sh
│   │   ├── build-viso.sh
│   │   ├── gen-modules-dep.sh
│   │   └── sanity-check.sh
│   └── docker/
│       └── Dockerfile.toolchain
├── kernel/
│   ├── config/
│   │   └── mixos_defconfig
│   └── patches/
├── rootfs/
│   ├── skeleton/                   # Base filesystem structure
│   ├── overlays/                   # Additional files
│   ├── init/
│   │   └── init                    # Initramfs init script
│   └── fstab
├── src/
│   ├── mix-cli/
│   ├── installer/
│   └── agent/
│       ├── core/
│       ├── planner/
│       └── executor/
├── packages/
│   └── */build.sh
├── docs/
│   ├── BUILD_FLOW.md
│   ├── ARCHITECTURE.md
│   └── AGENT.md
├── tests/
├── .tmp/                           # BUILD_DIR (ephemeral)
└── artifacts/                      # OUTPUT_DIR (final output only)
```

---

## 📊 Gap Analysis

### Current vs Target Structure

| Current Location | Target Location | Status | Action |
|-----------------|-----------------|--------|--------|
| `configs/kernel/mixos_defconfig` | `kernel/config/mixos_defconfig` | ❌ Wrong | Move |
| `configs/security/` | `rootfs/overlays/security/` | ❌ Wrong | Move |
| `initramfs/init` | `rootfs/init/init` | ❌ Wrong | Move |
| `initramfs/scripts/` | `rootfs/init/scripts/` | ❌ Wrong | Move |
| `src/packages/` | `packages/` | ❌ Wrong | Move |
| `build/patches/` | `kernel/patches/` | ❌ Wrong | Move |
| ❌ Missing | `build/scripts/common.sh` | ❌ Missing | Create |
| ❌ Missing | `build/scripts/env.sh` | ❌ Missing | Create |
| ❌ Missing | `build/scripts/sanity-check.sh` | ❌ Missing | Create |
| ❌ Missing | `rootfs/skeleton/` | ❌ Missing | Create |
| ❌ Missing | `rootfs/fstab` | ❌ Missing | Create |

### Current Build Scripts Analysis

| Script | Status | Issues |
|--------|--------|--------|
| `build-kernel.sh` | ⚠️ Needs fix | Output location inconsistent |
| `build-rootfs.sh` | ⚠️ Needs fix | Missing common.sh, hardcoded paths |
| `build-initramfs.sh` | ⚠️ Needs fix | Wrong source location |
| `build-iso.sh` | ⚠️ Needs fix | Missing sanity checks |
| `build-viso.sh` | ⚠️ Needs fix | Missing sanity checks |

---

## 🔥 Build Order (ABSOLUT - TIDAK BOLEH DIBALIK)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BUILD ORDER (STEP-BY-STEP)                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1️⃣ TOOLCHAIN-CHECK                                                  │
│     └── Verify: gcc, make, go, qemu, squashfs, cpio                  │
│     └── Output: none (validation only)                               │
│                                                                      │
│  2️⃣ KERNEL                                                           │
│     └── Input: kernel/config/mixos_defconfig                         │
│     └── Output: .tmp/kernel/vmlinuz-mixos                            │
│     └── Output: .tmp/kernel/modules/                                 │
│     ⚠️ HARUS DULUAN karena rootfs butuh modules                      │
│                                                                      │
│  3️⃣ MIX-CLI                                                          │
│     └── Input: src/mix-cli/                                          │
│     └── Output: artifacts/mix (STAGING)                              │
│     ⚠️ Ini BELUM final, hanya staging                                │
│                                                                      │
│  4️⃣ PACKAGES                                                         │
│     └── Input: packages/*/build.sh                                   │
│     └── Output: artifacts/packages/* (STAGING)                       │
│     ⚠️ Ini BELUM final, hanya staging                                │
│                                                                      │
│  5️⃣ INSTALLER                                                        │
│     └── Input: src/installer/                                        │
│     └── Output: artifacts/mixos-install (STAGING)                    │
│                                                                      │
│  6️⃣ ROOTFS (TAHAP PALING PENTING) 🔥                                 │
│     └── GABUNGKAN SEMUA:                                             │
│         - kernel modules                                             │
│         - mix-cli                                                    │
│         - packages                                                   │
│         - installer                                                  │
│         - init system                                                │
│         - /etc /bin /sbin /usr                                       │
│     └── Output: .tmp/rootfs/                                         │
│     └── Output: .tmp/rootfs.squashfs                                 │
│     📌 Setelah ini: OS SUDAH HIDUP (walau belum bootable)            │
│                                                                      │
│  7️⃣ INITRAMFS                                                        │
│     └── Input: rootfs/init/init                                      │
│     └── Input: kernel modules (subset)                               │
│     └── Output: artifacts/boot/initramfs-mixos.img                   │
│                                                                      │
│  8️⃣ ISO                                                              │
│     └── Input: kernel, initramfs, rootfs.squashfs                    │
│     └── Output: artifacts/mixos-go-vX.iso                            │
│                                                                      │
│  9️⃣ VISO                                                             │
│     └── Input: kernel, initramfs, rootfs.squashfs                    │
│     └── Output: artifacts/mixos-go-vX.viso                           │
│                                                                      │
│  ⚠️ JIKA SATU RUSAK → STOP, JANGAN LANJUT                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Identified Problems

### 🔴 Problem 1: Device Path Mismatch (CRITICAL)

**Location:** `initramfs/init` line 537-539

**Current Code:**
```bash
setup_rootfs_virtio() {
    setup_rootfs_sdisk "/dev/vda"  # ❌ WRONG!
}
```

**Problem:**
- VISO dibuat dengan partition table (MBR)
- `/dev/vda` = whole disk dengan partition table
- `/dev/vda1` = partition 1 dengan ext4 filesystem
- Init mencoba mount `/dev/vda` sebagai ext4 → **GAGAL**

**Evidence dari build-viso.sh:**
```bash
parted -s "$VISO_RAW" \
    mklabel msdos \
    mkpart primary ext4 1MiB 100% \
    set 1 boot on
```

**Comparison dengan setup_rootfs_disk():**
```bash
setup_rootfs_disk() {
    local device="/dev/sda"
    
    # Try partitions first ✅ CORRECT!
    for part in "${device}1" "${device}2" "$device"; do
        if [ -b "$part" ]; then
            if setup_rootfs_sdisk "$part"; then
                return 0
            fi
        fi
    done
    
    return 1
}
```

**Fix Required:**
```bash
setup_rootfs_virtio() {
    local device="/dev/vda"
    
    # Try partitions first (VISO has partition table)
    for part in "${device}1" "${device}2" "$device"; do
        if [ -b "$part" ]; then
            if setup_rootfs_sdisk "$part"; then
                return 0
            fi
        fi
    done
    
    return 1
}
```

---

### 🟠 Problem 2: Circular Dependency di Makefile (HIGH)

**Location:** `Makefile` line 288, 293

**Current Code:**
```makefile
viso: rootfs initramfs sdisk vram    # line 288
sdisk: viso                           # line 293
```

**Problem:**
- `viso` depends on `sdisk`
- `sdisk` depends on `viso`
- **CIRCULAR DEPENDENCY!**

**Impact:**
- Make tidak bisa resolve dependency dengan benar
- Build order tidak predictable
- Potential infinite loop atau random failures

**Analysis:**
- `sdisk` sebenarnya bukan artifact yang perlu di-build
- `sdisk` adalah **alias/mode boot** untuk VISO
- `vram` adalah output tambahan (squashfs), bukan dependency

**Fix Required:**
```makefile
# viso depends on rootfs and initramfs only
viso: rootfs initramfs
    @echo "Building VISO..."
    @bash build/scripts/build-viso.sh

# sdisk is just an alias, depends on viso being built
sdisk: viso
    @echo "SDISK is an alias for VISO with SDISK boot parameter"
    @echo "Use: SDISK=mixos-go-v$(VERSION).VISO"

# vram is a separate output, depends on rootfs
vram: rootfs
    @echo "Building VRAM package..."
    # ... build vram
```

---

### 🟡 Problem 3: Init Script Complexity (MEDIUM)

**Location:** `initramfs/init`

**Issues:**
1. Terlalu banyak mode boot dengan logic yang berbeda-beda
2. Inconsistent handling antara virtio, disk, nvme, cdrom
3. Hard to debug dan maintain

**Current Modes:**
- `sdisk` - SDISK parameter specified
- `root` - root= parameter specified
- `virtio` - /dev/vda detected
- `disk` - /dev/sda detected
- `nvme` - /dev/nvme0n1 detected
- `cdrom` - /dev/sr0 detected

**Recommendation:**
- Unify device detection logic
- Single function untuk mount any device
- Better error messages

---

### 🟡 Problem 4: Output Mixing (MEDIUM)

**Location:** `initramfs/init` various functions

**Issue:**
Functions use `echo` for both:
1. Return values (captured by `$()`)
2. Log messages

**Example:**
```bash
rootfs_mount=$(setup_rootfs_virtio)
```

If `setup_rootfs_virtio()` prints log messages to stdout, they get mixed with return value.

**Current Mitigation:**
Log functions already use `>&2`:
```bash
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1" >&2
}
```

**But:** Some functions still echo to stdout for non-return purposes.

---

## Root Cause Analysis

### Why Kernel Panic / Rootfs Not Found?

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ROOT CAUSE CHAIN                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. VISO dibuat dengan partition table                               │
│     └── /dev/vda = disk, /dev/vda1 = partition                       │
│                                                                      │
│  2. Init script mencoba mount /dev/vda sebagai ext4                  │
│     └── GAGAL karena /dev/vda bukan filesystem                       │
│                                                                      │
│  3. Fallback ke filesystem lain (squashfs, iso9660, vfat)            │
│     └── Semua GAGAL karena /dev/vda tetap bukan filesystem           │
│                                                                      │
│  4. rootfs_squashfs tidak ditemukan                                  │
│     └── Karena mount gagal, tidak bisa access /rootfs/               │
│                                                                      │
│  5. setup_rootfs_sdisk() return 1 (failure)                          │
│     └── rootfs_mount kosong                                          │
│                                                                      │
│  6. do_switch_root() gagal                                           │
│     └── "No init found in new root"                                  │
│                                                                      │
│  7. rescue_shell() dipanggil                                         │
│     └── Atau kernel panic jika rescue shell juga gagal               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Rebuilding Strategy

### Phase 1: Fix Critical Issues (Priority: IMMEDIATE)

1. **Fix Device Path in setup_rootfs_virtio()**
   - Try partitions before whole disk
   - Consistent dengan setup_rootfs_disk()

2. **Fix Makefile Circular Dependency**
   - Remove sdisk dan vram dari viso dependencies
   - Clarify what is artifact vs alias

### Phase 2: Improve Reliability (Priority: HIGH)

1. **Unify Device Detection**
   - Single function untuk detect dan mount any device
   - Better partition handling

2. **Improve Error Messages**
   - Clear indication of what failed
   - Actionable suggestions

### Phase 3: Simplify & Clean Up (Priority: MEDIUM)

1. **Reduce Init Script Complexity**
   - Consolidate similar functions
   - Remove dead code

2. **Add Debug Mode**
   - Verbose output when debug=1
   - Step-by-step progress

---

## Implementation Plan

### Step 1: Fix setup_rootfs_virtio() [CRITICAL]

**File:** `initramfs/init`

**Change:**
```bash
# OLD (BROKEN)
setup_rootfs_virtio() {
    setup_rootfs_sdisk "/dev/vda"
}

# NEW (FIXED)
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

### Step 2: Fix Makefile Dependencies [HIGH]

**File:** `Makefile`

**Change:**
```makefile
# OLD (CIRCULAR)
viso: rootfs initramfs sdisk vram
sdisk: viso

# NEW (FIXED)
viso: rootfs initramfs
    @echo -e "$(CYAN)Building VISO (Virtual ISO) image...$(NC)"
    @bash build/scripts/build-viso.sh
    @echo -e "$(GREEN)✓ VISO generated: $(VISO_NAME).viso$(NC)"

sdisk: viso
    @echo -e "$(CYAN)SDISK mode ready$(NC)"
    @echo "SDISK is an alias for VISO with SDISK boot parameter"
    @echo "Use: SDISK=$(VISO_NAME).VISO"

vram: rootfs
    @echo -e "$(CYAN)Building VRAM-optimized package...$(NC)"
    # ... existing vram build logic
```

### Step 3: Add Partition Detection to setup_rootfs_nvme() [HIGH]

**File:** `initramfs/init`

**Current code already correct, but verify:**
```bash
setup_rootfs_nvme() {
    local device="/dev/nvme0n1"
    
    for part in "${device}p1" "${device}p2" "$device"; do
        if [ -b "$part" ]; then
            if setup_rootfs_sdisk "$part"; then
                return 0
            fi
        fi
    done
    
    return 1
}
```

---

## Testing Strategy

### Test 1: Unit Test - Device Detection

```bash
# In rescue shell or test environment
# Verify partition detection works

# Check what devices exist
ls -la /dev/vd* /dev/sd* /dev/nvme*

# Verify partition table
fdisk -l /dev/vda

# Try mount partition
mount -t ext4 /dev/vda1 /mnt/test
ls /mnt/test/
```

### Test 2: Integration Test - VISO Boot

```bash
# Build VISO
make clean
make viso

# Test standalone boot
qemu-system-x86_64 \
    -drive file=artifacts/mixos-go-v1.0.0.viso,format=qcow2,if=virtio \
    -m 2G \
    -nographic

# Test external kernel boot
qemu-system-x86_64 \
    -kernel artifacts/boot/vmlinuz-mixos \
    -initrd artifacts/boot/initramfs-mixos.img \
    -drive file=artifacts/mixos-go-v1.0.0.viso,format=qcow2,if=virtio \
    -append "console=ttyS0" \
    -m 2G \
    -nographic
```

### Test 3: VRAM Mode Test

```bash
qemu-system-x86_64 \
    -kernel artifacts/boot/vmlinuz-mixos \
    -initrd artifacts/boot/initramfs-mixos.img \
    -drive file=artifacts/mixos-go-v1.0.0.viso,format=qcow2,if=virtio \
    -append "console=ttyS0 VRAM=auto" \
    -m 4G \
    -nographic
```

---

## Rollback Plan

Jika fix menyebabkan masalah baru:

1. **Git Revert**
   ```bash
   git revert HEAD
   ```

2. **Restore Original Files**
   - `initramfs/init` - restore setup_rootfs_virtio()
   - `Makefile` - restore dependencies

3. **Alternative Approach**
   - Buat VISO tanpa partition table (whole disk = filesystem)
   - Ini akan membuat /dev/vda langsung bisa di-mount

---

## Checklist Sebelum Implementasi

- [ ] Backup current working state
- [ ] Understand all changes to be made
- [ ] Have test environment ready
- [ ] Have rollback plan ready
- [ ] Review changes with user before commit

---

## Summary

**Root Cause:** Init script mencoba mount `/dev/vda` (whole disk) sebagai ext4, padahal VISO dibuat dengan partition table sehingga filesystem ada di `/dev/vda1`.

**Fix:** Ubah `setup_rootfs_virtio()` untuk mencoba partitions (`/dev/vda1`, `/dev/vda2`) sebelum whole disk (`/dev/vda`).

**Additional Fix:** Remove circular dependency di Makefile (`viso` ↔ `sdisk`).

---

*Document created: 2026-01-06*
*Author: OpenHands AI Assistant*
*Status: READY FOR REVIEW*
