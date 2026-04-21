#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "🔍 Checking Python bindings..."

if check_python_binding; then
    echo "✅ pyds already installed"
    exit 0
fi

DS_PATH="/opt/nvidia/deepstream/deepstream-${DEEPSTREAM_VERSION}"

if [ ! -d "$DS_PATH" ]; then
    echo "❌ DeepStream path not found: $DS_PATH"
    exit 1
fi

echo "Installing DeepStream Python Apps..."

cd "$DS_PATH/sources/"

if [ ! -d "deepstream_python_apps" ]; then
    git clone --branch "$PYTHON_APPS_VERSION" --depth 1 \
        https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git
fi

cd deepstream_python_apps/

echo "Installing dependencies..."

sudo apt-get update
sudo apt-get install -y \
    python3-gi \
    python3-dev \
    python3-gst-1.0 \
    python-gi-dev \
    meson \
    python3-pip \
    python3.10-dev \
    python3.10-venv \
    cmake \
    g++ \
    build-essential \
    libglib2.0-dev \
    libgstreamer1.0-dev \
    libtool \
    m4 \
    autoconf \
    automake \
    libgirepository1.0-dev \
    libcairo2-dev

sudo python3 -m pip install --upgrade build

echo "Updating submodules..."

sudo git submodule update --init
sudo python3 bindings/3rdparty/git-partial-submodule/git-partial-submodule.py restore-sparse

echo "Building gst-python..."

cd bindings/3rdparty/gstreamer/subprojects/gst-python/
meson setup build --reconfigure || true
cd build
ninja
sudo ninja install

cd "$DS_PATH/sources/deepstream_python_apps/bindings"

echo "Building pyds wheel..."
export CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"
sudo python3 -m build

echo "Installing pyds wheel..."
cd dist
sudo python3 -m pip install ./*.whl

echo "Installing cuda-python..."
sudo python3 -m pip install cuda-python

echo "✅ Python bindings installed successfully"