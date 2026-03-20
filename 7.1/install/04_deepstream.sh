#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../config/versions.env"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/check.sh"

echo "🔍 Checking DeepStream..."

if check_deepstream; then
    echo "✅ DeepStream already installed: $(get_deepstream_version)"
    exit 0
fi

echo "Installing DeepStream $DEEPSTREAM_VERSION..."

DEB_FILE="deepstream-${DEEPSTREAM_VERSION}.deb"

curl -L "https://api.ngc.nvidia.com/v2/resources/org/nvidia/deepstream/${DEEPSTREAM_VERSION}/files?redirect=true&path=deepstream-${DEEPSTREAM_VERSION}_${DEEPSTREAM_VERSION}.0-1_amd64.deb" \
-o "$DEB_FILE"

sudo apt install -y ./"$DEB_FILE"

echo "✅ DeepStream installation completed"