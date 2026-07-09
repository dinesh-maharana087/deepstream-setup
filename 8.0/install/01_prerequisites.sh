#!/bin/bash

###############################################################################
# DeepStream 8.0 Prerequisites Installer
# Ubuntu 24.04
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

trap 'log_failure "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "System Prerequisites"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

APT_OPTIONS=(
    "-y"
    "-q"
    "--no-upgrade"
    "-o" "Dpkg::Use-Pty=0"
    "-o" "Acquire::Retries=5"
    "-o" "Acquire::http::Timeout=30"
    "-o" "Acquire::https::Timeout=30"
)

INSTALL_PACKAGES=(
    ca-certificates
    curl
    wget
    gnupg
    build-essential
    cmake
    g++
    pkg-config
    libssl3t64
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

VERIFY_PACKAGES=(
    ca-certificates
    curl
    wget
    gnupg
    build-essential
    cmake
    g++
    pkg-config
    libssl3t64
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

        log_warn "apt update failed attempt ${attempt}/5. Retrying..."
        sleep 5
    done

    log_error "Unable to update package index."
    exit 1
}

check_sudo() {
    require_sudo
}

check_broken_packages() {
    local broken_pkgs

    broken_pkgs="$(dpkg -l | awk '$1=="iF" || $1=="iU" || $1=="iH"{print $2}')"

    if [[ -n "$broken_pkgs" ]]; then
        log_error "Broken or half-installed packages detected:"
        echo "$broken_pkgs"
        log_error "Fix broken packages manually before running this installer."
        exit 1
    fi
}

simulate_install() {
    local simulation_output

    log_info "Running apt simulation before installation..."

    simulation_output="$(sudo apt-get install --simulate "${APT_OPTIONS[@]}" "${INSTALL_PACKAGES[@]}")"

    echo "$simulation_output"

    if grep -E "^Remv " <<< "$simulation_output" >/dev/null 2>&1; then
        log_error "Apt simulation indicates package removal. Aborting."
        exit 1
    fi

    if grep -E "^Inst .* \[.*\]" <<< "$simulation_output" >/dev/null 2>&1; then
        log_error "Apt simulation indicates package upgrade/change. Aborting."
        exit 1
    fi

    log_success "Apt simulation passed."
}

verify_installed() {
    local pkg
    local missing=()

    for pkg in "${VERIFY_PACKAGES[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_error "Some required packages were not installed:"
        printf '%s\n' "${missing[@]}"
        exit 1
    fi
}

log_info "Installing DeepStream prerequisite packages..."

validate_system
validate_versions_before_install
check_sudo

wait_for_apt_lock
check_broken_packages

log_info "Updating package index..."
apt_update

simulate_install

log_info "Installing prerequisite packages..."
sudo apt-get install "${APT_OPTIONS[@]}" "${INSTALL_PACKAGES[@]}"

log_info "Verifying installation..."
check_broken_packages
verify_installed

log_info "Cleaning apt package cache only..."
sudo apt-get autoclean -y

log_success "DeepStream prerequisite package installation completed successfully."
