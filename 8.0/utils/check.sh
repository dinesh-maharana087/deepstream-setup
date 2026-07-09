#!/bin/bash

check_command() {
    command -v "$1" >/dev/null 2>&1
}

check_package() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

require_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi

    if ! sudo -v; then
        log_error "sudo access is required."
        return 1
    fi
}

run_as_install_user() {
    local command="$1"

    if [[ -z "${INSTALL_USER:-}" ]]; then
        log_error "INSTALL_USER is not set."
        return 1
    fi

    if [[ "$(id -un)" == "$INSTALL_USER" ]]; then
        bash -lc "$command"
    else
        sudo -u "$INSTALL_USER" -H bash -lc "$command"
    fi
}

ensure_user_owned_dir() {
    local directory="$1"

    sudo mkdir -p "$directory"

    if [[ -n "${INSTALL_USER:-}" && "${INSTALL_USER:-}" != "root" ]]; then
        sudo chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$directory"
    fi
}

wait_for_apt_lock() {
    log_info "Waiting for package manager lock..."

    while \
        sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1
    do
        sleep 2
    done
}

apt_update() {
    local attempt

    for attempt in {1..5}; do
        if sudo apt-get update; then
            return 0
        fi

        log_warn "apt update failed attempt ${attempt}/5. Retrying..."
        sleep 5
    done

    log_error "Unable to update package index."
    return 1
}

check_broken_packages() {
    local broken_pkgs

    broken_pkgs="$(dpkg -l | awk '$1=="iF" || $1=="iU" || $1=="iH"{print $2}')"

    if [[ -n "$broken_pkgs" ]]; then
        log_error "Broken or half-installed packages detected:"
        echo "$broken_pkgs"
        log_error "Fix broken packages manually before running this installer."
        return 1
    fi
}

apt_package_available() {
    local package="$1"
    apt-cache show "$package" >/dev/null 2>&1
}

apt_package_version_available() {
    local package="$1"
    local version="$2"

    apt-cache madison "$package" 2>/dev/null | awk -v ver="$version" '$3 == ver {found=1} END {exit found ? 0 : 1}'
}

check_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${VERSION_ID:-unknown}"
    else
        echo "unknown"
    fi
}

check_kernel_version() {
    uname -r
}

check_cpu_cores() {
    nproc
}

check_nvidia_driver() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1
        return 0
    fi
    return 1
}

check_gpu_available() {
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1
}

