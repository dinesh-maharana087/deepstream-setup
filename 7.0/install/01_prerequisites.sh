#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "Checking prerequisites..."

# Validate required env vars
required_vars=(
    DEEPSTREAM_VERSION
    UBUNTU_VERSION
    STRICT_MODE
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Missing required variable in versions.env: $var"
        exit 1
    fi
done

# Validate Ubuntu version
UBUNTU="$(check_ubuntu_version)"

if [[ "$UBUNTU" != "$UBUNTU_VERSION" ]]; then
    echo "Unsupported Ubuntu version: $UBUNTU (expected: $UBUNTU_VERSION)"
    exit 1
fi

# Check required commands
for cmd in apt dpkg sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd"
        exit 1
    fi
done

PACKAGES=(
    curl
    gcc
    git
    make
    pkg-config
    protobuf-compiler
    python3
    python3-pip
    python3-venv

    libssl3
    libssl-dev
    libgles2-mesa-dev

    libgstreamer1.0-0
    gstreamer1.0-tools
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
    gstreamer1.0-libav
    libgstreamer-plugins-base1.0-dev
    libgstrtspserver-1.0-0

    libjansson4
    libyaml-cpp-dev
    libjsoncpp-dev
)

MISSING=()

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "All prerequisites already installed."
    exit 0
fi

echo "Installing missing packages: ${MISSING[*]}"

sudo apt update

if [[ "$STRICT_MODE" == "true" ]]; then
    echo "Strict mode enabled"
    sudo apt install -y --no-install-recommends "${MISSING[@]}"
else
    sudo apt install -y "${MISSING[@]}"
fi

echo "Prerequisite installation complete."