#!/bin/bash
set -e
set -o pipefail

source ../config/versions.env
source ../utils/logger.sh
source ../utils/checks.sh

echo "🔍 Checking TensorRT..."

if check_tensorrt; then
    echo "✅ TensorRT already installed"
    exit 0
fi

echo "Installing TensorRT..."

version=$TENSORRT_VERSION

sudo apt-get install -y \
libnvinfer-dev=${version} \
libnvinfer-dispatch-dev=${version} \
libnvinfer-dispatch10=${version} \
libnvinfer-headers-dev=${version} \
libnvinfer-plugin-dev=${version} \
libnvinfer10=${version} \
libnvonnxparsers-dev=${version} \
tensorrt-dev=${version}

echo "✅ TensorRT installation completed"