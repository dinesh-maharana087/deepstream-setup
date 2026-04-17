#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "Checking TensorRT..."

required_vars=(
    UBUNTU_VERSION
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Missing required variable in versions.env: $var"
        exit 1
    fi
done

UBUNTU="$(check_ubuntu_version)"
if [[ "$UBUNTU" != "$UBUNTU_VERSION" ]]; then
    echo "Unsupported Ubuntu version: $UBUNTU (expected: $UBUNTU_VERSION)"
    exit 1
fi

for cmd in apt-get dpkg-query sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd"
        exit 1
    fi
done

# Prefer explicit package version; fall back to logical version if user chose not to split them.
if [[ -n "${TENSORRT_PKG_VERSION:-}" ]]; then
    TRT_PKG_VERSION="${TENSORRT_PKG_VERSION}"
elif [[ -n "${TENSORRT_VERSION:-}" ]]; then
    TRT_PKG_VERSION="${TENSORRT_VERSION}"
else
    echo "Missing TENSORRT_VERSION or TENSORRT_PKG_VERSION in versions.env"
    exit 1
fi

EXPECTED_TRT_VERSION="${TENSORRT_VERSION:-}"

# Verify that CUDA repo/keyring has likely been configured already.
if ! apt-cache policy | grep -q "developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64"; then
    echo "NVIDIA CUDA repository is not configured."
    echo "Run the CUDA setup script first."
    exit 1
fi

# If TensorRT is already installed with the expected version, skip.
if dpkg-query -W -f='${Version}\n' libnvinfer10 2>/dev/null | grep -Fxq "$TRT_PKG_VERSION"; then
    echo "TensorRT already installed: $TRT_PKG_VERSION"
    exit 0
fi

echo "Installing TensorRT packages: $TRT_PKG_VERSION"

sudo apt-get update

PACKAGES=(
    "libnvinfer10=${TRT_PKG_VERSION}"
    "libnvinfer-dev=${TRT_PKG_VERSION}"
    "libnvinfer-plugin10=${TRT_PKG_VERSION}"
    "libnvinfer-plugin-dev=${TRT_PKG_VERSION}"
    "libnvonnxparsers10=${TRT_PKG_VERSION}"
    "libnvonnxparsers-dev=${TRT_PKG_VERSION}"
    "libnvparsers10=${TRT_PKG_VERSION}"
    "libnvparsers-dev=${TRT_PKG_VERSION}"
    "tensorrt=${TRT_PKG_VERSION}"
    "tensorrt-dev=${TRT_PKG_VERSION}"
)

if [[ "${STRICT_MODE:-false}" == "true" ]]; then
    sudo apt-get install -y --no-install-recommends "${PACKAGES[@]}"
else
    sudo apt-get install -y "${PACKAGES[@]}"
fi

# Prevent unintended upgrades beyond validated DeepStream stack
sudo apt-mark hold \
    libnvinfer10 \
    libnvinfer-dev \
    libnvinfer-plugin10 \
    libnvinfer-plugin-dev \
    libnvonnxparsers10 \
    libnvonnxparsers-dev \
    libnvparsers10 \
    libnvparsers-dev \
    tensorrt \
    tensorrt-dev >/dev/null

INSTALLED_PKG_VERSION="$(dpkg-query -W -f='${Version}\n' libnvinfer10 2>/dev/null || true)"

if [[ -z "$INSTALLED_PKG_VERSION" ]]; then
    echo "TensorRT installation failed: libnvinfer10 not found after install"
    exit 1
fi

if [[ -n "$EXPECTED_TRT_VERSION" && "$INSTALLED_PKG_VERSION" != "${EXPECTED_TRT_VERSION}"* ]]; then
    echo "TensorRT installed, but version mismatch detected."
    echo "Expected logical version: $EXPECTED_TRT_VERSION"
    echo "Installed package version: $INSTALLED_PKG_VERSION"
    exit 1
fi

echo "TensorRT installation completed: $INSTALLED_PKG_VERSION"