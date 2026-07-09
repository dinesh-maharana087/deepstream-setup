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

trap 'log_failure "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" "Python Bindings"; cleanup_python_install; exit 1' ERR

run_as_user() {
    run_as_install_user "$1"
}

log_info "Checking Python bindings installation..."

validate_system
validate_versions_before_install

require_sudo

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

ensure_user_owned_dir "$WORK_DIR"

sudo mkdir -p "$DS_SOURCES_DIR"
sudo chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$DS_SOURCES_DIR"

if [[ -x "$VENV_PATH/bin/python3" ]]; then
    if "$VENV_PATH/bin/python3" -c "import pyds" >/dev/null 2>&1; then
        PYDS_VERSION="$("$VENV_PATH/bin/python3" -c "import pyds; print(getattr(pyds, '__version__', 'unknown'))")"
        log_success "Python bindings already installed in venv"
        log_info "PyDS version: $PYDS_VERSION"
        exit 0
    fi
fi

log_info "Installing Python build dependencies..."

apt_update

PYTHON_BUILD_PACKAGES=(
    git
    python3-gi
    python3-dev
    python3-gst-1.0
    python3-venv
    python3-pip
    meson
    cmake
    g++
    build-essential
    gobject-introspection
    libglib2.0-dev
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
    libtool
    m4
    autoconf
    automake
    libcairo2-dev
)

if apt_package_available python-gi-dev; then
    PYTHON_BUILD_PACKAGES+=(python-gi-dev)
else
    log_warn "Optional package python-gi-dev is not available; continuing with python3-gi."
fi

if apt_package_available libgirepository-2.0-dev; then
    PYTHON_BUILD_PACKAGES+=(libgirepository-2.0-dev)
elif apt_package_available libgirepository1.0-dev; then
    PYTHON_BUILD_PACKAGES+=(libgirepository1.0-dev)
else
    log_error "No supported GObject introspection development package found."
    log_error "Tried: libgirepository-2.0-dev, libgirepository1.0-dev"
    exit 1
fi

sudo apt-get install -y "${PYTHON_BUILD_PACKAGES[@]}"

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

sudo chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$PYDS_DIR"

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
run_as_user "'$VENV_PATH/bin/python3' -m pip install --upgrade '$CUDA_PYTHON_PACKAGE_SPEC'"

log_info "Verifying Python bindings installation..."

if ! run_as_user "'$VENV_PATH/bin/python3' -c 'import pyds; print(\"PyDS import OK\")'"; then
    log_error "Failed to import pyds from venv"
    exit 1
fi

PYDS_VERSION="$(run_as_user "'$VENV_PATH/bin/python3' -c 'import pyds; print(getattr(pyds, \"__version__\", \"unknown\"))'")"

log_info "Cleaning up build artifacts..."
rm -rf "$PYDS_DIR/bindings/build"
rm -rf "$PYDS_DIR/bindings/.eggs"

sudo chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$WORK_DIR"
sudo chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$PYDS_DIR"

log_success "Python bindings installation completed successfully"
log_info "PyDS version: $PYDS_VERSION"
log_info "Virtual environment: $VENV_PATH"
log_info "To use:"
log_info "source $VENV_PATH/bin/activate"
