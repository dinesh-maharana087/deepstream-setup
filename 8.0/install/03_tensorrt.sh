#!/bin/bash
set -e

source ../config/versions.env
source ../utils/logger.sh

echo "Installing TensorRT..."

version=$TENSORRT_VERSION

sudo apt-get install libnvinfer-dev=${version} libnvinfer-dispatch-dev=${version} \
libnvinfer-dispatch10=${version} libnvinfer-headers-dev=${version} libnvinfer-headers-plugin-dev=${version} \
libnvinfer-lean-dev=${version} libnvinfer-lean10=${version} libnvinfer-plugin-dev=${version} \
libnvinfer-plugin10=${version} libnvinfer-vc-plugin-dev=${version} libnvinfer-vc-plugin10=${version} \
libnvinfer10=${version} libnvonnxparsers-dev=${version} libnvonnxparsers10=${version} tensorrt-dev=${version}