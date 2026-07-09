#!/bin/bash

# Error handling: exit on any error, show line numbers
set -Eeuo pipefail
trap 'echo "[ERROR] CUDA Toolkit failed at line $LINENO: $BASH_COMMAND" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

trap 'log_failure "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" "CUDA Toolkit"; exit 1' ERR

log_info "🔍 Checking CUDA installation..."

# Pre-flight validation
validate_system
validate_versions_before_install

require_sudo

# Check if CUDA is already installed (idempotency)
if check_cuda && [[ "$(get_cuda_version)" == "$CUDA_VERSION"* ]]; then
    log_success "✅ CUDA already installed: $(get_cuda_version)"
    exit 0
fi

log_info "Installing CUDA $CUDA_VERSION ($CUDA_APT_PACKAGE)..."

# Ensure work directory exists
ensure_user_owned_dir "$WORK_DIR"
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
if ! sudo gpg --batch --yes --dearmor -o "$KEYRING_PATH" "$TEMP_KEY"; then
    log_error "Failed to install GPG key"
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
apt_update

if ! apt_package_available "$CUDA_APT_PACKAGE"; then
    log_error "CUDA package not found in apt repositories: $CUDA_APT_PACKAGE"
    log_error "Expected CUDA display version: $CUDA_VERSION"
    log_error "Expected CUDA package suffix: $CUDA_PACKAGE_VERSION"
    exit 1
fi

# Install CUDA toolkit with -y flag
log_info "Installing CUDA toolkit (this may take several minutes)..."
sudo apt-get install -y "$CUDA_APT_PACKAGE"

# Verify CUDA installation by checking for nvcc
log_info "Verifying CUDA installation..."
NVCC_BIN="$(get_cuda_nvcc 2>/dev/null || true)"
if [[ -z "$NVCC_BIN" ]]; then
    # Set CUDA path if nvcc not in PATH
    export PATH="/usr/local/cuda/bin:$PATH"
    
    NVCC_BIN="$(get_cuda_nvcc 2>/dev/null || true)"
    if [[ -z "$NVCC_BIN" ]]; then
        log_error "❌ CUDA installation verification failed (nvcc not found)"
        exit 1
    fi
fi

CUDA_VERSION_INSTALLED=$("$NVCC_BIN" --version | awk -F'release ' '/release/ {print $2}' | awk -F',' '{print $1}')
log_success "✅ CUDA installation completed successfully"
log_info "   Installed version: $CUDA_VERSION_INSTALLED"
log_info "   Expected version: $CUDA_VERSION"
