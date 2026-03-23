#!/bin/bash

# Error handling: exit on any error, show line numbers
set -e
set -o pipefail
trap 'log_error "DeepStream installation failed at line $LINENO"; cleanup_deepstream_install; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

# Cleanup function for error handling
cleanup_deepstream_install() {
    log_warn "Cleaning up DeepStream temporary files..."
    rm -f "$WORK_DIR/deepstream.deb"
    rm -f "$WORK_DIR/deepstream-*.deb"
}

log_info "🔍 Checking DeepStream installation..."

# Pre-flight validation
validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "❌ This script requires sudo access"
    exit 1
fi

# Check if DeepStream is already installed (idempotency)
if check_deepstream; then
    log_success "✅ DeepStream already installed: $(get_deepstream_version)"
    exit 0
fi

log_info "Installing DeepStream version: $DEEPSTREAM_VERSION"

# Validate DeepStream version format
if [[ ! "$DEEPSTREAM_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    log_error "❌ Invalid DeepStream version format: $DEEPSTREAM_VERSION (expected format: X.Y, e.g., 8.0)"
    exit 1
fi

# Ensure work directory exists
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Construct download URL for DeepStream deb package
DEB_URL="https://api.ngc.nvidia.com/v2/resources/org/nvidia/deepstream/${DEEPSTREAM_VERSION}/files?redirect=true&path=deepstream-${DEEPSTREAM_VERSION}_${DEEPSTREAM_VERSION}.0-1_amd64.deb"
DEB_FILE="$WORK_DIR/deepstream.deb"

log_info "Downloading DeepStream deb package from NGC..."
log_info "URL: $DEB_URL"

# Download deb file with error checking
if ! curl -fsSL --max-time 300 "$DEB_URL" -o "$DEB_FILE"; then
    log_error "❌ Failed to download DeepStream deb package"
    cleanup_deepstream_install
    exit 1
fi

# Verify downloaded file exists and has non-zero size
if [ ! -f "$DEB_FILE" ] || [ ! -s "$DEB_FILE" ]; then
    log_error "❌ Downloaded file is invalid or empty: $DEB_FILE"
    cleanup_deepstream_install
    exit 1
fi

DEB_SIZE=$(du -h "$DEB_FILE" | cut -f1)
log_info "Downloaded: $DEB_FILE (size: $DEB_SIZE)"

# Install the deb package
log_info "Installing DeepStream package (this may take several minutes)..."
sudo apt-get install -y "$DEB_FILE" 2>&1 | grep -v "^Reading\|^Building\|^Selecting"

# Verify DeepStream installation
log_info "Verifying DeepStream installation..."
if ! check_deepstream; then
    log_error "❌ DeepStream installation verification failed"
    cleanup_deepstream_install
    exit 1
fi

# Verify installation directory exists
if [ ! -d "/opt/nvidia/deepstream" ]; then
    log_error "❌ DeepStream directory not found at /opt/nvidia/deepstream"
    cleanup_deepstream_install
    exit 1
fi

# Get installed version
DS_VERSION=$(get_deepstream_version)

# Cleanup downloaded deb file
log_info "Cleaning up temporary files..."
rm -f "$DEB_FILE"

log_success "✅ DeepStream installation completed successfully"
log_info "   Installed version: $DS_VERSION"
log_info "   Installation directory: /opt/nvidia/deepstream"