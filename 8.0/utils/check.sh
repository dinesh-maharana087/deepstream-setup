#!/bin/bash

check_command() {
    command -v "$1" >/dev/null 2>&1
}

check_package() {
    dpkg -l | awk '{print $2}' | grep -Fxq "$1"
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

    if command -v nvcc >/dev/null 2>&1; then
        return 0
    fi

    if [[ -d "/usr/local/cuda" || -f "/usr/local/cuda/version.txt" ]]; then
        return 0
    fi

    if dpkg -l | grep -qE '^ii\s+cuda-(toolkit|runtime|compiler|cudart)'; then
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

    if command -v nvcc >/dev/null 2>&1; then
        nvcc --version | awk -F'release ' '/release/ {print $2}' | awk -F',' '{print $1}'
        return 0
    fi

    if [[ -f "/usr/local/cuda/version.txt" ]]; then
        cat /usr/local/cuda/version.txt
        return 0
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