#!/bin/bash

###############################################################################
# DeepStream 8.0 Python Bindings Installer
#
# Production-safe:
# - Uses real sudo user work directory
# - Avoids /root ownership problems
# - No broken pipe from head/tail pipelines
# - Uses full build log
# - Safe for repeated execution
# - Keeps install inside venv
###############################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

INSTALL_USER="${INSTALL_USER:-${SUDO_USER:-$(logname 2>/dev/null || whoami)}}"
INSTALL_HOME="${INSTALL_HOME:-$(getent passwd "$INSTALL_USER" | cut -d: -f6)}"

if [[ -z "${WORK_DIR:-}" || "$WORK_DIR" == "/root/"* ]]; then
    WORK_DIR="$INSTALL_HOME/deepstream-install"
fi

VENV_PATH="$WORK_DIR/deepstream_venv"
BUILD_LOG="$WORK_DIR/pyds_build.log"

cleanup_python_install() {
    log_warn "Cleaning up Python build artifacts..."
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/build" || true
    rm -rf "$WORK_DIR/deepstream_python_apps/bindings/.eggs" || true
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
log_info "Work directory: $WORK_DIR"
log_info "Virtual environment: $VENV_PATH"

mkdir -p "$WORK_DIR"
sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$WORK_DIR"

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

if [[ ! -d "$WORK_DIR/deepstream_python_apps/.git" ]]; then
    log_info "Cloning DeepStream Python apps repository..."
    run_as_user "cd '$WORK_DIR' && git clone --branch '$PYTHON_APPS_VERSION' --depth 1 https://github.com/NVIDIA-AI-IOT/deepstream_python_apps.git"
    log_success "Repository cloned"
else
    log_info "DeepStream Python apps repository already exists"
fi

sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$WORK_DIR/deepstream_python_apps"

log_info "Updating git submodules..."
run_as_user "cd '$WORK_DIR/deepstream_python_apps' && git submodule update --init --recursive"

log_info "Restoring sparse submodules..."
run_as_user "cd '$WORK_DIR/deepstream_python_apps' && '$VENV_PATH/bin/python3' bindings/3rdparty/git-partial-submodule/git-partial-submodule.py restore-sparse"

log_info "Building Python bindings. Full log: $BUILD_LOG"

run_as_user "cd '$WORK_DIR/deepstream_python_apps/bindings' && export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) && '$VENV_PATH/bin/python3' -m build --verbose 2>&1 | tee '$BUILD_LOG'"

WHEEL_FILE="$(ls -1t "$WORK_DIR"/deepstream_python_apps/bindings/dist/*.whl 2>/dev/null | head -1 || true)"

if [[ -z "$WHEEL_FILE" ]]; then
    log_error "Failed to build Python wheel"
    log_error "Check build log: $BUILD_LOG"
    exit 1
fi

log_info "Built wheel: $(basename "$WHEEL_FILE")"

log_info "Installing PyDS wheel into venv..."
run_as_user "'$VENV_PATH/bin/python3' -m pip install '$WHEEL_FILE'"

log_info "Installing cuda-python package into venv..."
run_as_user "'$VENV_PATH/bin/python3' -m pip install 'cuda-python==12.8'"

log_info "Verifying Python bindings installation..."

if ! run_as_user "'$VENV_PATH/bin/python3' -c 'import pyds; print(\"PyDS import OK\")'"; then
    log_error "Failed to import pyds from venv"
    exit 1
fi

PYDS_VERSION="$(sudo -u "$INSTALL_USER" -H "$VENV_PATH/bin/python3" -c "import pyds; print(getattr(pyds, '__version__', 'unknown'))")"

log_info "Cleaning up build artifacts..."
rm -rf "$WORK_DIR/deepstream_python_apps/bindings/build"
rm -rf "$WORK_DIR/deepstream_python_apps/bindings/.eggs"
sudo chown -R "$INSTALL_USER:$INSTALL_USER" "$WORK_DIR"

log_success "Python bindings installation completed successfully"
log_info "PyDS version: $PYDS_VERSION"
log_info "Virtual environment: $VENV_PATH"
log_info "To use:"
log_info "source $VENV_PATH/bin/activate"