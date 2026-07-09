#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log directory setup (use WORK_DIR if available, else fallback to logs/)
LOG_DIR="${WORK_DIR:-$(pwd)}/logs"
LOG_FILE="${LOG_FILE:-$LOG_DIR/install.log}"

if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    if command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$LOG_DIR"
    else
        echo "[ERROR] Could not create log directory: $LOG_DIR" >&2
        exit 1
    fi
fi

if [[ -n "${INSTALL_USER:-}" && "${INSTALL_USER:-}" != "root" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
        chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$LOG_DIR" 2>/dev/null || true
    elif [[ ! -w "$LOG_DIR" ]]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo chown -R "$INSTALL_USER:${INSTALL_GROUP:-$INSTALL_USER}" "$LOG_DIR"
        else
            echo "[ERROR] Log directory is not writable: $LOG_DIR" >&2
            exit 1
        fi
    fi
fi

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

log_failure() {
    local script="${1:-unknown}"
    local line="${2:-unknown}"
    local command="${3:-unknown}"
    local step="${4:-unknown}"

    log_error "Failure detected"
    log_error "Step: $step"
    log_error "Script: $script"
    log_error "Line: $line"
    log_error "Command: $command"
    log_error "Log file: ${LOG_FILE:-unknown}"
}

# Redirect both stdout and stderr to one shared log stream.
if [[ "${DEEPSTREAM_LOGGER_ACTIVE:-0}" != "1" ]]; then
    export DEEPSTREAM_LOGGER_ACTIVE=1
    exec > >(tee -a "$LOG_FILE") 2>&1

    log_info "=========================================="
    log_info "Starting installation session: $(_timestamp)"
    log_info "Log file: $LOG_FILE"
    log_info "=========================================="
fi
