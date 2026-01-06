# Archive Directory

This directory contains old files that have been superseded by the new repository structure.

## Why Archive Instead of Delete?

1. **Reference**: Old implementations can be useful for understanding historical decisions
2. **Rollback**: If new structure has issues, we can reference old code
3. **Migration**: Some code may need to be migrated to new locations

## Contents

### old-configs/
Old configuration files. Superseded by:
- `kernel/config/` - Kernel configuration
- `rootfs/overlays/security/` - Security hardening

### old-initramfs/
Old initramfs init script. Superseded by:
- `rootfs/init/` - New init scripts with better organization

### old-src/packages/
Old package build scripts. Superseded by:
- `packages/` - New package directory at repository root

## New Repository Structure

```
mixos/
├── build/
│   └── scripts/          # Build scripts (common.sh, build-*.sh)
├── kernel/
│   ├── config/           # Kernel configuration
│   └── patches/          # Kernel and BusyBox patches
├── rootfs/
│   ├── init/             # Initramfs init scripts
│   ├── skeleton/         # Base filesystem structure
│   └── overlays/         # Security and customization overlays
├── packages/             # Package build scripts
├── src/
│   ├── mix-cli/          # Mix package manager source
│   └── installer/        # MixOS installer source
└── archive/              # Old files (this directory)
```

## When to Delete

These files can be safely deleted after:
1. New structure is fully tested
2. All functionality is verified working
3. No references to old paths remain in documentation

---
*Archived on: 2026-01-06*
*Reason: Repository restructure for better organization*
