#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "🔍 Checking TensorRT installation..."

# Example:
# TENSORRT_VERSION="10.3.0.26-1+cuda12.5"
REQUIRED_TENSORRT_VERSION="$TENSORRT_VERSION"
REQUIRED_TENSORRT_BASE_VERSION="$(echo "$TENSORRT_VERSION" | cut -d'-' -f1)"

TENSORRT_LIB_PATH="/usr/lib/x86_64-linux-gnu"

REQUIRED_TRT_PACKAGES=(
    libnvinfer-dev
    libnvinfer-dispatch-dev
    libnvinfer-dispatch10
    libnvinfer-headers-dev
    libnvinfer-headers-plugin-dev
    libnvinfer-lean-dev
    libnvinfer-lean10
    libnvinfer-plugin-dev
    libnvinfer-plugin10
    libnvinfer-vc-plugin-dev
    libnvinfer-vc-plugin10
    libnvinfer10
    libnvonnxparsers-dev
    libnvonnxparsers10
    tensorrt-dev
)

echo "Required TensorRT package version: $REQUIRED_TENSORRT_VERSION"
echo "Required TensorRT base version   : $REQUIRED_TENSORRT_BASE_VERSION"
echo ""

check_package_installed() {
    local pkg="$1"

    if dpkg -s "$pkg" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

get_package_version() {
    local pkg="$1"
    dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "not installed"
}

check_all_tensorrt_packages() {
    local all_ok=0

    echo "🔎 Verifying TensorRT packages..."
    echo ""

    for pkg in "${REQUIRED_TRT_PACKAGES[@]}"; do
        if ! check_package_installed "$pkg"; then
            echo "❌ Missing: $pkg"
            all_ok=1
            continue
        fi

        installed_version="$(get_package_version "$pkg")"

        if [ "$installed_version" != "$REQUIRED_TENSORRT_VERSION" ]; then
            echo "❌ Version mismatch: $pkg"
            echo "   Installed: $installed_version"
            echo "   Required : $REQUIRED_TENSORRT_VERSION"
            all_ok=1
        else
            echo "✅ $pkg = $installed_version"
        fi
    done

    echo ""
    return "$all_ok"
}

check_tensorrt_runtime_files() {
    echo "🔎 Checking TensorRT runtime libraries..."

    local missing=0

    REQUIRED_LIBS=(
        "libnvinfer.so.10"
        "libnvinfer_plugin.so.10"
        "libnvonnxparser.so.10"
    )

    for lib in "${REQUIRED_LIBS[@]}"; do
        if [ -e "$TENSORRT_LIB_PATH/$lib" ]; then
            echo "✅ Found: $TENSORRT_LIB_PATH/$lib"
        else
            echo "❌ Missing library: $TENSORRT_LIB_PATH/$lib"
            missing=1
        fi
    done

    echo ""
    return "$missing"
}

check_tensorrt_headers() {
    echo "🔎 Checking TensorRT headers..."

    local missing=0

    REQUIRED_HEADERS=(
        "/usr/include/x86_64-linux-gnu/NvInfer.h"
        "/usr/include/x86_64-linux-gnu/NvInferPlugin.h"
        "/usr/include/x86_64-linux-gnu/NvOnnxParser.h"
    )

    for header in "${REQUIRED_HEADERS[@]}"; do
        if [ -f "$header" ]; then
            echo "✅ Found: $header"
        else
            echo "❌ Missing header: $header"
            missing=1
        fi
    done

    echo ""
    return "$missing"
}

install_tensorrt_packages() {
    local version="$REQUIRED_TENSORRT_VERSION"

    echo "📦 Installing TensorRT packages..."
    echo "Version: $version"
    echo ""

    sudo apt-get update

    sudo apt-get install -y \
        libnvinfer-dev="${version}" \
        libnvinfer-dispatch-dev="${version}" \
        libnvinfer-dispatch10="${version}" \
        libnvinfer-headers-dev="${version}" \
        libnvinfer-headers-plugin-dev="${version}" \
        libnvinfer-lean-dev="${version}" \
        libnvinfer-lean10="${version}" \
        libnvinfer-plugin-dev="${version}" \
        libnvinfer-plugin10="${version}" \
        libnvinfer-vc-plugin-dev="${version}" \
        libnvinfer-vc-plugin10="${version}" \
        libnvinfer10="${version}" \
        libnvonnxparsers-dev="${version}" \
        libnvonnxparsers10="${version}" \
        tensorrt-dev="${version}"
}

configure_tensorrt_environment() {
    echo "🔧 Configuring TensorRT environment variables..."

    local bashrc="$HOME/.bashrc"
    local backup="$HOME/.bashrc.backup.$(date +%Y%m%d_%H%M%S)"

    if [ -f "$bashrc" ]; then
        cp "$bashrc" "$backup"
        echo "✅ Backup created: $backup"
    fi

    if grep -q "# TensorRT" "$bashrc" 2>/dev/null; then
        echo "✅ TensorRT environment block already exists in ~/.bashrc"
    else
        {
            echo ""
            echo "# TensorRT"
            echo "export TENSORRT_HOME=$TENSORRT_LIB_PATH"
            echo "export LD_LIBRARY_PATH=$TENSORRT_LIB_PATH:\$LD_LIBRARY_PATH"
        } >> "$bashrc"

        echo "✅ TensorRT environment variables added to ~/.bashrc"
    fi

    export TENSORRT_HOME="$TENSORRT_LIB_PATH"
    export LD_LIBRARY_PATH="$TENSORRT_LIB_PATH:$LD_LIBRARY_PATH"

    echo "TENSORRT_HOME=$TENSORRT_HOME"
    echo ""
}

print_tensorrt_summary() {
    echo "📋 TensorRT Summary"
    echo "-------------------"

    if check_package_installed libnvinfer10; then
        echo "libnvinfer10 package version: $(get_package_version libnvinfer10)"
    else
        echo "libnvinfer10 package version: not installed"
    fi

    if [ -e "$TENSORRT_LIB_PATH/libnvinfer.so.10" ]; then
        echo "Runtime library found       : $TENSORRT_LIB_PATH/libnvinfer.so.10"
    else
        echo "Runtime library found       : no"
    fi

    if [ -f "/usr/include/x86_64-linux-gnu/NvInfer.h" ]; then
        echo "TensorRT headers found      : yes"
    else
        echo "TensorRT headers found      : no"
    fi

    echo "TENSORRT_HOME               : ${TENSORRT_HOME:-not set}"
    echo ""
}

# ---------------------------------------------------------
# Main flow
# ---------------------------------------------------------

PACKAGES_OK=0
LIBS_OK=0
HEADERS_OK=0

if check_all_tensorrt_packages; then
    PACKAGES_OK=1
else
    PACKAGES_OK=0
fi

if check_tensorrt_runtime_files; then
    LIBS_OK=1
else
    LIBS_OK=0
fi

if check_tensorrt_headers; then
    HEADERS_OK=1
else
    HEADERS_OK=0
fi

if [ "$PACKAGES_OK" -eq 1 ] && [ "$LIBS_OK" -eq 1 ] && [ "$HEADERS_OK" -eq 1 ]; then
    echo "✅ TensorRT is already fully installed and verified."
    configure_tensorrt_environment
    print_tensorrt_summary
    exit 0
fi

echo "⚠️ TensorRT is missing or incomplete."
echo "Proceeding with installation..."
echo ""

install_tensorrt_packages

echo ""
echo "🔁 Re-checking TensorRT after installation..."
echo ""

POST_PACKAGES_OK=0
POST_LIBS_OK=0
POST_HEADERS_OK=0

if check_all_tensorrt_packages; then
    POST_PACKAGES_OK=1
else
    POST_PACKAGES_OK=0
fi

if check_tensorrt_runtime_files; then
    POST_LIBS_OK=1
else
    POST_LIBS_OK=0
fi

if check_tensorrt_headers; then
    POST_HEADERS_OK=1
else
    POST_HEADERS_OK=0
fi

if [ "$POST_PACKAGES_OK" -ne 1 ] || [ "$POST_LIBS_OK" -ne 1 ] || [ "$POST_HEADERS_OK" -ne 1 ]; then
    echo "❌ TensorRT installation verification failed."
    echo ""
    print_tensorrt_summary
    exit 1
fi

configure_tensorrt_environment

print_tensorrt_summary

echo "✅ TensorRT installation completed and verified successfully."