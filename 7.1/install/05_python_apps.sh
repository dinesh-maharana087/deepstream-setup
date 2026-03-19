#!/bin/bash
set -e

source ../config/versions.env
source ../utils/logger.sh

DS_PATH="/opt/nvidia/deepstream/deepstream-${DEEPSTREAM_VERSION}"

echo "Installing DeepStream Python Apps..."

cd $DS_PATH/sources/

sudo git clone --branch $PYTHON_APPS_VERSION --depth 1 \
https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git

cd deepstream_python_apps/

sudo apt install -y python3-gi python3-dev python3-gst-1.0 \
python-gi-dev meson python3-pip python3.10-dev cmake g++ \
build-essential libglib2.0-dev libgstreamer1.0-dev \
libtool m4 autoconf automake libgirepository1.0-dev libcairo2-dev

sudo pip3 install build

git submodule update --init

python3 bindings/3rdparty/git-partial-submodule/git-partial-submodule.py restore-sparse

# Build bindings
cd bindings
export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc)
python3 -m build

cd dist
sudo pip3 install *.whl