#!/bin/bash

# -------------------------------
# Generic helpers
# -------------------------------

check_command() {
    command -v "$1" >/dev/null 2>&1
}

check_package() {
    dpkg -l | grep -qw "$1"
}

# -------------------------------
# System checks
# -------------------------------

check_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_ID"
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

# -------------------------------
# NVIDIA / GPU checks
# -------------------------------

check_nvidia_driver() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null
        return 0
    else
        return 1
    fi
}

check_gpu_available() {
    nvidia-smi >/dev/null 2>&1
}

# -------------------------------
# CUDA checks (robust)
# -------------------------------

check_cuda() {
    # Method 1: nvcc in PATH
    if command -v nvcc >/dev/null 2>&1; then
        return 0
    fi

    # Method 2: check default install path
    if [ -d "/usr/local/cuda" ]; then
        return 0
    fi

    # Method 3: check version file
    if [ -f "/usr/local/cuda/version.txt" ]; then
        return 0
    fi

    return 1
}

get_cuda_version() {
    if command -v nvcc >/dev/null 2>&1; then
        nvcc --version | grep "release" | awk '{print $6}' | cut -c2-
    elif [ -f "/usr/local/cuda/version.txt" ]; then
        cat /usr/local/cuda/version.txt
    else
        echo "not installed"
    fi
}

# -------------------------------
# TensorRT check
# -------------------------------

check_tensorrt() {
    dpkg -l | grep -q libnvinfer
}

# -------------------------------
# DeepStream check
# -------------------------------

check_deepstream() {
    [ -d "/opt/nvidia/deepstream" ]
}

get_deepstream_version() {
    ls /opt/nvidia/deepstream/ 2>/dev/null | grep deepstream-
}

# -------------------------------
# Python binding check
# -------------------------------

check_python_binding() {
    python3 -c "import pyds" >/dev/null 2>&1
}

# -------------------------------
# Full system summary (🔥 useful)
# -------------------------------

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
        echo "TensorRT: ✅ Installed"
    else
        echo "TensorRT: ❌ Not installed"
    fi

    if check_deepstream; then
        echo "DeepStream: ✅ Installed ($(get_deepstream_version))"
    else
        echo "DeepStream: ❌ Not installed"
    fi

    if check_python_binding; then
        echo "Python Bindings (pyds): ✅ Installed"
    else
        echo "Python Bindings (pyds): ❌ Not installed"
    fi

    echo "================================="
}

validate_system() {
    log_info "🔍 Validating system prerequisites..."

    UBUNTU=$(check_ubuntu_version)

    # Strict Ubuntu 24.04 check - hard-fail on mismatch
    if [[ "$UBUNTU" != "24.04" ]]; then
        log_error "❌ DeepStream 8.0 requires Ubuntu 24.04 exclusively. Found: $UBUNTU"
        log_error "This installer does not support other Ubuntu versions."
        exit 1
    fi
    log_success "✅ Ubuntu version 24.04 verified"

    # GPU check (configurable via GPU_REQUIRED environment variable)
    if [[ "${GPU_REQUIRED:-true}" == "true" ]]; then
        if ! check_gpu_available; then
            log_error "❌ GPU not detected. Required for DeepStream 8.0."
            log_error "   To skip GPU check (testing only), set: GPU_REQUIRED=false"
            exit 1
        fi
        log_success "✅ GPU detected and verified"
    else
        log_warn "⚠️  GPU check skipped (GPU_REQUIRED=false)"
    fi

    log_info "✅ System validation passed"
}

# Version validation functions
validate_ubuntu_version() {
    local expected="24.04"
    local actual=$(check_ubuntu_version)
    
    if [[ "$actual" != "$expected" ]]; then
        log_error "❌ Ubuntu version mismatch. Expected: $expected, Found: $actual"
        return 1
    fi
    return 0
}

validate_cuda_version() {
    local expected_version="$CUDA_VERSION"
    
    if ! check_cuda; then
        log_error "❌ CUDA is not installed"
        return 1
    fi
    
    local actual_version=$(get_cuda_version)
    log_info "CUDA version detected: $actual_version (expected format: $expected_version)"
    return 0
}

validate_tensorrt_version() {
    if ! check_tensorrt; then
        log_error "❌ TensorRT is not installed"
        return 1
    fi
    
    log_info "✅ TensorRT is installed"
    return 0
}

validate_deepstream_version() {
    if ! check_deepstream; then
        log_error "❌ DeepStream is not installed"
        return 1
    fi
    
    local version=$(get_deepstream_version)
    log_info "✅ DeepStream is installed: $version"
    return 0
}

# Comprehensive version validation before installation
validate_versions_before_install() {
    log_info "🔍 Validating required version constants..."
    
    local missing_vars=()
    
    # Check required env vars from versions.env
    if [[ -z "$CUDA_VERSION" ]]; then
        missing_vars+=("CUDA_VERSION")
    fi
    
    if [[ -z "$TENSORRT_VERSION" ]]; then
        missing_vars+=("TENSORRT_VERSION")
    fi
    
    if [[ -z "$DEEPSTREAM_VERSION" ]]; then
        missing_vars+=("DEEPSTREAM_VERSION")
    fi
    
    if [[ -z "$WORK_DIR" ]]; then
        missing_vars+=("WORK_DIR")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "❌ Missing required version constants: ${missing_vars[*]}"
        log_error "   Ensure versions.env is properly sourced"
        return 1
    fi
    
    log_success "✅ All version constants defined:"
    log_info "   CUDA_VERSION=$CUDA_VERSION"
    log_info "   TENSORRT_VERSION=$TENSORRT_VERSION"
    log_info "   DEEPSTREAM_VERSION=$DEEPSTREAM_VERSION"
    log_info "   WORK_DIR=$WORK_DIR"
    
    return 0
}