#!/usr/bin/env bash
set -Eeuo pipefail

# ====================================================
# DeepStream 6.2 + Python Bindings v1.1.6 Safe Installer
# Target: Jetson L4T R35.3.1 / Ubuntu 20.04 / Python 3.8
# ====================================================

DS_VERSION="6.2"
PYDS_VERSION="1.1.6"

DS_DIR="/opt/nvidia/deepstream/deepstream-6.2"
DS_SOURCES="${DS_DIR}/sources"
PY_APPS_DIR="${DS_SOURCES}/deepstream_python_apps"

PYDS_WHEEL="pyds-1.1.6-py3-none-linux_aarch64.whl"
PYDS_URL="https://github.com/NVIDIA-AI-IOT/deepstream_python_apps/releases/download/v1.1.6/${PYDS_WHEEL}"

DS_DEB="deepstream-6.2_6.2.0-1_arm64.deb"
DS_DEB_URL="https://developer.nvidia.com/downloads/deepstream-62-620-1-arm64-deb"

LOG_FILE="/tmp/deepstream62_install.log"

# Set to 1 only if you want to run apt upgrade.
RUN_APT_UPGRADE="${RUN_APT_UPGRADE:-0}"

# Set to 1 if you want to run a DeepStream Python sample at the end.
RUN_SAMPLE_TEST="${RUN_SAMPLE_TEST:-0}"

USER_NAME="${SUDO_USER:-$USER}"
USER_HOME="$(eval echo "~${USER_NAME}")"
BASHRC="${USER_HOME}/.bashrc"

