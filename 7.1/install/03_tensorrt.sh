#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "🔍 Checking TensorRT..."

REQUIRED_TENSORRT_VERSION=$(echo "$TENSORRT_VERSION" | cut -d'-' -f1)

get_installed_tensorrt_version() {
    if dpkg -s libnvinfer10 >/dev/null 2>&1; then
        dpkg-query -W -f='${Version}' libnvinfer10 2>/dev/null | cut -d'-' -f1
    else
        echo "not installed"
    fi
}

INSTALLED_TENSORRT_VERSION="$(get_installed_tensorrt_version)"

echo "Required TensorRT: $REQUIRED_TENSORRT_VERSION"
echo "Detected TensorRT: $INSTALLED_TENSORRT_VERSION"

if [ "$INSTALLED_TENSORRT_VERSION" = "$REQUIRED_TENSORRT_VERSION" ]; then
    echo "✅ TensorRT already installed: $INSTALLED_TENSORRT_VERSION"
    exit 0
fi

echo "Installing TensorRT..."

version=$TENSORRT_VERSION

sudo apt-get update

sudo apt-get install -y \
    libnvinfer-dev=${version} \
    libnvinfer-dispatch-dev=${version} \
    libnvinfer-dispatch10=${version} \
    libnvinfer-headers-dev=${version} \
    libnvinfer-headers-plugin-dev=${version} \
    libnvinfer-lean-dev=${version} \
    libnvinfer-lean10=${version} \
    libnvinfer-plugin-dev=${version} \
    libnvinfer-plugin10=${version} \
    libnvinfer-vc-plugin-dev=${version} \
    libnvinfer-vc-plugin10=${version} \
    libnvinfer10=${version} \
    libnvonnxparsers-dev=${version} \
    libnvonnxparsers10=${version} \
    tensorrt-dev=${version}

echo "🔧 Configuring TensorRT environment variables..."

TENSORRT_LIB_PATH="/usr/lib/x86_64-linux-gnu"

if ! grep -q "TensorRT" ~/.bashrc; then
    {
        echo ""
        echo "# TensorRT"
        echo "export TENSORRT_HOME=$TENSORRT_LIB_PATH"
        echo "export LD_LIBRARY_PATH=$TENSORRT_LIB_PATH:\$LD_LIBRARY_PATH"
    } >> ~/.bashrc

    echo "✅ TensorRT environment variables added to ~/.bashrc"
else
    echo "✅ TensorRT environment variables already configured"
fi

# Export for current shell session
export TENSORRT_HOME="$TENSORRT_LIB_PATH"
export LD_LIBRARY_PATH="$TENSORRT_LIB_PATH:$LD_LIBRARY_PATH"

echo "Installed TensorRT: $(get_installed_tensorrt_version)"
echo "TENSORRT_HOME=$TENSORRT_HOME"
echo "✅ TensorRT installation completed"