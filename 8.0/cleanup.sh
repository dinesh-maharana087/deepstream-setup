#!/bin/bash

# DeepStream 8.0 - Post-Installation Cleanup Script
# Removes temporary files and clears apt cache after successful installation
# Usage: bash cleanup.sh

set -e
set -o pipefail

trap 'log_error "Cleanup failed at line $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "$SCRIPT_DIR/config/versions.env"
source "$SCRIPT_DIR/utils/logger.sh"

log_info "=================================================="
log_info "DeepStream 8.0 - Post-Installation Cleanup"
log_info "=================================================="

if ! sudo -n true 2>/dev/null; then
    log_error "❌ This script requires sudo access"
    exit 1
fi

# Cleanup work directory temporary files
log_info "Cleaning up installation temporary files..."

TEMP_FILES=(
    "$WORK_DIR/deepstream.deb"
    "$WORK_DIR/deepstream-*.deb"
    "$WORK_DIR/nvidia-cuda-key.pub"
    "$WORK_DIR/cuda-key.gpg"
)

for pattern in "${TEMP_FILES[@]}"; do
    if [ -e "$pattern" ] || [ -L "$pattern" ]; then
        log_info "Removing: $pattern"
        rm -f "$pattern" 2>/dev/null || true
    fi
done

# Cleanup Python build artifacts (kept in WORK_DIR but can be removed)
if [ -d "$WORK_DIR/deepstream_python_apps/bindings/build" ]; then
    log_info "Removing Python build cache..."
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/build"
fi

if [ -d "$WORK_DIR/deepstream_python_apps/bindings/.eggs" ]; then
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/.eggs"
fi

# Clear apt cache to reclaim disk space
log_info "Clearing apt package cache..."
sudo apt-get clean -qq
sudo apt-get autoclean -qq

# Optional: Remove old apt lists (more aggressive cleanup, use with caution)
# sudo apt-get autoremove -y

log_info "Disk usage before cleanup could be validated with: du -sh $WORK_DIR"

log_success "✅ Cleanup completed successfully"
log_info ""
log_info "Installation directory: $WORK_DIR"
log_info "Python virtual environment: $WORK_DIR/deepstream_venv"
log_info "DeepStream installation: /opt/nvidia/deepstream"
log_info "Log files: $WORK_DIR/logs/"
