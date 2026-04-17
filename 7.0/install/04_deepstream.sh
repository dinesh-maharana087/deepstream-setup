#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "Checking DeepStream..."

required_vars=(
    DEEPSTREAM_VERSION
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

for cmd in apt-get dpkg-query sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd"
        exit 1
    fi
done

# DeepStream 7.0 dGPU package name from NVIDIA docs
DEEPSTREAM_DEB_DEFAULT="deepstream-${DEEPSTREAM_VERSION}_7.0.0-1_amd64.deb"

# Allow override from env, otherwise look in common local locations
if [[ -n "${DEEPSTREAM_DEB_PATH:-}" ]]; then
    DEB_PATH="${DEEPSTREAM_DEB_PATH}"
elif [[ -f "$SCRIPT_DIR/../packages/${DEEPSTREAM_DEB_DEFAULT}" ]]; then
    DEB_PATH="$SCRIPT_DIR/../packages/${DEEPSTREAM_DEB_DEFAULT}"
elif [[ -f "$PWD/${DEEPSTREAM_DEB_DEFAULT}" ]]; then
    DEB_PATH="$PWD/${DEEPSTREAM_DEB_DEFAULT}"
else
    echo "DeepStream package not found."
    echo "Expected one of:"
    echo "  - DEEPSTREAM_DEB_PATH environment variable"
    echo "  - $SCRIPT_DIR/../packages/${DEEPSTREAM_DEB_DEFAULT}"
    echo "  - $PWD/${DEEPSTREAM_DEB_DEFAULT}"
    exit 1
fi

if [[ ! -f "$DEB_PATH" ]]; then
    echo "DeepStream package file does not exist: $DEB_PATH"
    exit 1
fi

# Verify CUDA is present
if ! command -v nvcc >/dev/null 2>&1; then
    echo "CUDA is not installed or nvcc is not in PATH."
    echo "Run 02_cuda.sh first."
    exit 1
fi

EXPECTED_CUDA="${CUDA_VERSION:-12.2}"
INSTALLED_CUDA="$(nvcc --version | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n1)"
if [[ -n "$INSTALLED_CUDA" && "$INSTALLED_CUDA" != "$EXPECTED_CUDA" ]]; then
    echo "CUDA version mismatch: found $INSTALLED_CUDA, expected $EXPECTED_CUDA"
    exit 1
fi

# Verify TensorRT is present
EXPECTED_TRT_PKG="${TENSORRT_PKG_VERSION:-}"
if [[ -n "$EXPECTED_TRT_PKG" ]]; then
    INSTALLED_TRT_PKG="$(dpkg-query -W -f='${Version}\n' libnvinfer10 2>/dev/null || true)"
    if [[ -z "$INSTALLED_TRT_PKG" ]]; then
        echo "TensorRT is not installed."
        echo "Run 03_tensorrt.sh first."
        exit 1
    fi
    if [[ "$INSTALLED_TRT_PKG" != "$EXPECTED_TRT_PKG" ]]; then
        echo "TensorRT version mismatch: found $INSTALLED_TRT_PKG, expected $EXPECTED_TRT_PKG"
        exit 1
    fi
else
    if ! dpkg-query -W -f='${Version}\n' libnvinfer10 >/dev/null 2>&1; then
        echo "TensorRT is not installed."
        echo "Run 03_tensorrt.sh first."
        exit 1
    fi
fi

# Check whether DeepStream is already installed
if dpkg-query -W -f='${Status}\n' "deepstream-${DEEPSTREAM_VERSION}" 2>/dev/null | grep -q "install ok installed"; then
    echo "DeepStream already installed: deepstream-${DEEPSTREAM_VERSION}"
    exit 0
fi

echo "Installing DeepStream package: $DEB_PATH"
sudo apt-get update

if [[ "${STRICT_MODE:-false}" == "true" ]]; then
    sudo apt-get install -y --no-install-recommends "$DEB_PATH"
else
    sudo apt-get install -y "$DEB_PATH"
fi

# Hold DeepStream package to avoid accidental upgrades
sudo apt-mark hold "deepstream-${DEEPSTREAM_VERSION}" >/dev/null || true

# Run NVIDIA RTSP jitterbuffer fix script if present
RTP_FIX_SCRIPT="/opt/nvidia/deepstream/deepstream/update_rtpmanager.sh"
if [[ -x "$RTP_FIX_SCRIPT" ]]; then
    echo "Running DeepStream RTP manager update script..."
    sudo "$RTP_FIX_SCRIPT"
fi

# Refresh linker cache
sudo ldconfig

# Verify install
if [[ ! -d "/opt/nvidia/deepstream/deepstream" && ! -d "/opt/nvidia/deepstream/deepstream-${DEEPSTREAM_VERSION}" ]]; then
    echo "DeepStream installation completed, but expected install directory was not found."
    exit 1
fi

echo "DeepStream installation completed successfully."