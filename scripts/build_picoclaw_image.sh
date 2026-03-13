#!/bin/bash
#
# build_picoclaw_image.sh
#
# Builds an Alpine Linux ARM64 disk image with picoclaw pre-installed.
# Output: scripts/resources/picoclaw-alpine.qcow2
#
# Requirements:
#   - Docker with buildx support (for cross-platform builds on macOS/Linux)
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
DOCKER_IMAGE_TAG="picoclaw-alpine-builder"

echo "=== PicoClaw Alpine ARM64 Image Builder ==="
echo ""

# Check dependencies
if ! command -v docker &> /dev/null; then
    echo "Error: docker is required. Install Docker Desktop or Docker Engine."
    exit 1
fi

if ! command -v qemu-img &> /dev/null; then
    echo "Error: qemu-img is required."
    echo "  macOS:  brew install qemu"
    echo "  Linux:  apt install qemu-utils (or equivalent)"
    exit 1
fi

mkdir -p "$RESOURCES_DIR"

# Step 1: Build the Docker image (cross-platform ARM64)
echo "[1/5] Building Alpine ARM64 rootfs via Docker buildx..."
docker buildx build \
    --platform linux/arm64 \
    -f "$SCRIPT_DIR/Dockerfile.picoclaw" \
    -t "$DOCKER_IMAGE_TAG" \
    --load \
    "$REPO_DIR"

# Step 2: Export the rootfs as a tar archive
echo "[2/5] Exporting rootfs from Docker image..."
CONTAINER_ID=$(docker create --platform linux/arm64 "$DOCKER_IMAGE_TAG" /bin/true)
ROOTFS_TAR="$RESOURCES_DIR/picoclaw-rootfs.tar"
docker export "$CONTAINER_ID" -o "$ROOTFS_TAR"
docker rm "$CONTAINER_ID" > /dev/null

# Step 3: Create a raw ext4 image and populate it
echo "[3/5] Creating ext4 disk image (${IMAGE_SIZE_MB}MB)..."
RAW_IMAGE="$RESOURCES_DIR/picoclaw-alpine.raw"
rm -f "$RAW_IMAGE"

if [[ "$(uname)" == "Linux" ]]; then
    # On Linux, we can use loop mount directly
    dd if=/dev/zero of="$RAW_IMAGE" bs=1M count="$IMAGE_SIZE_MB" status=progress
    mkfs.ext4 -F -L picoclaw "$RAW_IMAGE"

    MOUNT_DIR=$(mktemp -d)
    sudo mount -o loop "$RAW_IMAGE" "$MOUNT_DIR"
    sudo tar -xf "$ROOTFS_TAR" -C "$MOUNT_DIR"
    sudo umount "$MOUNT_DIR"
    rmdir "$MOUNT_DIR"
else
    # On macOS, use Docker to populate the ext4 image
    echo "  (Using Docker to create ext4 image on macOS)"
    docker run --rm --platform linux/arm64 \
        -v "$RESOURCES_DIR:/output" \
        alpine:3.19 sh -c "
            apk add --no-cache e2fsprogs tar &&
            dd if=/dev/zero of=/output/picoclaw-alpine.raw bs=1M count=$IMAGE_SIZE_MB &&
            mkfs.ext4 -F -L picoclaw /output/picoclaw-alpine.raw &&
            mkdir -p /mnt/rootfs &&
            mount -o loop /output/picoclaw-alpine.raw /mnt/rootfs &&
            tar -xf /output/picoclaw-rootfs.tar -C /mnt/rootfs &&
            umount /mnt/rootfs
        "
fi

# Step 4: Convert raw image to qcow2
echo "[4/5] Converting to qcow2..."
rm -f "$OUTPUT_QCOW2"
qemu-img convert -c -f raw -O qcow2 "$RAW_IMAGE" "$OUTPUT_QCOW2"

# Step 5: Cleanup
echo "[5/5] Cleaning up temporary files..."
rm -f "$RAW_IMAGE" "$ROOTFS_TAR"
docker rmi "$DOCKER_IMAGE_TAG" > /dev/null 2>&1 || true

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_QCOW2"
QCOW2_SIZE=$(du -h "$OUTPUT_QCOW2" | cut -f1)
echo "Size: $QCOW2_SIZE"
echo ""
echo "Copy to VM bundle:"
echo "  cp $OUTPUT_QCOW2 'Bundled VMs/PicoClaw Linux.utm/picoclaw-alpine.qcow2'"
