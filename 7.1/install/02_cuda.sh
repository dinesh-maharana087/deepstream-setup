#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

REQUIRED_CUDA_VERSION="${CUDA_VERSION/-/.}"
CUDA_PATH="/usr/local/cuda-${REQUIRED_CUDA_VERSION}"
CUDA_TOOLKIT_PACKAGE="cuda-toolkit-${CUDA_VERSION}"
CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64"
CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
CUDA_KEYRING_URL="${CUDA_REPO_URL}/${CUDA_KEYRING_DEB}"
CUDA_KEYRING_PATH="/tmp/${CUDA_KEYRING_DEB}"
CUDA_REPO_FILE="/etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list"
CUDA_REPO_LINE="deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] ${CUDA_REPO_URL}/ /"
BASHRC="${HOME}/.bashrc"

log() {
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
    echo ""
    echo "ERROR: $*" >&2
    exit 1
}

append_bashrc_once() {
    local line="$1"

    touch "$BASHRC"

    if grep -qxF "$line" "$BASHRC"; then
        echo "Already in ~/.bashrc: $line"
    else
        echo "$line" >> "$BASHRC"
        echo "Added to ~/.bashrc: $line"
    fi
}

get_nvcc_path() {
    if [ -x "${CUDA_PATH}/bin/nvcc" ]; then
        echo "${CUDA_PATH}/bin/nvcc"
    elif command -v nvcc >/dev/null 2>&1; then
        command -v nvcc
    else
        return 1
    fi
}

get_installed_cuda_version() {
    local nvcc_path
    local nvcc_output
    local detected_version

    if ! nvcc_path="$(get_nvcc_path)"; then
        echo "not installed"
        return 0
    fi

    nvcc_output="$("$nvcc_path" --version 2>/dev/null || true)"
    detected_version="$(printf '%s\n' "$nvcc_output" | sed -nE 's/.*release ([0-9]+\.[0-9]+).*/\1/p' | head -n 1)"

    if [ -n "$detected_version" ]; then
        echo "$detected_version"
    else
        echo "unknown"
    fi
}

clean_old_cuda_repos() {
    log "Cleaning old CUDA repository entries..."

    for repo_file in \
        /etc/apt/sources.list.d/cuda.list \
        /etc/apt/sources.list.d/cuda-ubuntu2204-x86_64.list
    do
        if sudo test -e "$repo_file"; then
            echo "Removing old CUDA repo file: $repo_file"
            sudo rm -f "$repo_file"
        else
            echo "Old CUDA repo file not present: $repo_file"
        fi
    done

    if sudo test -f /etc/apt/sources.list; then
        if grep -qE 'developer\.download\.nvidia\.com.*cuda' /etc/apt/sources.list; then
            local backup_file="/etc/apt/sources.list.cuda-backup.$(date '+%Y%m%d%H%M%S')"
            echo "Removing CUDA repo lines from /etc/apt/sources.list"
            echo "Backup: $backup_file"
            sudo cp /etc/apt/sources.list "$backup_file"
            sudo sed -i -E '/developer\.download\.nvidia\.com.*cuda/d' /etc/apt/sources.list
        else
            echo "No CUDA repo entries found in /etc/apt/sources.list"
        fi
    else
        echo "/etc/apt/sources.list not found; skipping main source cleanup"
    fi
}

install_required_packages() {
    log "Installing required apt packages..."
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wget \
        gnupg \
        software-properties-common \
        ca-certificates
}

install_cuda_keyring() {
    log "Installing NVIDIA cuda-keyring package..."
    echo "Downloading: $CUDA_KEYRING_URL"
    wget -O "$CUDA_KEYRING_PATH" "$CUDA_KEYRING_URL"

    echo "Installing: $CUDA_KEYRING_PATH"
    sudo env DEBIAN_FRONTEND=noninteractive dpkg --force-confnew --force-confmiss -i "$CUDA_KEYRING_PATH"

    if ! sudo test -f "$CUDA_REPO_FILE" || ! sudo grep -qxF "$CUDA_REPO_LINE" "$CUDA_REPO_FILE"; then
        echo "Adding CUDA repository entry: $CUDA_REPO_FILE"
        echo "$CUDA_REPO_LINE" | sudo tee "$CUDA_REPO_FILE" >/dev/null
    else
        echo "CUDA repository entry already configured: $CUDA_REPO_FILE"
    fi
}

update_apt_after_keyring() {
    log "Running apt update after cuda-keyring installation..."

    if ! sudo apt-get update; then
        fail "apt-get update failed after installing cuda-keyring. Check the CUDA repo entry, network access, and NVIDIA repository availability."
    fi
}

install_cuda_toolkit() {
    local installed_cuda_version

    installed_cuda_version="$(get_installed_cuda_version)"

    echo "Required CUDA: $REQUIRED_CUDA_VERSION"
    echo "Detected CUDA: $installed_cuda_version"

    if [ "$installed_cuda_version" = "$REQUIRED_CUDA_VERSION" ]; then
        echo "CUDA already installed: $installed_cuda_version"
        return 0
    fi

    log "Installing CUDA toolkit package: $CUDA_TOOLKIT_PACKAGE"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$CUDA_TOOLKIT_PACKAGE"
    echo "CUDA toolkit installation completed"
}

configure_cuda_environment() {
    log "Configuring CUDA environment variables..."

    append_bashrc_once "# CUDA $REQUIRED_CUDA_VERSION"
    append_bashrc_once "export CUDA_HOME=$CUDA_PATH"
    append_bashrc_once 'export PATH=$CUDA_HOME/bin:$PATH'
    append_bashrc_once 'export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH'

    export CUDA_HOME="$CUDA_PATH"
    export PATH="$CUDA_HOME/bin:$PATH"
    export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"

    echo "CUDA_HOME=$CUDA_HOME"
}

log "Checking CUDA setup..."
echo "Configured CUDA_VERSION: $CUDA_VERSION"
echo "Expected toolkit package: $CUDA_TOOLKIT_PACKAGE"
echo "Expected CUDA path: $CUDA_PATH"

sudo -v

clean_old_cuda_repos
install_required_packages
install_cuda_keyring
update_apt_after_keyring
install_cuda_toolkit
configure_cuda_environment

log "Final nvcc version..."
if nvcc_path="$(get_nvcc_path)"; then
    "$nvcc_path" --version
else
    fail "nvcc was not found after installing $CUDA_TOOLKIT_PACKAGE"
fi

echo ""
echo "CUDA setup completed"
