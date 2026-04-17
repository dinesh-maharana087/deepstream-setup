#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "Checking CUDA..."

# Validate required env vars
required_vars=(
    UBUNTU_VERSION
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Missing required variable in versions.env: $var"
        exit 1
    fi
done

# Normalize CUDA package version
# Prefer CUDA_PKG_VERSION if provided, otherwise convert CUDA_VERSION 12.2 -> 12-2
if [[ -n "${CUDA_PKG_VERSION:-}" ]]; then
    CUDA_PKG="${CUDA_PKG_VERSION}"
elif [[ -n "${CUDA_VERSION:-}" ]]; then
    CUDA_PKG="${CUDA_VERSION//./-}"
else
    echo "Missing CUDA_VERSION or CUDA_PKG_VERSION in versions.env"
    exit 1
fi

CUDA_TOOLKIT_PACKAGE="cuda-toolkit-${CUDA_PKG}"
CUDA_REPO_DEB="cuda-keyring_1.1-1_all.deb"
CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/${CUDA_REPO_DEB}"

# Validate Ubuntu version
UBUNTU="$(check_ubuntu_version)"
if [[ "$UBUNTU" != "$UBUNTU_VERSION" ]]; then
    echo "Unsupported Ubuntu version: $UBUNTU (expected: $UBUNTU_VERSION)"
    exit 1
fi

# Check commands
for cmd in apt dpkg wget sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd"
        exit 1
    fi
done

# If nvcc exists and reports the expected major.minor, skip install
if command -v nvcc >/dev/null 2>&1; then
    INSTALLED_CUDA="$(nvcc --version | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n1)"
    EXPECTED_CUDA="${CUDA_VERSION:-${CUDA_PKG//-/.}}"

    if [[ -n "$INSTALLED_CUDA" && "$INSTALLED_CUDA" == "$EXPECTED_CUDA" ]]; then
        echo "CUDA already installed: ${INSTALLED_CUDA}"
        exit 0
    fi

    echo "Detected CUDA version ${INSTALLED_CUDA:-unknown}, expected ${EXPECTED_CUDA}"
    echo "Continuing with installation/update of ${CUDA_TOOLKIT_PACKAGE}"
fi

# If toolkit package is already installed, skip
if dpkg -s "$CUDA_TOOLKIT_PACKAGE" >/dev/null 2>&1; then
    echo "CUDA toolkit package already installed: $CUDA_TOOLKIT_PACKAGE"
    exit 0
fi

echo "Installing CUDA repository keyring..."
TMP_DEB="/tmp/${CUDA_REPO_DEB}"
wget -O "$TMP_DEB" "$CUDA_REPO_URL"
sudo dpkg -i "$TMP_DEB"
rm -f "$TMP_DEB"

echo "Updating apt metadata..."
sudo apt update

echo "Installing CUDA toolkit package: $CUDA_TOOLKIT_PACKAGE"
if [[ "${STRICT_MODE:-false}" == "true" ]]; then
    sudo apt install -y --no-install-recommends "$CUDA_TOOLKIT_PACKAGE"
else
    sudo apt install -y "$CUDA_TOOLKIT_PACKAGE"
fi

# Verify installation
if ! command -v nvcc >/dev/null 2>&1; then
    echo "CUDA installation completed, but nvcc is not in PATH yet."
    echo "You may need to add /usr/local/cuda/bin to PATH or re-login."
    exit 1
fi

INSTALLED_CUDA="$(nvcc --version | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n1)"
echo "CUDA installation completed: ${INSTALLED_CUDA:-unknown}"