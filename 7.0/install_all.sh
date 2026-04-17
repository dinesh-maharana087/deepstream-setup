#!/bin/bash

set -e
set -o pipefail

trap 'echo "❌ Installation failed. Check logs."' ERR

# Get absolute path of this script (VERY IMPORTANT)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Running system validation..."

# Source using absolute path
source "$SCRIPT_DIR/utils/check.sh"

system_summary
validate_system

echo "🚀 Starting installation..."

# Run scripts using absolute paths
bash "$SCRIPT_DIR/install/01_prerequisites.sh"
bash "$SCRIPT_DIR/install/02_cuda.sh"
bash "$SCRIPT_DIR/install/03_tensorrt.sh"
bash "$SCRIPT_DIR/install/04_deepstream.sh"
bash "$SCRIPT_DIR/install/05_python_apps.sh"

echo "✅ ALL DONE!"