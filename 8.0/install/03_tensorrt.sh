#!/bin/bash

###############################################################################
# TensorRT 10.9 Installer for DeepStream 8.0
#
# Production-safe:
# - Uses exact pinned TensorRT version from versions.env
# - No package version changes
# - No autoremove
# - No apt -f install
# - Uses apt simulation before install
# - Verifies packages using dpkg-query, not grep pipelines
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

trap 'log_failure "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "TensorRT"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

APT_OPTIONS=(
    "-y"
    "-q"
    "-o" "Dpkg::Use-Pty=0"
    "-o" "Acquire::Retries=5"
    "-o" "Acquire::http::Timeout=30"
    "-o" "Acquire::https::Timeout=30"
)

TENSORRT_PACKAGE_NAMES=(
    libnvinfer-dev
    libnvinfer-dispatch-dev
    libnvinfer-dispatch10
    libnvinfer-headers-dev
    libnvinfer-headers-plugin-dev
    libnvinfer-lean-dev
    libnvinfer-lean10
    libnvinfer-plugin-dev
    libnvinfer-plugin10
    libnvinfer-vc-plugin-dev
    libnvinfer-vc-plugin10
    libnvinfer10
    libnvonnxparsers-dev
    libnvonnxparsers10
    tensorrt-dev
)

TENSORRT_PACKAGES=()
for pkg in "${TENSORRT_PACKAGE_NAMES[@]}"; do
    TENSORRT_PACKAGES+=("${pkg}=${TENSORRT_PACKAGE_VERSION}")
done

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

check_broken_packages() {
    local broken_pkgs

    broken_pkgs="$(dpkg -l | awk '$1=="iF" || $1=="iU" || $1=="iH"{print $2}')"

    if [[ -n "$broken_pkgs" ]]; then
        log_error "Broken or half-installed packages detected:"
        echo "$broken_pkgs"
        log_error "Fix broken packages manually before running this production installer."
        exit 1
    fi
}

check_available_versions() {
    local pkg
    local candidate

    log_info "Checking TensorRT package availability..."

    for pkg in "${TENSORRT_PACKAGE_NAMES[@]}"; do
        candidate="$(apt-cache madison "$pkg" | awk -v ver="$TENSORRT_PACKAGE_VERSION" '$3 == ver {print $3; exit}')"

        if [[ "$candidate" != "$TENSORRT_PACKAGE_VERSION" ]]; then
            log_error "Required version not available for package: $pkg"
            log_error "Expected: $TENSORRT_PACKAGE_VERSION"
            exit 1
        fi
    done

    log_success "All required TensorRT package versions are available."
}

simulate_install() {
    local simulation_output

    log_info "Running apt simulation before TensorRT installation..."

    simulation_output="$(sudo apt-get install --simulate "${TENSORRT_PACKAGES[@]}")"

    if echo "$simulation_output" | grep -E "^Remv " >/dev/null 2>&1; then
        log_error "Apt simulation indicates package removal."
        echo "$simulation_output"
        log_error "Aborting for production safety."
        exit 1
    fi

    if echo "$simulation_output" | grep -E "^Inst " | grep -v "$TENSORRT_PACKAGE_VERSION" >/dev/null 2>&1; then
        log_error "Apt simulation indicates installation of unexpected package versions."
        echo "$simulation_output"
        log_error "Aborting for production safety."
        exit 1
    fi

    log_success "Apt simulation passed."
}

verify_tensorrt_packages() {
    local pkg
    local installed_version
    local missing_or_wrong=0

    log_info "Verifying TensorRT package versions..."

    for pkg in "${TENSORRT_PACKAGE_NAMES[@]}"; do
        installed_version="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"

        if [[ "$installed_version" != "$TENSORRT_PACKAGE_VERSION" ]]; then
            log_error "$pkg version mismatch or not installed"
            log_error "  Installed: ${installed_version:-not installed}"
            log_error "  Expected : $TENSORRT_PACKAGE_VERSION"
            missing_or_wrong=1
        else
            log_success "$pkg = $installed_version"
        fi
    done

    if [[ "$missing_or_wrong" -ne 0 ]]; then
        log_error "TensorRT verification failed."
        exit 1
    fi
}

log_info "Checking TensorRT installation..."

validate_system
validate_versions_before_install

require_sudo

wait_for_apt_lock
check_broken_packages

if dpkg-query -W -f='${Version}' libnvinfer10 2>/dev/null | grep -Fxq "$TENSORRT_PACKAGE_VERSION"; then
    log_success "TensorRT already installed: $TENSORRT_PACKAGE_VERSION"
    verify_tensorrt_packages
    exit 0
fi

log_info "Installing TensorRT version: $TENSORRT_VERSION ($TENSORRT_PACKAGE_VERSION)"

sudo apt-get update

check_available_versions
simulate_install

log_info "Installing ${#TENSORRT_PACKAGES[@]} TensorRT packages..."
sudo apt-get install "${APT_OPTIONS[@]}" "${TENSORRT_PACKAGES[@]}"

check_broken_packages
verify_tensorrt_packages

log_success "TensorRT installation completed successfully."
log_info "Expected TensorRT package version: $TENSORRT_PACKAGE_VERSION"
