#!/bin/bash

# Error handling: exit on any error, show line numbers
set -e
set -o pipefail
trap 'log_error "Python bindings installation failed at line $LINENO"; cleanup_python_install; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

# Virtual environment path (global, created once)
VENV_PATH="$WORK_DIR/deepstream_venv"

# Cleanup function for error handling
cleanup_python_install() {
    log_warn "Cleaning up Python build artifacts..."
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/build"
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/dist"
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/.eggs"
}

log_info "🔍 Checking Python bindings installation..."

# Pre-flight validation
validate_system
validate_versions_before_install

if ! sudo -n true 2>/dev/null; then
    log_error "❌ This script requires sudo access"
    exit 1
fi

# Check if pyds is already installed (idempotency)
if check_python_binding; then
    log_success "✅ Python bindings (pyds) already installed"
    exit 0
fi

log_info "Installing DeepStream Python bindings..."

# Ensure work directory exists
mkdir -p "$WORK_DIR"

# Install system dependencies for Python build (use apt-get with -y)
log_info "Installing Python build dependencies..."
sudo apt-get install -y \
    python3-gi \
    python3-dev \
    python3-gst-1.0 \
    python-gi-dev \
    meson \
    cmake \
    g++ \
    build-essential \
    libglib2.0-dev \
    libgstreamer1.0-dev \
    libtool \
    m4 \
    autoconf \
    automake \
    libgirepository-2.0-dev \
    libcairo2-dev 2>&1 | grep -v "^Reading\|^Building\|^Selecting"

# Setup Python virtual environment (create once if not exists)
if [ ! -d "$VENV_PATH" ]; then
    log_info "Creating Python virtual environment at: $VENV_PATH"
    python3 -m venv "$VENV_PATH"
    log_success "✅ Virtual environment created"
else
    log_info "Virtual environment already exists at: $VENV_PATH"
fi

# Activate virtual environment
log_info "Activating virtual environment..."
source "$VENV_PATH/bin/activate"

# Upgrade pip and install build tools (in venv, no --break-system-packages)
log_info "Upgrading pip and installing build tools..."
pip install --upgrade pip setuptools wheel 2>&1 | tail -5

# Clone DeepStream Python apps repository (as regular user, not with sudo)
if [ ! -d "$WORK_DIR/deepstream_python_apps" ]; then
    log_info "Cloning DeepStream Python apps repository..."
    cd "$WORK_DIR"
    
    git clone --branch "$PYTHON_APPS_VERSION" --depth 1 \
        https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git
    
    log_success "✅ Repository cloned"
else
    log_info "DeepStream Python apps repository already exists"
fi

cd "$WORK_DIR/deepstream_python_apps"

# Install Python build dependency (in venv)
log_info "Installing Python build package..."
pip install build 2>&1 | tail -5

# Update git submodules
log_info "Updating git submodules..."
git submodule update --init --recursive

# Restore sparse Git submodules using Python script
log_info "Restoring sparse submodules..."
python3 bindings/3rdparty/git-partial-submodule/git-partial-submodule.py restore-sparse

# Build Python bindings using meson/meson-python
cd "$WORK_DIR/deepstream_python_apps/bindings"

log_info "Building Python bindings (this may take several minutes)..."
export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc)
python3 -m build --verbose 2>&1 | head -30

# Verify wheel was created
WHEEL_FILE=$(ls -1t dist/*.whl 2>/dev/null | head -1)
if [ -z "$WHEEL_FILE" ]; then
    log_error "❌ Failed to build Python wheel"
    deactivate
    exit 1
fi

log_info "Built wheel: $(basename "$WHEEL_FILE")"

# Install the wheel (in venv, no --break-system-packages)
log_info "Installing Python wheel..."
pip install "$WHEEL_FILE" 2>&1 | tail -5

# Install CUDA Python bindings (in venv)
log_info "Installing cuda-python package..."
pip install cuda-python==12.8 2>&1 | tail -5

# Return to work directory and verify installation
cd "$WORK_DIR"

# Verify PyDS installation
log_info "Verifying Python bindings installation..."
if ! python3 -c "import pyds; v = pyds.__version__; print(f'PyDS version: {v}')" 2>/dev/null; then
    log_error "❌ Failed to import pyds"
    deactivate
    exit 1
fi

PYDS_VERSION=$(python3 -c "import pyds; print(pyds.__version__)" 2>/dev/null)

# Cleanup build artifacts
log_info "Cleaning up build artifacts..."
rm -rf "$WORK_DIR/deepstream_python_apps/bindings/build"
rm -rf "$WORK_DIR/deepstream_python_apps/bindings/.eggs"

# Deactivate virtual environment (stay activated for subsequent scripts if needed)
# NOTE: Keep venv activated for any subsequent Python operations
# To deactivate later: source "$VENV_PATH/bin/deactivate"

log_success "✅ Python bindings installation completed successfully"
log_info "   PyDS version: $PYDS_VERSION"
log_info "   Virtual environment: $VENV_PATH"
log_info "   To use: source $VENV_PATH/bin/activate"