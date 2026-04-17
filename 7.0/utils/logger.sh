#!/usr/bin/env bash

# Prevent double initialization if sourced multiple times
if [[ -n "${LOGGER_INITIALIZED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
LOGGER_INITIALIZED=1

# Resolve project root relative to this file:
# project/
#   utils/logger.sh
#   logs/
LOGGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$LOGGER_DIR/.." && pwd)"

LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_FILE="${LOG_FILE:-$LOG_DIR/install_${TIMESTAMP}.log}"
LATEST_LOG_LINK="$LOG_DIR/install.log"

mkdir -p "$LOG_DIR"

# Send all stdout/stderr to both console and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Maintain a stable "latest" log symlink for convenience
ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LOG_LINK"

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*"
}

log_error() {
    echo "[ERROR] $*"
}

log_section() {
    echo
    echo "====================================="
    echo "$*"
    echo "====================================="
}

log_info "Starting installation: $(date '+%Y-%m-%d %H:%M:%S %Z')"
log_info "Log file: $LOG_FILE"