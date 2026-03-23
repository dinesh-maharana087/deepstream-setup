#!/bin/bash

# Error handling: exit on any error, show line numbers
set -e
set -o pipefail
trap 'log_error "Prerequisites installation failed at line $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

log_info "🔍 Installing system prerequisites..."

# Pre-flight validation: Ubuntu 24.04, versions defined, sudo available
validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "❌ This script requires sudo access"
    exit 1
fi

# Define required system packages for DeepStream 8.0 on Ubuntu 24.04
PACKAGES=(
    "libssl3"
    "libssl-dev"
    "libgles2-mesa-dev"
    "libgstreamer1.0-0"
    "gstreamer1.0-tools"
    "gstreamer1.0-plugins-good"
    "gstreamer1.0-plugins-bad"
    "gstreamer1.0-plugins-ugly"
    "gstreamer1.0-libav"
    "libgstreamer-plugins-base1.0-dev"
    "libgstrtspserver-1.0-0"
    "libjansson4"
    "libyaml-cpp-dev"
    "libjsoncpp-dev"
    "protobuf-compiler"
    "libmosquitto1"
    "gcc"
    "make"
    "git"
    "python3"
    "python3-pip"
    "python3-venv"
    "curl"
    "wget"
)

# Check which packages are missing (idempotency: avoid reinstalling)
MISSING=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
    log_success "✅ All system prerequisites already installed"
    exit 0
fi

log_info "Installing ${#MISSING[@]} missing package(s)..."
log_info "Packages: ${MISSING[*]}"

# Update apt index before installation
log_info "Updating apt package index..."
sudo apt-get update -qq

# Install missing packages with -y flag for automation
log_info "Installing packages (this may take several minutes)..."
sudo apt-get install -y "${MISSING[@]}"

# Verify installation
log_info "Verifying package installation..."
FAILED_PACKAGES=()
for pkg in "${MISSING[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        FAILED_PACKAGES+=("$pkg")
    fi
done

if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    log_error "❌ Failed to install: ${FAILED_PACKAGES[*]}"
    exit 1
fi

# Cleanup apt cache to reduce disk usage
log_info "Cleaning up apt cache..."
sudo apt-get clean -qq
sudo apt-get autoclean -qq

log_success "✅ System prerequisites installation completed successfully"

