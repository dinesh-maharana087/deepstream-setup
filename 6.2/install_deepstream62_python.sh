#!/usr/bin/env bash
set -e

echo "===================================================="
echo " DeepStream 6.2 + Python Bindings v1.1.6 Installer"
echo " Target: Jetson L4T R35.x / Ubuntu 20.04"
echo "===================================================="

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME="$(eval echo ~$USER_NAME)"

DS_VERSION="6.2"
DS_DIR="/opt/nvidia/deepstream/deepstream-6.2"
DS_SOURCES="${DS_DIR}/sources"
PY_APPS_DIR="${DS_SOURCES}/deepstream_python_apps"

PYDS_WHEEL="pyds-1.1.6-py3-none-linux_aarch64.whl"
PYDS_URL="https://github.com/NVIDIA-AI-IOT/deepstream_python_apps/releases/download/v1.1.6/${PYDS_WHEEL}"

DS_DEB="deepstream-6.2_6.2.0-1_arm64.deb"
DS_DEB_URL="https://developer.nvidia.com/downloads/deepstream-62-620-1-arm64-deb"

echo ""
echo "Checking L4T version..."
cat /etc/nv_tegra_release || true

echo ""
echo "Updating system packages..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y nvidia-l4t-apt-source
sudo apt update

echo ""
echo "Installing JetPack runtime/dev packages..."
sudo apt install -y nvidia-jetpack

echo ""
echo "Installing DeepStream dependencies..."
sudo apt install -y \
  libssl1.1 \
  libgstreamer1.0-0 \
  gstreamer1.0-tools \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly \
  gstreamer1.0-libav \
  libgstreamer-plugins-base1.0-dev \
  libgstrtspserver-1.0-0 \
  libgstrtspserver-1.0-dev \
  libjansson4 \
  libyaml-cpp-dev

echo ""
echo "Installing development dependencies..."
sudo apt install -y \
  build-essential \
  cmake \
  git \
  g++ \
  pkg-config \
  m4 \
  autoconf \
  automake \
  libtool \
  libcairo2-dev \
  libglib2.0-dev \
  libglib2.0-dev-bin \
  libjson-glib-dev \
  libgirepository1.0-dev \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  libopencv-dev \
  python3 \
  python3-pip \
  python3-dev \
  python3.8-dev \
  python3-gi \
  python3-gst-1.0 \
  python3-numpy \
  python3-opencv \
  gir1.2-gstreamer-1.0 \
  gir1.2-gst-plugins-base-1.0 \
  v4l-utils \
  wget

echo ""
echo "Installing DeepStream 6.2 if not already installed..."

if [ -d "$DS_DIR" ] && command -v deepstream-app >/dev/null 2>&1; then
  echo "DeepStream 6.2 appears to already be installed."
else
  cd /tmp
  echo "Downloading DeepStream 6.2 Debian package..."
  wget -O "$DS_DEB" "$DS_DEB_URL"

  echo "Installing DeepStream 6.2..."
  sudo apt install -y "/tmp/$DS_DEB"
fi

echo ""
echo "Running ldconfig..."
sudo ldconfig

echo ""
echo "Adding environment variables to ~/.bashrc..."

BASHRC="${USER_HOME}/.bashrc"

grep -qxF 'export CUDA_HOME=/usr/local/cuda' "$BASHRC" || \
  echo 'export CUDA_HOME=/usr/local/cuda' >> "$BASHRC"

grep -qxF 'export PATH=/usr/local/cuda/bin:$PATH' "$BASHRC" || \
  echo 'export PATH=/usr/local/cuda/bin:$PATH' >> "$BASHRC"

grep -qxF 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/nvidia/deepstream/deepstream-6.2/lib:$LD_LIBRARY_PATH' "$BASHRC" || \
  echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/nvidia/deepstream/deepstream-6.2/lib:$LD_LIBRARY_PATH' >> "$BASHRC"

grep -qxF 'export GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream-6.2/lib/gst-plugins:$GST_PLUGIN_PATH' "$BASHRC" || \
  echo 'export GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream-6.2/lib/gst-plugins:$GST_PLUGIN_PATH' >> "$BASHRC"

export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/nvidia/deepstream/deepstream-6.2/lib:$LD_LIBRARY_PATH
export GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream-6.2/lib/gst-plugins:$GST_PLUGIN_PATH

echo ""
echo "Cloning DeepStream Python apps v1.1.6..."

sudo mkdir -p "$DS_SOURCES"
sudo chown -R "$USER_NAME:$USER_NAME" "$DS_SOURCES"

if [ -d "$PY_APPS_DIR" ]; then
  echo "Existing deepstream_python_apps directory found. Removing old copy..."
  rm -rf "$PY_APPS_DIR"
fi

cd "$DS_SOURCES"
git clone --branch v1.1.6 --depth 1 https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git

echo ""
echo "Removing wrong PyPI pyds if installed..."
python3 -m pip uninstall -y pyds || true

echo ""
echo "Downloading NVIDIA DeepStream pyds wheel..."
cd /tmp
rm -f "$PYDS_WHEEL"
wget -O "$PYDS_WHEEL" "$PYDS_URL"

echo ""
echo "Installing pyds for current user: $USER_NAME"
python3 -m pip install --user --force-reinstall "/tmp/$PYDS_WHEEL"

echo ""
echo "Installing pyds for sudo/root Python too..."
sudo python3 -m pip uninstall -y pyds || true
sudo python3 -m pip install --force-reinstall "/tmp/$PYDS_WHEEL"

echo ""
echo "Verifying normal user pyds..."
python3 -c "import pyds; print('User pyds:', pyds.__file__); print('gst_buffer_get_nvds_batch_meta:', hasattr(pyds, 'gst_buffer_get_nvds_batch_meta'))"

echo ""
echo "Verifying sudo/root pyds..."
sudo python3 -c "import pyds; print('Root pyds:', pyds.__file__); print('gst_buffer_get_nvds_batch_meta:', hasattr(pyds, 'gst_buffer_get_nvds_batch_meta'))"

echo ""
echo "Adding user to video group for camera access..."
sudo usermod -aG video "$USER_NAME" || true

echo ""
echo "Running DeepStream version check..."
deepstream-app --version-all || true

echo ""
echo "Testing Python DeepStream sample: deepstream-test1"
cd "$PY_APPS_DIR/apps/deepstream-test1"

python3 deepstream_test_1.py /opt/nvidia/deepstream/deepstream-6.2/samples/streams/sample_720p.h264 || {
  echo ""
  echo "deepstream-test1 failed. This can happen if display/X11 is not available."
  echo "Installation may still be successful. Check errors above."
}

echo ""
echo "===================================================="
echo " Installation finished."
echo " Open a new terminal or run:"
echo " source ~/.bashrc"
echo ""
echo " Test nvdsanalytics with:"
echo " cd $PY_APPS_DIR/apps/deepstream-nvdsanalytics"
echo " python3 deepstream_nvdsanalytics.py file:///opt/nvidia/deepstream/deepstream-6.2/samples/streams/sample_1080p_h264.mp4"
echo "===================================================="