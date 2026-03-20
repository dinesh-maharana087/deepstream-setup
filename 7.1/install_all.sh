#!/bin/bash

set -e
set -o pipefail

trap 'echo "❌ Installation failed. Check logs."' ERR

echo "🔍 Running system validation..."

source utils/checks.sh
system_summary
validate_system

echo "🚀 Starting installation..."

bash install/01_prerequisites.sh
bash install/02_cuda.sh
bash install/03_tensorrt.sh
bash install/04_deepstream.sh
bash install/05_python_apps.sh

echo "✅ ALL DONE!"