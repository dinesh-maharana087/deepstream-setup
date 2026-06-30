#!/bin/bash

###############################################################################
# DeepStream 8.0 Python Bindings Installer
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

BUILD_LOG="$WORK_DIR/pyds_build.log"

cleanup_python_install() {
    log_warn "Cleaning up Python build artifacts..."
    rm -rf "$PYDS_DIR/bindings/build" || true
    rm -rf "$PYDS_DIR/bindings/.eggs" || true
}

trap 'log_error "Python bindings installation failed at line ${LINENO}"; cleanup_python_install; exit 1' ERR

run_as_user() {
    sudo -u "$INSTALL_USER" -H bash -c "$1"
}

log_info "Checking Python bindings installation..."

validate_system
validate_versions_before_install

if ! sudo -v; then
    log_error "sudo access is required."
    exit 1
fi

log_info "Install user: $INSTALL_USER"
log_info "Install home: $INSTALL_HOME"
log_info "Work directory: $WORK_DIR"
log_info "DeepStream directory: $DS_DIR"
log_info "DeepStream sources directory: $DS_SOURCES_DIR"
log_info "Python apps directory: $PYDS_DIR"
log_info "Virtual environment: $VENV_PATH"

if [[ ! -d "$DS_DIR" ]]; then
    log_error "DeepStream directory not found: $DS_DIR"
    exit 1
fi

sudo mkdir -p "$WORK_DIR"
sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$WORK_DIR"

sudo mkdir -p "$DS_SOURCES_DIR"
sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$DS_SOURCES_DIR"

if [[ -x "$VENV_PATH/bin/python3" ]]; then
    if "$VENV_PATH/bin/python3" -c "import pyds" >/dev/null 2>&1; then
        PYDS_VERSION="$("$VENV_PATH/bin/python3" -c "import pyds; print(getattr(pyds, '__version__', 'unknown'))")"
        log_success "Python bindings already installed in venv"
        log_info "PyDS version: $PYDS_VERSION"
        exit 0
    fi
fi

log_info "Installing Python build dependencies..."

sudo apt-get update

sudo apt-get install -y \
    git \
    python3-gi \
    python3-dev \
    python3-gst-1.0 \
    python-gi-dev \
    python3-venv \
    python3-pip \
    meson \
    cmake \
    g++ \
    build-essential \
    libglib2.0-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libtool \
    m4 \
    autoconf \
    automake \
    libgirepository-2.0-dev \
    libcairo2-dev

if [[ ! -d "$VENV_PATH" ]]; then
    log_info "Creating Python virtual environment..."
    run_as_user "python3 -m venv '$VENV_PATH'"
    log_success "Virtual environment created"
else
    log_info "Virtual environment already exists"
fi

log_info "Upgrading pip/build tools inside venv..."
run_as_user "'$VENV_PATH/bin/python3' -m pip install --upgrade pip setuptools wheel build"

if [[ ! -d "$PYDS_DIR/.git" ]]; then
    log_info "Cloning DeepStream Python apps repository into DeepStream sources..."
    run_as_user "cd '$DS_SOURCES_DIR' && git clone --branch '$PYTHON_APPS_VERSION' --depth 1 https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git"
    log_success "Repository cloned: $PYDS_DIR"
else
    log_info "DeepStream Python apps repository already exists: $PYDS_DIR"
    run_as_user "cd '$PYDS_DIR' && git fetch --tags --force"
    run_as_user "cd '$PYDS_DIR' && git checkout '$PYTHON_APPS_VERSION'"
fi

sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$PYDS_DIR"

log_info "Updating git submodules..."
run_as_user "cd '$PYDS_DIR' && git submodule update --init --recursive"

log_info "Restoring sparse submodules..."
run_as_user "cd '$PYDS_DIR' && '$VENV_PATH/bin/python3' bindings/3rdparty/git-partial-submodule/git-partial-submodule.py restore-sparse"

log_info "Building Python bindings. Full log: $BUILD_LOG"

run_as_user "cd '$PYDS_DIR/bindings' && export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) && '$VENV_PATH/bin/python3' -m build --verbose 2>&1 | tee '$BUILD_LOG'"

WHEEL_FILE="$(ls -1t "$PYDS_DIR"/bindings/dist/*.whl 2>/dev/null | head -1 || true)"

if [[ -z "$WHEEL_FILE" ]]; then
    log_error "Failed to build Python wheel"
    log_error "Check build log: $BUILD_LOG"
    exit 1
fi

log_info "Built wheel: $(basename "$WHEEL_FILE")"

log_info "Installing PyDS wheel into venv..."
run_as_user "'$VENV_PATH/bin/python3' -m pip install --force-reinstall '$WHEEL_FILE'"

log_info "Installing cuda-python package into venv..."
run_as_user "'$VENV_PATH/bin/python3' -m pip install --upgrade 'cuda-python==12.8'"

log_info "Verifying Python bindings installation..."

if ! run_as_user "'$VENV_PATH/bin/python3' -c 'import pyds; print(\"PyDS import OK\")'"; then
    log_error "Failed to import pyds from venv"
    exit 1
fi

PYDS_VERSION="$(sudo -u "$INSTALL_USER" -H "$VENV_PATH/bin/python3" -c "import pyds; print(getattr(pyds, '__version__', 'unknown'))")"

log_info "Cleaning up build artifacts..."
rm -rf "$PYDS_DIR/bindings/build"
rm -rf "$PYDS_DIR/bindings/.eggs"

sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$WORK_DIR"
sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$PYDS_DIR"

log_success "Python bindings installation completed successfully"
log_info "PyDS version: $PYDS_VERSION"
log_info "Virtual environment: $VENV_PATH"
log_info "To use:"
log_info "source $VENV_PATH/bin/activate"