#!/bin/bash
set -e
set -o pipefail

source ../config/versions.env
source ../utils/logger.sh
source ../utils/checks.sh

echo "🔍 Checking CUDA..."

if check_cuda; then
    echo "✅ CUDA already installed: $(get_cuda_version)"
    exit 0
fi

echo "Installing CUDA..."

sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub

sudo add-apt-repository -y "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"

sudo apt update
sudo apt install -y cuda-toolkit-$CUDA_VERSION

echo "✅ CUDA installation completed"