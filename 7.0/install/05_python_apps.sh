#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "Checking DeepStream Python apps and bindings..."

required_vars=(
    DEEPSTREAM_VERSION
    PYTHON_APPS_VERSION
    UBUNTU_VERSION
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Missing required variable in versions.env: $var"
        exit 1
    fi
done

UBUNTU="$(check_ubuntu_version)"
if [[ "$UBUNTU" != "$UBUNTU_VERSION" ]]; then
    echo "Unsupported Ubuntu version: $UBUNTU (expected: $UBUNTU_VERSION)"
    exit 1
fi

for cmd in python3 pip3 git sudo apt-get; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd"
        exit 1
    fi
done

PYTHON_VERSION_DETECTED="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$PYTHON_VERSION_DETECTED" != "3.10" ]]; then
    echo "Unsupported Python version: $PYTHON_VERSION_DETECTED (expected: 3.10 for DeepStream 7.0 Python apps)"
    exit 1
fi

# Detect DeepStream install path
if [[ -d "/opt/nvidia/deepstream/deepstream-${DEEPSTREAM_VERSION}" ]]; then
    DS_PATH="/opt/nvidia/deepstream/deepstream-${DEEPSTREAM_VERSION}"
elif [[ -d "/opt/nvidia/deepstream/deepstream" ]]; then
    DS_PATH="/opt/nvidia/deepstream/deepstream"
else
    echo "DeepStream installation not found."
    echo "Run 04_deepstream.sh first."
    exit 1
fi

# Check whether pyds is already importable
if python3 -c "import pyds" >/dev/null 2>&1; then
    echo "pyds already installed"
    exit 0
fi

echo "Installing Python app dependencies..."

sudo apt-get update

APT_PACKAGES=(
    python3-gi
    python3-dev
    python3-gst-1.0
    python-gi-dev
    python3-pip
    python3-venv
    git
    meson
    cmake
    g++
    build-essential
    libglib2.0-dev
    libglib2.0-dev-bin
    libgstreamer1.0-dev
    libtool
    m4
    autoconf
    automake
    libgirepository1.0-dev
    libcairo2-dev
)

if [[ "${STRICT_MODE:-false}" == "true" ]]; then
    sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
else
    sudo apt-get install -y "${APT_PACKAGES[@]}"
fi

# Keep repo outside /opt to avoid root-owned source checkout
PY_APPS_ROOT="${PYTHON_APPS_ROOT:-/opt/nvidia/deepstream-python-apps}"
PY_APPS_REPO="${PY_APPS_ROOT}/deepstream_python_apps"

if [[ ! -d "$PY_APPS_ROOT" ]]; then
    sudo mkdir -p "$PY_APPS_ROOT"
    sudo chown "$(id -u)":"$(id -g)" "$PY_APPS_ROOT"
fi

if [[ ! -d "$PY_APPS_REPO/.git" ]]; then
    echo "Cloning deepstream_python_apps ${PYTHON_APPS_VERSION}..."
    git clone --branch "$PYTHON_APPS_VERSION" --depth 1 \
        https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git \
        "$PY_APPS_REPO"
else
    echo "deepstream_python_apps repo already present: $PY_APPS_REPO"
fi

cd "$PY_APPS_REPO"

echo "Updating submodules..."
git submodule update --init --recursive

# Prefer local prebuilt wheel from NVIDIA release assets
# Example:
#   PYDS_WHL_PATH=/opt/installers/pyds-1.1.11-*.whl
#
# Fallback search locations are included for convenience.
WHEEL_CANDIDATES=()

if [[ -n "${PYDS_WHL_PATH:-}" ]]; then
    WHEEL_CANDIDATES+=("${PYDS_WHL_PATH}")
fi

if [[ -d "$SCRIPT_DIR/../packages" ]]; then
    while IFS= read -r -d '' f; do
        WHEEL_CANDIDATES+=("$f")
    done < <(find "$SCRIPT_DIR/../packages" -maxdepth 1 -type f -name "pyds-*.whl" -print0)
fi

if [[ -d "$PY_APPS_REPO/bindings/dist" ]]; then
    while IFS= read -r -d '' f; do
        WHEEL_CANDIDATES+=("$f")
    done < <(find "$PY_APPS_REPO/bindings/dist" -maxdepth 1 -type f -name "pyds-*.whl" -print0)
fi

INSTALL_DONE=false

for whl in "${WHEEL_CANDIDATES[@]:-}"; do
    if [[ -f "$whl" ]]; then
        echo "Installing pyds wheel: $whl"
        python3 -m pip install --no-cache-dir "$whl"
        INSTALL_DONE=true
        break
    fi
done

if [[ "$INSTALL_DONE" != "true" ]]; then
    echo "No prebuilt pyds wheel found."
    echo "Building bindings from source..."

    python3 -m pip install --no-cache-dir build

    cd "$PY_APPS_REPO/bindings"

    # Build with the repository's build system for the checked-out tag
    mkdir -p build
    cd build
    cmake ..
    make -j"$(nproc)"

    cd "$PY_APPS_REPO/bindings"
    python3 -m pip install --no-cache-dir .
fi

# Optional CUDA Python package aligned to CUDA 12.2 stack
# Install only if you actually need it for your apps.
if [[ "${INSTALL_CUDA_PYTHON:-false}" == "true" ]]; then
    python3 -m pip install --no-cache-dir "cuda-python>=12.2,<13"
fi

# Verify
if ! python3 -c "import pyds" >/dev/null 2>&1; then
    echo "pyds installation failed"
    exit 1
fi

echo "DeepStream Python bindings installed successfully"
echo "Repository path: $PY_APPS_REPO"