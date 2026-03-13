# PicoClaw Linux VM Bundle

This directory contains the UTM VM bundle for PicoClaw Linux — an Alpine Linux ARM64 VM with [picoclaw](https://github.com/sipeed/picoclaw) pre-installed.

## Contents

- `config.plist` — UTM QEMU VM configuration (tracked in git)
- `picoclaw-alpine.qcow2` — Alpine Linux disk image with picoclaw (not tracked, must be built)

## Building the Disk Image

The `picoclaw-alpine.qcow2` disk image is not included in git due to its size. To generate it:

```bash
# From the repository root:
./scripts/build_picoclaw_image.sh

# Then copy to this bundle:
cp scripts/resources/picoclaw-alpine.qcow2 "Bundled VMs/PicoClaw Linux.utm/"
```

### Requirements

- Docker with buildx support (for cross-platform ARM64 builds)
- `qemu-img` (`brew install qemu` on macOS, `apt install qemu-utils` on Linux)

## VM Specifications

| Setting | Value |
|---------|-------|
| Architecture | ARM64 (aarch64) |
| CPU | Cortex-A57, 2 cores |
| Memory | 512 MB |
| Disk | ~512 MB qcow2 (virtio) |
| Network | Shared (NAT) via virtio-net |
| Display | Terminal (serial console) |
| Hypervisor | Disabled (UTM SE compatible) |
| UEFI | Disabled |

## Usage

Once the VM is running in UTM, log in as `root` (no password) and run:

```
picoclaw onboard    # First-time setup (configure API keys)
picoclaw            # Start the AI assistant
```

API keys can also be configured in `/root/.env`.
