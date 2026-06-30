#!/bin/bash

###############################################################################
# DeepStream 8.0 Prerequisites Installer
#
# Ubuntu: 24.04
# Production-safe:
# - Installs only listed prerequisite packages
# - No autoremove
# - No automatic dependency repair
# - Performs apt simulation before install
# - Safe for repeated execution
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

trap 'log_error "Prerequisites installation failed at line ${LINENO}"; exit 1' ERR

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
    make
    git
    python3
)

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

        log_warning "apt update failed attempt ${attempt}/5. Retrying..."
        sleep 5
    done

    log_error "Unable to update package index."
    exit 1
}

check_broken_packages() {
    local broken_pkgs

    broken_pkgs="$(dpkg -l | awk '$1=="iF" || $1=="iU" || $1=="iH"{print $2}')"

    if [[ -n "$broken_pkgs" ]]; then
        log_error "Broken or half-installed packages detected:"
        echo "$broken_pkgs"
        log_error "Please fix broken packages manually before running this production installer."
        exit 1
    fi
}

simulate_install() {
    log_info "Running apt simulation before installation..."

    if ! sudo apt-get install --simulate "${PACKAGES[@]}"; then
        log_error "Apt simulation failed. No packages were installed."
        exit 1
    fi

    local simulation_output
    simulation_output="$(sudo apt-get install --simulate "${PACKAGES[@]}")"

    if echo "$simulation_output" | grep -E "^Remv |^Conf .* \[.*\]" >/dev/null 2>&1; then
        log_error "Apt simulation indicates package removal or version changes."
        echo "$simulation_output"
        log_error "Aborting for production safety."
        exit 1
    fi

    log_success "Apt simulation passed."
}

verify_installed() {
    local missing=()

    for pkg in "${PACKAGES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_error "Some packages were not installed:"
        printf '%s\n' "${missing[@]}"
        exit 1
    fi
}

log_info "Installing DeepStream prerequisite packages..."

validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "Passwordless sudo is required."
    exit 1
fi

wait_for_apt_lock

check_broken_packages

log_info "Updating package index..."
apt_update

simulate_install

log_info "Installing prerequisite packages..."
sudo apt-get install \
    "${APT_OPTIONS[@]}" \
    "${PACKAGES[@]}"

log_info "Verifying installation..."
check_broken_packages
verify_installed

log_info "Cleaning apt package cache only..."
sudo apt-get autoclean -y

log_success "DeepStream prerequisite package installation completed successfully."