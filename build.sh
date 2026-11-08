#!/bin/bash

set -euo pipefail

# Default values
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
IMAGE="${IMAGE:-ath79-nand}"
TARGET="${TARGET:-}"
SUBTARGET="${SUBTARGET:-}"
PROFILE="${PROFILE:-glinet_gl-ar750s-nor-nand}"
BASE_PACKAGES="${BASE_PACKAGES:-"luci ip-full ip-bridge nano tcpdump"}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-"-dnsmasq dnsmasq-full luci-app-travelmate luci-app-pbr luci-proto-wireguard wireguard-tools"}"
PACKAGES="${PACKAGES:-"${BASE_PACKAGES} ${EXTRA_PACKAGES}"}"
BIN_DIR="${BIN_DIR:-bin}"
FILES="${FILES:-}"
DISABLED_SERVICES="${DISABLED_SERVICES:-}"
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-}"
CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-ghcr.io/openwrt/imagebuilder}"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build OpenWrt custom firmware images using the official OpenWrt ImageBuilder Docker image.

Options:
  -i, --image <image>               Target image in <target>-<subtarget> format (e.g., ath79-nand, ramips-mt7621)
  -p, --profile <profile>           Target device profile (e.g., glinet_gl-ar750s-nor-nand)
  -v, --version <version>           OpenWrt version (e.g., 25.12.5)
  -k, --packages <packages>         Space-separated list of packages to embed or exclude (-pkg)
  -d, --bin-dir <dir>               Output directory for generated binaries (default: bin)
  -f, --files <dir>                 Directory containing custom files to include in image
  -s, --disabled-services <list>    Space-separated list of services to disable
  -r, --rootfs-size <mb>            Root filesystem partition size in megabytes
  -h, --help                        Show this help message

All options can also be provided via environment variables (IMAGE, PROFILE, PACKAGES, OPENWRT_VERSION, CONTAINER_REGISTRY, etc.).
EOF
}

# Parse CLI arguments (override environment variables)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -v|--version)
            OPENWRT_VERSION="$2"
            shift 2
            ;;
        -k|--packages)
            PACKAGES="$2"
            shift 2
            ;;
        -d|--bin-dir)
            BIN_DIR="$2"
            shift 2
            ;;
        -f|--files)
            FILES="$2"
            shift 2
            ;;
        -s|--disabled-services)
            DISABLED_SERVICES="$2"
            shift 2
            ;;
        -r|--rootfs-size)
            ROOTFS_PARTSIZE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Derive TARGET and SUBTARGET
if [ -z "$TARGET" ] || [ -z "$SUBTARGET" ]; then
    TARGET="${IMAGE%%-*}"
    SUBTARGET="${IMAGE#*-}"
fi
IMAGE="${TARGET}-${SUBTARGET}"
DOCKER_IMAGE="${CONTAINER_REGISTRY}:${IMAGE}-${OPENWRT_VERSION}"

echo "========================================"
echo "OpenWrt Image Build Configuration"
echo "========================================"
echo "OpenWrt Version:   $OPENWRT_VERSION"
echo "Image Target:      $IMAGE (Target: $TARGET, Subtarget: $SUBTARGET)"
echo "Docker Image:      $DOCKER_IMAGE"
echo "Device Profile:    $PROFILE"
echo "Packages:          $PACKAGES"
echo "Output Directory:  $BIN_DIR"
[ -n "$FILES" ] && echo "Custom Files:      $FILES"
[ -n "$DISABLED_SERVICES" ] && echo "Disabled Services: $DISABLED_SERVICES"
[ -n "$ROOTFS_PARTSIZE" ] && echo "Rootfs Size (MB):  $ROOTFS_PARTSIZE"
echo "========================================"

mkdir -p "$BIN_DIR"
chmod 777 "$BIN_DIR"
ABS_BIN_DIR="$(realpath "$BIN_DIR")"

DOCKER_ARGS=(
    --rm
    -v "${ABS_BIN_DIR}:/output"
    -e PROFILE="$PROFILE"
    -e PACKAGES="$PACKAGES"
    -e DISABLED_SERVICES="$DISABLED_SERVICES"
    -e ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"
)

if [ -n "$FILES" ]; then
    if [ ! -d "$FILES" ]; then
        echo "Error: Custom files directory '$FILES' does not exist." >&2
        exit 1
    fi
    DOCKER_ARGS+=(-v "$(realpath "$FILES"):/builder/files:ro" -e FILES="/builder/files")
elif [ -d "files" ]; then
    DOCKER_ARGS+=(-v "$(realpath files):/builder/files:ro" -e FILES="/builder/files")
fi

echo "Running ImageBuilder in Docker ($DOCKER_IMAGE)..."
docker run "${DOCKER_ARGS[@]}" "$DOCKER_IMAGE" bash -c '
    set -euo pipefail

    if [ ! -d ./scripts ]; then
        ./setup.sh
    fi

    MAKE_ARGS=(
        PROFILE="$PROFILE"
        PACKAGES="$PACKAGES"
    )

    if [ -n "${FILES:-}" ]; then
        MAKE_ARGS+=(FILES="$FILES")
    fi

    if [ -n "${DISABLED_SERVICES:-}" ]; then
        MAKE_ARGS+=(DISABLED_SERVICES="$DISABLED_SERVICES")
    fi

    if [ -n "${ROOTFS_PARTSIZE:-}" ]; then
        MAKE_ARGS+=(ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE")
    fi

    echo "Running make image..."
    make image "${MAKE_ARGS[@]}"

    shopt -s nullglob
    bin_files=(bin/targets/*/*/*.bin)
    if [ ${#bin_files[@]} -eq 0 ]; then
        echo "Error: No .bin image files were found in bin/targets/" >&2
        exit 1
    fi

    echo "Copying images to output directory..."
    for file in "${bin_files[@]}"; do
        fname=$(basename "$file")
        # Strip openwrt-<version>-<target>-<subtarget>- prefix to match standard release names
        stripped="${fname#openwrt-*-*-*-}"
        cp -f "$file" "/output/$stripped"
        chmod 0666 "/output/$stripped"
        echo "Created: $stripped"
    done
'

echo "Build completed successfully!"
