#!/bin/bash

###############################################################################
# DeepStream 8.0 Prerequisites Installer
#
# Ubuntu: 24.04
# Safe for repeated execution.
# Production-grade package installation.
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

trap 'log_error "Prerequisites installation failed at line ${LINENO}"; exit 1' ERR

###############################################################################
# Configuration
###############################################################################

export DEBIAN_FRONTEND=noninteractive

APT_OPTIONS=(
    "-y"
    "-q"
    "-o" "Dpkg::Use-Pty=0"
    "-o" "Acquire::Retries=5"
    "-o" "Acquire::http::Timeout=30"
    "-o" "Acquire::https::Timeout=30"
)

PACKAGES=(
    libssl3
    libssl-dev
    libgles2-mesa-dev
    libgstreamer1.0-0
    gstreamer1.0-tools
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
    gstreamer1.0-libav
    libgstreamer-plugins-base1.0-dev
    libgstrtspserver-1.0-0
    libjansson4
    libyaml-cpp-dev
    libjsoncpp-dev
    protobuf-compiler
    libmosquitto1
    gcc
    g++
    make
    git
    curl
    wget
    unzip
    pkg-config
    python3
    python3-dev
    python3-pip
    python3-venv
)

###############################################################################
# Helper Functions
###############################################################################

wait_for_apt_lock() {

    log_info "Waiting for package manager lock..."

    while \
        sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1
    do
        sleep 2
    done
}

apt_update() {

    local attempt

    for attempt in {1..5}; do

        if sudo apt-get update; then
            return 0
        fi

        log_warning "apt update failed (attempt ${attempt}/5). Retrying..."

        sleep 5
    done

    log_error "Unable to update package index."

    exit 1
}

###############################################################################
# Validation
###############################################################################

log_info "Installing system prerequisites..."

validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "Passwordless sudo is required."
    exit 1
fi

###############################################################################
# Installation
###############################################################################

wait_for_apt_lock

log_info "Updating package index..."

apt_update

log_info "Installing prerequisite packages..."

sudo apt-get install \
    "${APT_OPTIONS[@]}" \
    "${PACKAGES[@]}"

###############################################################################
# Verification
###############################################################################

log_info "Verifying installation..."

BROKEN_PKGS=$(dpkg -l | awk '$1=="iF" || $1=="iU" || $1=="rc"{print $2}')

if [[ -n "$BROKEN_PKGS" ]]; then

    log_error "Broken packages detected:"

    echo "$BROKEN_PKGS"

    sudo apt-get -f install -y

fi

###############################################################################
# Cleanup
###############################################################################

log_info "Cleaning apt cache..."

sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get clean

###############################################################################
# Done
###############################################################################

log_success "System prerequisite installation completed successfully."