get_cuda_nvcc() {
    local candidate

    if command -v nvcc >/dev/null 2>&1; then
        command -v nvcc
        return 0
    fi

    for candidate in \
        "/usr/local/cuda-${CUDA_VERSION:-}/bin/nvcc" \
        "/usr/local/cuda/bin/nvcc"
    do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

get_deepstream_app_bin() {
    if command -v deepstream-app >/dev/null 2>&1; then
        command -v deepstream-app
        return 0
    fi

    local candidate
    candidate="$(find /opt/nvidia/deepstream -path "*/bin/deepstream-app" -o -path "*/deepstream-app" 2>/dev/null | head -1)"

    if [[ -n "$candidate" && -x "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    return 1
}

check_deepstream() {
    get_deepstream_app_bin >/dev/null 2>&1 || [[ -d "/opt/nvidia/deepstream/deepstream-${DEEPSTREAM_VERSION:-8.0}" ]]
}

get_deepstream_version() {
    local ds_app
    ds_app="$(get_deepstream_app_bin 2>/dev/null || true)"

    if [[ -n "$ds_app" ]]; then
        "$ds_app" --version-all 2>/dev/null | awk -F': ' '/DeepStreamSDK/ {print $2; exit}'
        return 0
    fi

    ls /opt/nvidia/deepstream/ 2>/dev/null | grep -E '^deepstream-[0-9]+' | tail -1 || echo "unknown"
}

check_cuda() {
    local ds_app
    ds_app="$(get_deepstream_app_bin 2>/dev/null || true)"

    if [[ -n "$ds_app" ]] && "$ds_app" --version-all 2>/dev/null | grep -q "CUDA Runtime Version"; then
        return 0
    fi

    if get_cuda_nvcc >/dev/null 2>&1; then
        return 0
    fi

    if [[ -d "/usr/local/cuda" || -f "/usr/local/cuda/version.txt" ]]; then
        return 0
    fi

    if [[ -n "${CUDA_APT_PACKAGE:-}" ]] && check_package "$CUDA_APT_PACKAGE"; then
        return 0
    fi

    if dpkg-query -W -f='${Status}\n' 'cuda-toolkit-*' 2>/dev/null | grep -q "install ok installed"; then
        return 0
    fi

    return 1
}

get_cuda_version() {
    local ds_app
    ds_app="$(get_deepstream_app_bin 2>/dev/null || true)"

    if [[ -n "$ds_app" ]]; then
        local runtime
        runtime="$("$ds_app" --version-all 2>/dev/null | awk -F': ' '/CUDA Runtime Version/ {print $2; exit}')"
        if [[ -n "$runtime" ]]; then
            echo "$runtime"
            return 0
        fi
    fi

    local nvcc_bin
    nvcc_bin="$(get_cuda_nvcc 2>/dev/null || true)"

    if [[ -n "$nvcc_bin" ]]; then
        "$nvcc_bin" --version | awk -F'release ' '/release/ {print $2}' | awk -F',' '{print $1}'
        return 0
    fi

    if [[ -f "/usr/local/cuda/version.txt" ]]; then
        cat /usr/local/cuda/version.txt
        return 0
    fi

    if [[ -n "${CUDA_APT_PACKAGE:-}" ]]; then
        dpkg-query -W -f='${Version}\n' "$CUDA_APT_PACKAGE" 2>/dev/null | head -1 && return 0
    fi

    echo "not installed"
}

check_tensorrt() {
    local ds_app
    ds_app="$(get_deepstream_app_bin 2>/dev/null || true)"

    if [[ -n "$ds_app" ]] && "$ds_app" --version-all 2>/dev/null | grep -q "TensorRT Version"; then
        return 0
    fi

    dpkg -l | grep -qE '^ii\s+(libnvinfer|tensorrt|libnvonnxparsers|libnvinfer-plugin)'
}

get_tensorrt_version() {
    local ds_app
    ds_app="$(get_deepstream_app_bin 2>/dev/null || true)"

    if [[ -n "$ds_app" ]]; then
        local trt
        trt="$("$ds_app" --version-all 2>/dev/null | awk -F': ' '/TensorRT Version/ {print $2; exit}')"
        if [[ -n "$trt" ]]; then
            echo "$trt"
            return 0
        fi
    fi

    dpkg-query -W -f='${Version}\n' libnvinfer10 2>/dev/null | head -1 || echo "unknown"
}

check_python_binding() {
    local venv_python=""

    if [[ -n "${WORK_DIR:-}" && -x "$WORK_DIR/deepstream_venv/bin/python3" ]]; then
        venv_python="$WORK_DIR/deepstream_venv/bin/python3"
    elif [[ -n "${VENV_PATH:-}" && -x "$VENV_PATH/bin/python3" ]]; then
        venv_python="$VENV_PATH/bin/python3"
    fi

    if [[ -n "$venv_python" ]]; then
        "$venv_python" -c "import pyds" >/dev/null 2>&1
        return $?
    fi

    python3 -c "import pyds" >/dev/null 2>&1
}

get_pyds_version() {
    local venv_python=""

    if [[ -n "${WORK_DIR:-}" && -x "$WORK_DIR/deepstream_venv/bin/python3" ]]; then
        venv_python="$WORK_DIR/deepstream_venv/bin/python3"
    elif [[ -n "${VENV_PATH:-}" && -x "$VENV_PATH/bin/python3" ]]; then
        venv_python="$VENV_PATH/bin/python3"
    else
        venv_python="python3"
    fi

    "$venv_python" -c "import pyds; print(getattr(pyds, '__version__', 'unknown'))" 2>/dev/null || echo "not installed"
}

system_summary() {
    echo "========== SYSTEM INFO =========="
    echo "Ubuntu Version: $(check_ubuntu_version)"
    echo "Kernel Version: $(check_kernel_version)"
    echo "CPU Cores: $(check_cpu_cores)"
    echo "--------------------------------"

    if check_gpu_available; then
        echo "GPU: ✅ Available"
        echo "Driver Version: $(check_nvidia_driver)"
    else
        echo "GPU: ❌ Not detected"
    fi

    echo "--------------------------------"

    if check_cuda; then
        echo "CUDA: ✅ Installed ($(get_cuda_version))"
    else
        echo "CUDA: ❌ Not installed"
    fi

    if check_tensorrt; then
        echo "TensorRT: ✅ Installed ($(get_tensorrt_version))"
    else
        echo "TensorRT: ❌ Not installed"
    fi

    if check_deepstream; then
        echo "DeepStream: ✅ Installed ($(get_deepstream_version))"
    else
        echo "DeepStream: ❌ Not installed"
    fi

    if check_python_binding; then
        echo "Python Bindings (pyds): ✅ Installed ($(get_pyds_version))"
    else
        echo "Python Bindings (pyds): ❌ Not installed"
    fi

    echo "================================="
}

validate_system() {
    log_info "🔍 Validating system prerequisites..."

    local UBUNTU
    UBUNTU="$(check_ubuntu_version)"

    if [[ "$UBUNTU" != "24.04" ]]; then
        log_error "❌ DeepStream 8.0 requires Ubuntu 24.04. Found: $UBUNTU"
        exit 1
    fi

    log_success "✅ Ubuntu version 24.04 verified"

    if [[ "${GPU_REQUIRED:-true}" == "true" ]]; then
        if ! check_gpu_available; then
            log_error "❌ GPU not detected. Required for DeepStream 8.0."
            log_error "   To skip GPU check for testing only: GPU_REQUIRED=false"
            exit 1
        fi
        log_success "✅ GPU detected and verified"
    else
        log_warn "⚠️ GPU check skipped"
    fi

    log_success "✅ System validation passed"
}

validate_ubuntu_version() {
    local expected="24.04"
    local actual
    actual="$(check_ubuntu_version)"

    if [[ "$actual" != "$expected" ]]; then
        log_error "❌ Ubuntu version mismatch. Expected: $expected, Found: $actual"
        return 1
    fi

    return 0
}

validate_cuda_version() {
    if ! check_cuda; then
        log_error "❌ CUDA is not installed or not detected"
        return 1
    fi

    log_info "✅ CUDA detected: $(get_cuda_version)"
    return 0
}

validate_tensorrt_version() {
    if ! check_tensorrt; then
        log_error "❌ TensorRT is not installed or not detected"
        return 1
    fi

    log_info "✅ TensorRT detected: $(get_tensorrt_version)"
    return 0
}

validate_deepstream_version() {
    if ! check_deepstream; then
        log_error "❌ DeepStream is not installed"
        return 1
    fi

    log_info "✅ DeepStream detected: $(get_deepstream_version)"
    return 0
}

validate_versions_before_install() {
    log_info "🔍 Validating required version constants..."

    local missing_vars=()

    [[ -z "${CUDA_VERSION:-}" ]] && missing_vars+=("CUDA_VERSION")
    [[ -z "${TENSORRT_VERSION:-}" ]] && missing_vars+=("TENSORRT_VERSION")
    [[ -z "${DEEPSTREAM_VERSION:-}" ]] && missing_vars+=("DEEPSTREAM_VERSION")
    [[ -z "${WORK_DIR:-}" ]] && missing_vars+=("WORK_DIR")
    [[ -z "${PYTHON_APPS_VERSION:-}" ]] && missing_vars+=("PYTHON_APPS_VERSION")

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "❌ Missing required constants: ${missing_vars[*]}"
        log_error "   Ensure config/versions.env is properly sourced"
        return 1
    fi

    log_success "✅ All version constants defined:"
    log_info "   CUDA_VERSION=$CUDA_VERSION"
    log_info "   TENSORRT_VERSION=$TENSORRT_VERSION"
    log_info "   DEEPSTREAM_VERSION=$DEEPSTREAM_VERSION"
    log_info "   PYTHON_APPS_VERSION=$PYTHON_APPS_VERSION"
    log_info "   WORK_DIR=$WORK_DIR"

    return 0
}

# ASCII-only overrides used by the 8.0 installer.
system_summary() {
    echo "========== SYSTEM INFO =========="
    echo "Ubuntu Version: $(check_ubuntu_version)"
    echo "Kernel Version: $(check_kernel_version)"
    echo "CPU Cores: $(check_cpu_cores)"
    echo "Install User: ${INSTALL_USER:-unknown}"
    echo "Work Directory: ${WORK_DIR:-unknown}"
    echo "--------------------------------"

    if check_gpu_available; then
        echo "GPU: Available"
        echo "Driver Version: $(check_nvidia_driver)"
    else
        echo "GPU: Not detected"
    fi

    echo "--------------------------------"

    if check_cuda; then
        echo "CUDA: Installed ($(get_cuda_version))"
    else
        echo "CUDA: Not installed"
    fi

    if check_tensorrt; then
        echo "TensorRT: Installed ($(get_tensorrt_version))"
    else
        echo "TensorRT: Not installed"
    fi

    if check_deepstream; then
        echo "DeepStream: Installed ($(get_deepstream_version))"
    else
        echo "DeepStream: Not installed"
    fi

    if check_python_binding; then
        echo "Python Bindings (pyds): Installed ($(get_pyds_version))"
    else
        echo "Python Bindings (pyds): Not installed"
    fi

    echo "================================="
}

validate_system() {
    log_info "Validating system prerequisites..."

    local ubuntu
    ubuntu="$(check_ubuntu_version)"

    if [[ "$ubuntu" != "24.04" ]]; then
        log_error "DeepStream 8.0 requires Ubuntu 24.04. Found: $ubuntu"
        exit 1
    fi

    log_success "Ubuntu version 24.04 verified"

    if [[ "${GPU_REQUIRED:-true}" == "true" ]]; then
        if ! check_gpu_available; then
            log_error "GPU not detected. Required for DeepStream 8.0."
            log_error "To skip GPU check for testing only: GPU_REQUIRED=false"
            exit 1
        fi
        log_success "GPU detected and verified"
    else
        log_warn "GPU check skipped"
    fi

    log_success "System validation passed"
}

validate_ubuntu_version() {
    local expected="24.04"
    local actual
    actual="$(check_ubuntu_version)"

    if [[ "$actual" != "$expected" ]]; then
        log_error "Ubuntu version mismatch. Expected: $expected, Found: $actual"
        return 1
    fi

    return 0
}

validate_cuda_version() {
    if ! check_cuda; then
        log_error "CUDA is not installed or not detected"
        return 1
    fi

    log_info "CUDA detected: $(get_cuda_version)"
    return 0
}

validate_tensorrt_version() {
    if ! check_tensorrt; then
        log_error "TensorRT is not installed or not detected"
        return 1
    fi

    log_info "TensorRT detected: $(get_tensorrt_version)"
    return 0
}

validate_deepstream_version() {
    if ! check_deepstream; then
        log_error "DeepStream is not installed"
        return 1
    fi

    log_info "DeepStream detected: $(get_deepstream_version)"
    return 0
}

validate_versions_before_install() {
    log_info "Validating required version constants..."

    local missing_vars=()

    [[ -z "${CUDA_VERSION:-}" ]] && missing_vars+=("CUDA_VERSION")
    [[ -z "${CUDA_PACKAGE_VERSION:-}" ]] && missing_vars+=("CUDA_PACKAGE_VERSION")
    [[ -z "${CUDA_APT_PACKAGE:-}" ]] && missing_vars+=("CUDA_APT_PACKAGE")
    [[ -z "${TENSORRT_VERSION:-}" ]] && missing_vars+=("TENSORRT_VERSION")
    [[ -z "${TENSORRT_PACKAGE_VERSION:-}" ]] && missing_vars+=("TENSORRT_PACKAGE_VERSION")
    [[ -z "${DEEPSTREAM_VERSION:-}" ]] && missing_vars+=("DEEPSTREAM_VERSION")
    [[ -z "${PYTHON_APPS_VERSION:-}" ]] && missing_vars+=("PYTHON_APPS_VERSION")
    [[ -z "${CUDA_PYTHON_PACKAGE_SPEC:-}" ]] && missing_vars+=("CUDA_PYTHON_PACKAGE_SPEC")
    [[ -z "${INSTALL_USER:-}" ]] && missing_vars+=("INSTALL_USER")
    [[ -z "${INSTALL_HOME:-}" ]] && missing_vars+=("INSTALL_HOME")
    [[ -z "${WORK_DIR:-}" ]] && missing_vars+=("WORK_DIR")

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required constants: ${missing_vars[*]}"
        log_error "Ensure config/versions.env is properly sourced"
        return 1
    fi

    log_success "All version constants defined:"
    log_info "   CUDA_VERSION=$CUDA_VERSION"
    log_info "   CUDA_PACKAGE_VERSION=$CUDA_PACKAGE_VERSION"
    log_info "   CUDA_APT_PACKAGE=$CUDA_APT_PACKAGE"
    log_info "   TENSORRT_VERSION=$TENSORRT_VERSION"
    log_info "   TENSORRT_PACKAGE_VERSION=$TENSORRT_PACKAGE_VERSION"
    log_info "   DEEPSTREAM_VERSION=$DEEPSTREAM_VERSION"
    log_info "   PYTHON_APPS_VERSION=$PYTHON_APPS_VERSION"
    log_info "   CUDA_PYTHON_PACKAGE_SPEC=$CUDA_PYTHON_PACKAGE_SPEC"
    log_info "   INSTALL_USER=$INSTALL_USER"
    log_info "   INSTALL_HOME=$INSTALL_HOME"
    log_info "   WORK_DIR=$WORK_DIR"

    return 0
}
