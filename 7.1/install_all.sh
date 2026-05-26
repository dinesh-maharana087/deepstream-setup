#!/bin/bash
set -e
set -o pipefail

trap 'echo "❌ Installation failed at line $LINENO. Check logs."' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/config/versions.env"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/check.sh"

echo "====================================="
echo "Starting installation: $(date)"
echo "====================================="

echo "🔍 Running system validation..."
system_summary
validate_system

run_step() {
    local step_name="$1"
    local script_path="$2"

    echo "====================================="
    echo "▶️  Running: $step_name"
    echo "====================================="

    if [ ! -f "$script_path" ]; then
        echo "❌ Missing script: $script_path"
        exit 1
    fi

    bash "$script_path"

    echo "✅ Completed: $step_name"
}

echo "🚀 Starting installation..."

run_step "Prerequisites" "$SCRIPT_DIR/install/01_prerequisites.sh"
run_step "CUDA" "$SCRIPT_DIR/install/02_cuda.sh"
run_step "TensorRT" "$SCRIPT_DIR/install/03_tensorrt.sh"
run_step "DeepStream" "$SCRIPT_DIR/install/04_deepstream.sh"
run_step "DeepStream Python Apps" "$SCRIPT_DIR/install/05_python_apps.sh"

echo "====================================="
echo "✅ ALL DONE!"
echo "Completed at: $(date)"
echo "====================================="

echo "CUDA version:"
nvcc --version || true

echo "TensorRT packages:"
dpkg -l | grep nvinfer || true

echo "DeepStream:"
deepstream-app --version-all || true

echo "Python pyds:"
python3 -c "import pyds; print('pyds installed successfully')" || true