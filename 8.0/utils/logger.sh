#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log directory setup (use WORK_DIR if available, else fallback to logs/)
LOG_DIR="${WORK_DIR:=$(pwd)}/logs"
LOG_FILE="$LOG_DIR/install.log"

mkdir -p "$LOG_DIR"

# Redirect both stdout and stderr to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

# Timestamp function
_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Logger functions with color-coded output
log_info() {
    echo -e "${BLUE}[INFO]${NC} [$(_timestamp)] $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} [$(_timestamp)] $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(_timestamp)] $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(_timestamp)] $*" >&2
}

# Session header
log_info "=========================================="
log_info "Starting installation session: $(_timestamp)"
log_info "=========================================="