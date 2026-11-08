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

# In Ubuntu 24.04+ (Python 3.12+), python3-distutils is obsoleted with no candidate, replaced by python3-setuptools.
# Check for an actual installation candidate before adding.
if apt-cache policy python3-distutils 2>/dev/null | grep -q 'Candidate: [^(]'; then
    pkgs+=(python3-distutils)
fi
if apt-cache policy python3-setuptools 2>/dev/null | grep -q 'Candidate: [^(]'; then
    pkgs+=(python3-setuptools)
fi

apt-get install -y "${pkgs[@]}"
