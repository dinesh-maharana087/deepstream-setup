#!/bin/bash
set -e

source ../config/versions.env
source ../utils/logger.sh

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