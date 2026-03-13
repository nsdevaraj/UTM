#!/bin/bash
#
# build_picoclaw_image.sh
#
# Builds an Alpine Linux ARM64 disk image with picoclaw pre-installed.
# Output: scripts/resources/picoclaw-alpine.qcow2
#
# Requirements:
#   - Podman (for cross-platform builds on macOS/Linux)
#   - qemu-img (from qemu-utils on Linux, or `brew install qemu` on macOS)
#
# Usage:
#   ./scripts/build_picoclaw_image.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/resources"
OUTPUT_QCOW2="$RESOURCES_DIR/picoclaw-alpine.qcow2"
IMAGE_SIZE_MB=512
PODMAN_IMAGE_TAG="picoclaw-alpine-builder"

echo "=== PicoClaw Alpine ARM64 Image Builder ==="
echo ""

# Check dependencies
if ! command -v podman &> /dev/null; then
    echo "Error: podman is required. Install Podman Desktop or Podman CLI."
    exit 1
fi

if ! command -v qemu-img &> /dev/null; then
    echo "Error: qemu-img is required."
    echo "  macOS:  brew install qemu"
    echo "  Linux:  apt install qemu-utils (or equivalent)"
    exit 1
fi

mkdir -p "$RESOURCES_DIR"

# Step 1: Build the Podman image (cross-platform ARM64)
echo "[1/5] Building Alpine ARM64 rootfs via Podman..."
podman build \
    --platform linux/arm64 \
    -f "$SCRIPT_DIR/Dockerfile.picoclaw" \
    -t "$PODMAN_IMAGE_TAG" \
    "$REPO_DIR"

# Step 2: Export the rootfs as a tar archive
echo "[2/5] Exporting rootfs from Podman image..."
CONTAINER_ID=$(podman create --platform linux/arm64 "$PODMAN_IMAGE_TAG" /bin/true)
ROOTFS_TAR="$RESOURCES_DIR/picoclaw-rootfs.tar"
podman export "$CONTAINER_ID" -o "$ROOTFS_TAR"
podman rm "$CONTAINER_ID" > /dev/null

# Step 3: Create a raw ext4 image and populate it
echo "[3/5] Creating ext4 disk image (${IMAGE_SIZE_MB}MB)..."
RAW_IMAGE="$RESOURCES_DIR/picoclaw-alpine.raw"
rm -f "$RAW_IMAGE"

# Use Podman to populate the ext4 image reliably across platforms without loop mounts
echo "  (Using Podman to create ext4 image)"
podman run --rm --platform linux/arm64 \
    -v "$RESOURCES_DIR:/output" \
    alpine:3.19 sh -c "
        apk add --no-cache e2fsprogs tar &&
        mkdir -p /mnt/rootfs &&
        tar -xf /output/picoclaw-rootfs.tar -C /mnt/rootfs &&
        dd if=/dev/zero of=/output/picoclaw-alpine.raw bs=1M count=$IMAGE_SIZE_MB &&
        mkfs.ext4 -d /mnt/rootfs -F -L picoclaw /output/picoclaw-alpine.raw
    "

# Step 4: Convert raw image to qcow2
echo "[4/5] Converting to qcow2..."
rm -f "$OUTPUT_QCOW2"
qemu-img convert -c -f raw -O qcow2 "$RAW_IMAGE" "$OUTPUT_QCOW2"

# Step 5: Cleanup
echo "[5/5] Cleaning up temporary files..."
rm -f "$RAW_IMAGE" "$ROOTFS_TAR"
podman rmi "$PODMAN_IMAGE_TAG" > /dev/null 2>&1 || true

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_QCOW2"
QCOW2_SIZE=$(du -h "$OUTPUT_QCOW2" | cut -f1)
echo "Size: $QCOW2_SIZE"
echo ""
echo "Copy to VM bundle:"
echo "  cp $OUTPUT_QCOW2 'Bundled VMs/PicoClaw Linux.utm/picoclaw-alpine.qcow2'"
