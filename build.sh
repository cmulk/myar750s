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
DL_DIR="${DL_DIR:-dl}"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build OpenWrt custom firmware images using the official OpenWrt ImageBuilder.

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

All options can also be provided via environment variables (IMAGE, PROFILE, PACKAGES, OPENWRT_VERSION, etc.).
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

echo "========================================"
echo "OpenWrt Image Build Configuration"
echo "========================================"
echo "OpenWrt Version:   $OPENWRT_VERSION"
echo "Image Target:      $IMAGE (Target: $TARGET, Subtarget: $SUBTARGET)"
echo "Device Profile:    $PROFILE"
echo "Packages:          $PACKAGES"
echo "Output Directory:  $BIN_DIR"
[ -n "$FILES" ] && echo "Custom Files:      $FILES"
[ -n "$DISABLED_SERVICES" ] && echo "Disabled Services: $DISABLED_SERVICES"
[ -n "$ROOTFS_PARTSIZE" ] && echo "Rootfs Size (MB):  $ROOTFS_PARTSIZE"
echo "========================================"

# Prepare download directory
mkdir -p "$DL_DIR"

BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}"
IB_PREFIX="openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64"

ARCHIVE=""
if [ -f "${DL_DIR}/${IB_PREFIX}.tar.zst" ]; then
    ARCHIVE="${DL_DIR}/${IB_PREFIX}.tar.zst"
elif [ -f "${DL_DIR}/${IB_PREFIX}.tar.xz" ]; then
    ARCHIVE="${DL_DIR}/${IB_PREFIX}.tar.xz"
else
    # Check .tar.zst first, fallback to .tar.xz
    ZST_URL="${BASE_URL}/${IB_PREFIX}.tar.zst"
    XZ_URL="${BASE_URL}/${IB_PREFIX}.tar.xz"

    echo "Downloading ImageBuilder..."
    if wget -q --spider "$ZST_URL"; then
        ARCHIVE="${DL_DIR}/${IB_PREFIX}.tar.zst"
        wget -c "$ZST_URL" -O "${ARCHIVE}.tmp"
        mv "${ARCHIVE}.tmp" "$ARCHIVE"
    elif wget -q --spider "$XZ_URL"; then
        ARCHIVE="${DL_DIR}/${IB_PREFIX}.tar.xz"
        wget -c "$XZ_URL" -O "${ARCHIVE}.tmp"
        mv "${ARCHIVE}.tmp" "$ARCHIVE"
    else
        echo "Error: ImageBuilder archive not found at $ZST_URL or $XZ_URL" >&2
        exit 1
    fi
fi

# Clean and extract ImageBuilder
BUILD_DIR="builder"
echo "Extracting $(basename "$ARCHIVE") into $BUILD_DIR..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
tar -xaf "$ARCHIVE" -C "$BUILD_DIR" --strip-components 1

# Prepare make arguments
MAKE_ARGS=(
    PROFILE="$PROFILE"
    PACKAGES="$PACKAGES"
)

if [ -n "$FILES" ]; then
    if [ ! -d "$FILES" ]; then
        echo "Error: Custom files directory '$FILES' does not exist." >&2
        exit 1
    fi
    MAKE_ARGS+=(FILES="$(realpath "$FILES")")
elif [ -d "files" ]; then
    MAKE_ARGS+=(FILES="$(realpath files)")
fi

if [ -n "$DISABLED_SERVICES" ]; then
    MAKE_ARGS+=(DISABLED_SERVICES="$DISABLED_SERVICES")
fi

if [ -n "$ROOTFS_PARTSIZE" ]; then
    MAKE_ARGS+=(ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE")
fi

# Build image
echo "Running make image..."
make -C "$BUILD_DIR" image "${MAKE_ARGS[@]}"

# Copy generated images to output directory
mkdir -p "$BIN_DIR"

shopt -s nullglob
bin_files=("$BUILD_DIR"/bin/targets/*/*/*.bin)
if [ ${#bin_files[@]} -eq 0 ]; then
    echo "Error: No .bin image files were found in $BUILD_DIR/bin/targets/" >&2
    exit 1
fi

echo "Copying images to $BIN_DIR..."
for file in "${bin_files[@]}"; do
    fname=$(basename "$file")
    # Strip openwrt-<version>-<target>-<subtarget>- prefix to match standard release names
    stripped="${fname#openwrt-*-*-*-}"
    cp -f "$file" "$BIN_DIR/$stripped"
    echo "Created: $BIN_DIR/$stripped"
done
shopt -u nullglob

echo "Build completed successfully!"