log() {
  echo ""
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

warn() {
  echo ""
  echo "WARNING: $*" >&2
}

fail() {
  echo ""
  echo "ERROR: $*" >&2
  exit 1
}

on_error() {
  echo ""
  echo "ERROR: Script failed near line ${1}."
  echo "Check log file: ${LOG_FILE}"
}
trap 'on_error $LINENO' ERR

run_as_user() {
  sudo -H -u "$USER_NAME" "$@"
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_missing_apt_packages() {
  local missing=()

  for pkg in "$@"; do
    if pkg_installed "$pkg"; then
      echo "Already installed: $pkg"
    else
      echo "Missing: $pkg"
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    log "Installing missing apt packages..."
    sudo apt install -y "${missing[@]}"
  else
    log "All apt packages in this group are already installed. Skipping."
  fi
}

append_bashrc_once() {
  local line="$1"

  touch "$BASHRC"
  chown "$USER_NAME:$USER_NAME" "$BASHRC"

  if grep -qxF "$line" "$BASHRC"; then
    echo "Already in .bashrc: $line"
  else
    echo "$line" >> "$BASHRC"
    echo "Added to .bashrc: $line"
  fi
}

download_if_missing() {
  local url="$1"
  local output="$2"

  if [ -s "$output" ]; then
    echo "File already exists: $output"
  else
    log "Downloading: $url"
    wget -O "$output" "$url"
  fi
}

pyds_ok_for_user() {
  run_as_user python3 -c "import pyds; raise SystemExit(0 if hasattr(pyds, 'gst_buffer_get_nvds_batch_meta') else 1)" >/dev/null 2>&1
}

pyds_ok_for_root() {
  sudo python3 -c "import pyds; raise SystemExit(0 if hasattr(pyds, 'gst_buffer_get_nvds_batch_meta') else 1)" >/dev/null 2>&1
}

echo "===================================================="
echo " DeepStream 6.2 + Python Bindings v1.1.6 Installer"
echo " Safe / repeatable / skip-installed version"
echo " Log file: ${LOG_FILE}"
echo "===================================================="

exec > >(tee -a "$LOG_FILE") 2>&1

log "Checking user..."
echo "Script user: $USER"
echo "Target install user: $USER_NAME"
echo "Target user home: $USER_HOME"

if [ "$USER_NAME" = "root" ]; then
  warn "Running as root directly. It is better to run this script as the nvidia user, not root."
fi

log "Checking architecture..."
ARCH="$(uname -m)"
echo "Architecture: $ARCH"

if [ "$ARCH" != "aarch64" ]; then
  fail "This script is for Jetson aarch64 only. Detected: $ARCH"
fi

log "Checking L4T version..."
if [ -f /etc/nv_tegra_release ]; then
  cat /etc/nv_tegra_release

  if grep -q "R35 (release), REVISION: 3.1" /etc/nv_tegra_release; then
    echo "L4T R35.3.1 detected. Good for your DeepStream 6.2 setup."
  else
    warn "This is not exactly L4T R35.3.1. DeepStream 6.2 may still work on some R35.x versions, but verify compatibility."
  fi
else
  fail "/etc/nv_tegra_release not found. This does not look like Jetson L4T."
fi

log "Checking Python version..."
python3 --version

if ! python3 -c "import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 8) else 1)"; then
  warn "Python 3.8 was expected for DeepStream Python bindings v1.1.6 on Ubuntu 20.04."
fi

log "Checking sudo access..."
sudo -v

log "Running apt update..."
sudo apt update

if [ "$RUN_APT_UPGRADE" = "1" ]; then
  log "RUN_APT_UPGRADE=1, running apt upgrade..."
  sudo apt upgrade -y
else
  log "Skipping apt upgrade. To enable it, run: RUN_APT_UPGRADE=1 ./install_deepstream62_safe.sh"
fi

log "Installing nvidia-l4t-apt-source if missing..."
install_missing_apt_packages nvidia-l4t-apt-source

log "Refreshing apt after NVIDIA source check..."
sudo apt update

log "Installing JetPack meta package if missing..."
if pkg_installed nvidia-jetpack; then
  echo "nvidia-jetpack already installed. Skipping."
else
  sudo apt install -y nvidia-jetpack
fi

log "Installing DeepStream runtime dependencies if missing..."
install_missing_apt_packages \
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

log "Installing development dependencies if missing..."
install_missing_apt_packages \
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

log "Checking DeepStream installation..."
if [ -d "$DS_DIR" ] && command -v deepstream-app >/dev/null 2>&1; then
  echo "DeepStream appears installed at: $DS_DIR"
  deepstream-app --version-all || true
else
  log "DeepStream 6.2 not found. Installing from Debian package..."
  cd /tmp
  download_if_missing "$DS_DEB_URL" "/tmp/$DS_DEB"
  sudo apt install -y "/tmp/$DS_DEB"
fi

log "Running ldconfig..."
sudo ldconfig

log "Adding environment variables safely..."
append_bashrc_once 'export CUDA_HOME=/usr/local/cuda'
append_bashrc_once 'export PATH=/usr/local/cuda/bin:$PATH'
append_bashrc_once 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/nvidia/deepstream/deepstream-6.2/lib:$LD_LIBRARY_PATH'
append_bashrc_once 'export GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream-6.2/lib/gst-plugins:$GST_PLUGIN_PATH'

export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/opt/nvidia/deepstream/deepstream-6.2/lib:$LD_LIBRARY_PATH
export GST_PLUGIN_PATH=/opt/nvidia/deepstream/deepstream-6.2/lib/gst-plugins:$GST_PLUGIN_PATH

log "Preparing DeepStream sources directory..."
sudo mkdir -p "$DS_SOURCES"
sudo chown -R "$USER_NAME:$USER_NAME" "$DS_SOURCES"

log "Checking deepstream_python_apps repository..."
if [ -d "$PY_APPS_DIR/.git" ]; then
  echo "deepstream_python_apps repo already exists."

  cd "$PY_APPS_DIR"
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD || true)"
  CURRENT_TAG_OR_BRANCH="$(git describe --tags --exact-match 2>/dev/null || echo "$CURRENT_BRANCH")"

  echo "Current repo state: $CURRENT_TAG_OR_BRANCH"

  if git rev-parse --verify "origin/v${PYDS_VERSION}" >/dev/null 2>&1; then
    echo "Remote branch v${PYDS_VERSION} visible."
  fi

  if [ "$CURRENT_BRANCH" = "v${PYDS_VERSION}" ]; then
    echo "Repo already on branch v${PYDS_VERSION}. Skipping clone."
  else
    warn "Repo exists but is not on branch v${PYDS_VERSION}. Leaving it untouched."
    warn "Expected path: $PY_APPS_DIR"
    warn "You can manually inspect it. This script will continue."
  fi
else
  if [ -d "$PY_APPS_DIR" ]; then
    BACKUP_DIR="${PY_APPS_DIR}.backup.$(date '+%Y%m%d_%H%M%S')"
    warn "Directory exists but is not a git repo. Moving it to: $BACKUP_DIR"
    mv "$PY_APPS_DIR" "$BACKUP_DIR"
  fi

  cd "$DS_SOURCES"
  run_as_user git clone --branch "v${PYDS_VERSION}" --depth 1 https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git
fi

log "Downloading NVIDIA pyds wheel if missing..."
cd /tmp
download_if_missing "$PYDS_URL" "/tmp/$PYDS_WHEEL"

log "Checking current-user pyds..."
if pyds_ok_for_user; then
  echo "Correct NVIDIA pyds already installed for user: $USER_NAME"
  run_as_user python3 -c "import pyds; print('User pyds:', pyds.__file__)"
else
  warn "Correct pyds not found for user. Removing wrong pyds if present and installing NVIDIA pyds."
  run_as_user python3 -m pip uninstall -y pyds || true
  run_as_user python3 -m pip install --user --force-reinstall "/tmp/$PYDS_WHEEL"
fi

log "Checking root pyds..."
if pyds_ok_for_root; then
  echo "Correct NVIDIA pyds already installed for root."
  sudo python3 -c "import pyds; print('Root pyds:', pyds.__file__)"
else
  warn "Correct pyds not found for root. Installing NVIDIA pyds for root too."
  sudo python3 -m pip uninstall -y pyds || true
  sudo python3 -m pip install --force-reinstall "/tmp/$PYDS_WHEEL"
fi

log "Verifying pyds for user..."
run_as_user python3 -c "import pyds; print('User pyds:', pyds.__file__); print('gst_buffer_get_nvds_batch_meta:', hasattr(pyds, 'gst_buffer_get_nvds_batch_meta'))"

log "Verifying pyds for root..."
sudo python3 -c "import pyds; print('Root pyds:', pyds.__file__); print('gst_buffer_get_nvds_batch_meta:', hasattr(pyds, 'gst_buffer_get_nvds_batch_meta'))"

log "Adding user to video group if needed..."
if id -nG "$USER_NAME" | grep -qw video; then
  echo "$USER_NAME is already in video group."
else
  sudo usermod -aG video "$USER_NAME"
  warn "$USER_NAME added to video group. Log out and log back in for camera permissions to fully apply."
fi

log "Final DeepStream version check..."
deepstream-app --version-all || warn "deepstream-app version check failed."

log "Checking sample files..."
if [ -f "${DS_DIR}/samples/streams/sample_720p.h264" ]; then
  echo "Found sample_720p.h264"
else
  warn "Missing sample_720p.h264"
fi

if [ -f "${DS_DIR}/samples/streams/sample_1080p_h264.mp4" ]; then
  echo "Found sample_1080p_h264.mp4"
else
  warn "Missing sample_1080p_h264.mp4"
fi

if [ "$RUN_SAMPLE_TEST" = "1" ]; then
  log "RUN_SAMPLE_TEST=1, running deepstream-test1..."
  cd "$PY_APPS_DIR/apps/deepstream-test1"

  run_as_user env \
    CUDA_HOME="$CUDA_HOME" \
    PATH="$PATH" \
    LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
    GST_PLUGIN_PATH="$GST_PLUGIN_PATH" \
    python3 deepstream_test_1.py "${DS_DIR}/samples/streams/sample_720p.h264" || {
      warn "deepstream-test1 failed. This can happen if display/X11 is unavailable."
    }
else
  log "Skipping sample execution. To run it automatically, use: RUN_SAMPLE_TEST=1 ./install_deepstream62_safe.sh"
fi

echo ""
echo "===================================================="
echo " Installation/check completed."
echo " Log file: ${LOG_FILE}"
echo ""
echo " Open a new terminal or run:"
echo " source ~/.bashrc"
echo ""
echo " Test basic Python sample:"
echo " cd ${PY_APPS_DIR}/apps/deepstream-test1"
echo " python3 deepstream_test_1.py ${DS_DIR}/samples/streams/sample_720p.h264"
echo ""
echo " Test nvdsanalytics:"
echo " cd ${PY_APPS_DIR}/apps/deepstream-nvdsanalytics"
echo " python3 deepstream_nvdsanalytics.py file://${DS_DIR}/samples/streams/sample_1080p_h264.mp4"
echo ""
echo " If using a USB camera, log out and log back in after video group change."
echo "===================================================="