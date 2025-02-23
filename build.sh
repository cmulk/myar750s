#!/bin/bash

## build dependencies
# apt install -y file build-essential libncurses-dev zlib1g-dev gawk git gettext libssl-dev xsltproc rsync wget unzip python3 python3-distutils

set -eou pipefail

OPENWRT_VERSION=${OPENWRT_VERSION:-24.10.0}
BASE_PACKAGES=${BASE_PACKAGES:-"luci ip-tiny ip-bridge nano tcpdump"}
EXTRA_PACKAGES=${EXTRA_PACKAGES:-"-dnsmasq dnsmasq-full luci-app-travelmate luci-app-pbr luci-proto-wireguard wireguard-tools"}
PROFILE=${PROFILE:-"glinet_gl-ar750s-nor-nand"}

wget https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/ath79/nand/openwrt-imagebuilder-$OPENWRT_VERSION-ath79-nand.Linux-x86_64.tar.zst -O imagebuilder.tar.zst

tar -xaf imagebuilder.tar.zst --strip-components 1

make image PROFILE="$PROFILE" PACKAGES="${BASE_PACKAGES} ${EXTRA_PACKAGES}"

