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