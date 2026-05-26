#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "🔍 Checking CUDA..."

REQUIRED_CUDA_VERSION="${CUDA_VERSION/-/.}"

get_installed_cuda_version() {
    if command -v nvcc >/dev/null 2>&1; then
        nvcc --version | grep "release" | sed -E 's/.*release ([0-9]+\.[0-9]+).*/\1/'
    else
        echo "not installed"
    fi
}

INSTALLED_CUDA_VERSION="$(get_installed_cuda_version)"

echo "Required CUDA: $REQUIRED_CUDA_VERSION"
echo "Detected CUDA: $INSTALLED_CUDA_VERSION"

if [ "$INSTALLED_CUDA_VERSION" = "$REQUIRED_CUDA_VERSION" ]; then
    echo "✅ CUDA already installed: $INSTALLED_CUDA_VERSION"
else
    echo "Installing CUDA toolkit $CUDA_VERSION..."

    sudo apt update
    sudo apt install -y wget gnupg software-properties-common

    sudo wget -qO /usr/share/keyrings/cuda-archive-keyring.gpg \
        https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub

    echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /" | \
        sudo tee /etc/apt/sources.list.d/cuda.list >/dev/null

    sudo apt update
    sudo apt install -y "cuda-toolkit-$CUDA_VERSION"

    echo "✅ CUDA installation completed"
fi

CUDA_PATH="/usr/local/cuda-${REQUIRED_CUDA_VERSION}"

echo "🔧 Configuring CUDA environment variables..."

if ! grep -q "$CUDA_PATH/bin" ~/.bashrc; then
    {
        echo ""
        echo "# CUDA $REQUIRED_CUDA_VERSION"
        echo "export CUDA_HOME=$CUDA_PATH"
        echo "export PATH=\$CUDA_HOME/bin:\$PATH"
        echo "export LD_LIBRARY_PATH=\$CUDA_HOME/lib64:\$LD_LIBRARY_PATH"
    } >> ~/.bashrc

    echo "✅ CUDA environment variables added to ~/.bashrc"
else
    echo "✅ CUDA environment variables already configured"
fi

# Export for current shell session
export CUDA_HOME="$CUDA_PATH"
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

echo "Current CUDA version: $(get_installed_cuda_version)"
echo "CUDA_HOME=$CUDA_HOME"
echo "✅ CUDA setup completed"