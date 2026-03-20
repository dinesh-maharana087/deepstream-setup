#!/bin/bash
set -e

source ../config/versions.env
source ../utils/logger.sh

echo "Installing DeepStream..."

curl -L "https://api.ngc.nvidia.com/v2/resources/org/nvidia/deepstream/${DEEPSTREAM_VERSION}/files?redirect=true&path=deepstream-${DEEPSTREAM_VERSION}_${DEEPSTREAM_VERSION}.0-1_amd64.deb" \
-o deepstream.deb

sudo apt install -y ./deepstream.deb