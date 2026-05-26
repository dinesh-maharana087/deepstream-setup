#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "🔍 Checking prerequisites..."

echo "🔍 Validating Ubuntu version..."
UBUNTU="$(check_ubuntu_version)"

if [[ "$UBUNTU" != "$UBUNTU_VERSION" ]]; then
    echo "❌ Unsupported Ubuntu version: $UBUNTU"
    echo "Expected Ubuntu version: $UBUNTU_VERSION"
    exit 1
fi

echo "✅ Ubuntu version matched: $UBUNTU"

echo "🔍 Validating NVIDIA driver..."

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "❌ NVIDIA driver not found."
    echo "Please install NVIDIA driver first."
    exit 1
fi

INSTALLED_DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | cut -d'.' -f1)"

if [[ -z "$INSTALLED_DRIVER_VERSION" ]]; then
    echo "❌ Unable to detect NVIDIA driver version."
    exit 1
fi

echo "Detected NVIDIA driver major version: $INSTALLED_DRIVER_VERSION"
echo "Required minimum driver major version: $NVIDIA_DRIVER_MIN_VERSION"

if (( INSTALLED_DRIVER_VERSION < NVIDIA_DRIVER_MIN_VERSION )); then
    echo "❌ NVIDIA driver version is too old."
    echo "Installed: $INSTALLED_DRIVER_VERSION"
    echo "Required minimum: $NVIDIA_DRIVER_MIN_VERSION"
    exit 1
fi

echo "✅ NVIDIA driver validation passed."

PACKAGES=(
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
    protobuf-compiler
    gcc
    make
    git
    python3
    curl
)

MISSING=()

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
    echo "✅ All prerequisites already installed."
    exit 0
fi

echo "Installing missing packages: ${MISSING[*]}"

sudo apt update

if [ "$STRICT_MODE" = true ]; then
    echo "⚠️ Strict mode enabled"
    sudo apt install -y --no-install-recommends "${MISSING[@]}"
else
    sudo apt install -y "${MISSING[@]}"
fi

echo "✅ Prerequisites installation completed."