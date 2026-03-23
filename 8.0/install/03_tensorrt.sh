#!/bin/bash

# Error handling: exit on any error, show line numbers
set -e
set -o pipefail
trap 'log_error "TensorRT installation failed at line $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

log_info "🔍 Checking TensorRT installation..."

# Pre-flight validation
validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "❌ This script requires sudo access"
    exit 1
fi

# Check if TensorRT is already installed (idempotency)
if check_tensorrt; then
    log_success "✅ TensorRT already installed"
    exit 0
fi

log_info "Installing TensorRT version: $TENSORRT_VERSION"

# Define TensorRT packages with version pinning
# Note: All packages must be the exact same version for compatibility
TENSORRT_PACKAGES=(
    "libnvinfer-dev=${TENSORRT_VERSION}"
    "libnvinfer-dispatch-dev=${TENSORRT_VERSION}"
    "libnvinfer-dispatch10=${TENSORRT_VERSION}"
    "libnvinfer-headers-dev=${TENSORRT_VERSION}"
    "libnvinfer-headers-plugin-dev=${TENSORRT_VERSION}"
    "libnvinfer-lean-dev=${TENSORRT_VERSION}"
    "libnvinfer-lean10=${TENSORRT_VERSION}"
    "libnvinfer-plugin-dev=${TENSORRT_VERSION}"
    "libnvinfer-plugin10=${TENSORRT_VERSION}"
    "libnvinfer-vc-plugin-dev=${TENSORRT_VERSION}"
    "libnvinfer-vc-plugin10=${TENSORRT_VERSION}"
    "libnvinfer10=${TENSORRT_VERSION}"
    "libnvonnxparsers-dev=${TENSORRT_VERSION}"
    "libnvonnxparsers10=${TENSORRT_VERSION}"
    "tensorrt-dev=${TENSORRT_VERSION}"
)

log_info "Installing ${#TENSORRT_PACKAGES[@]} TensorRT packages (this may take several minutes)..."
sudo apt-get install -y "${TENSORRT_PACKAGES[@]}" 2>&1 | grep -v "^Reading\|^Building\|^Selecting"

# Verify TensorRT installation
log_info "Verifying TensorRT installation..."
if ! dpkg -l | grep -q "libnvinfer10"; then
    log_error "❌ TensorRT installation verification failed (libnvinfer10 not found)"
    exit 1
fi

# Get installed version for logging
TENSORRT_INSTALLED=$(dpkg -l | grep libnvinfer10 | awk '{print $3}')
log_success "✅ TensorRT installation completed successfully"
log_info "   Installed packages: libnvinfer10 (version: $TENSORRT_INSTALLED)"
log_info "   Expected version: $TENSORRT_VERSION"