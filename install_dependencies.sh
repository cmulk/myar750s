#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update

pkgs=(
    file
    zstd
    build-essential
    libncurses-dev
    zlib1g-dev
    gawk
    git
    gettext
    libssl-dev
    xsltproc
    rsync
    wget
    unzip
    python3
)

# On Ubuntu 24.04+ (Python 3.12+), python3-distutils is removed and replaced by python3-setuptools
if apt-cache show python3-distutils >/dev/null 2>&1; then
    pkgs+=(python3-distutils)
fi
if apt-cache show python3-setuptools >/dev/null 2>&1; then
    pkgs+=(python3-setuptools)
fi

apt-get install -y "${pkgs[@]}"
