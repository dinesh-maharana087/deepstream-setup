#!/bin/bash

LOG_DIR="$(pwd)/logs"
LOG_FILE="$LOG_DIR/install.log"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "====================================="
echo "Starting installation: $(date)"
echo "====================================="