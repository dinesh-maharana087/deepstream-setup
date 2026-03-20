#!/bin/bash
set -e
set -o pipefail

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

echo "Installing DeepStream Python Apps..."

cd "$DS_PATH/sources/"

if [ ! -d "deepstream_python_apps" ]; then
    sudo git clone --branch $PYTHON_APPS_VERSION --depth 1 \
    https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git
fi

cd deepstream_python_apps/

echo "Installing dependencies..."

sudo apt install -y python3-gi python3-dev python3-gst-1.0 \
python-gi-dev meson python3-pip python3.10-dev cmake g++ \
build-essential libglib2.0-dev libgstreamer1.0-dev \
libtool m4 autoconf automake libgirepository1.0-dev libcairo2-dev

sudo pip3 install --upgrade build

echo "Updating submodules..."

sudo git submodule update --init

sudo python3 bindings/3rdparty/git-partial-submodule/git-partial-submodule.py restore-sparse

echo "Building bindings..."

cd bindings
export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc)
python3 -m build

cd dist
sudo pip3 install *.whl

echo "✅ Python bindings installed successfully"