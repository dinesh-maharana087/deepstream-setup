#!/bin/bash
set -e

source ../config/versions.env
source ../utils/logger.sh

echo "Installing CUDA..."

sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub

sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /"

sudo apt-get update
sudo apt-get install cuda-toolkit-$CUDA_VERSION