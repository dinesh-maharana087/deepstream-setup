#!/bin/bash

# Error handling: exit on any error, show line numbers
set -e
set -o pipefail
trap 'log_error "CUDA installation failed at line $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

log_info "🔍 Checking CUDA installation..."

# Pre-flight validation
validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "❌ This script requires sudo access"
    exit 1
fi

# Check if CUDA is already installed (idempotency)
if check_cuda; then
    log_success "✅ CUDA already installed: $(get_cuda_version)"
    exit 0
fi

log_info "Installing CUDA $CUDA_VERSION..."

# Ensure work directory exists
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download and setup NVIDIA CUDA repository GPG key using modern keyring method
log_info "Setting up NVIDIA CUDA repository..."

GPG_KEY_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub"
KEYRING_PATH="/usr/share/keyrings/nvidia-cuda-archive-keyring.gpg"
TEMP_KEY="$WORK_DIR/nvidia-cuda-key.pub"

# Download GPG key
log_info "Downloading NVIDIA GPG key..."
if ! curl -fsSL "$GPG_KEY_URL" -o "$TEMP_KEY"; then
    log_error "❌ Failed to download NVIDIA GPG key from $GPG_KEY_URL"
    exit 1
fi

# Convert GPG key to binary format and install to system keyring (requires sudo)
log_info "Installing GPG key to system keyring..."
sudo gpg --dearmour -o "$KEYRING_PATH" "$TEMP_KEY" 2>/dev/null
if [ $? -ne 0 ]; then
    log_error "❌ Failed to install GPG key"
    rm -f "$TEMP_KEY"
    exit 1
fi

# Clean up temporary key file
rm -f "$TEMP_KEY"

# Add CUDA repository using the installed keyring (modern method, no apt-key)
log_info "Adding CUDA APT repository..."
CUDA_REPO="deb [signed-by=$KEYRING_PATH] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /"
sudo sh -c "echo '$CUDA_REPO' > /etc/apt/sources.list.d/nvidia-cuda.list"

# Update package index with new repository
log_info "Updating package index with CUDA repository..."
sudo apt-get update -qq

# Install CUDA toolkit with -y flag
log_info "Installing CUDA toolkit (this may take several minutes)..."
sudo apt-get install -y cuda-toolkit-"${CUDA_VERSION}" 2>&1 | grep -v "^Reading\|^Building\|^Selecting"

# Verify CUDA installation by checking for nvcc
log_info "Verifying CUDA installation..."
if ! command -v nvcc >/dev/null 2>&1; then
    # Set CUDA path if nvcc not in PATH
    export PATH="/usr/local/cuda/bin:$PATH"
    
    if ! command -v nvcc >/dev/null 2>&1; then
        log_error "❌ CUDA installation verification failed (nvcc not found)"
        exit 1
    fi
fi

CUDA_VERSION_INSTALLED=$(nvcc --version | grep "release" | awk '{print $5}' | cut -d'.' -f1-2)
log_success "✅ CUDA installation completed successfully"
log_info "   Installed version: $CUDA_VERSION_INSTALLED"
log_info "   Expected version: $CUDA_VERSION"