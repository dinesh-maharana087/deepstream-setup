#!/bin/bash

# DeepStream 8.0 Automated Installation Orchestrator
# This script coordinates the installation of CUDA, TensorRT, DeepStream, and Python bindings
# Usage: bash install_all.sh
# Override work dir: WORK_DIR=/custom/path bash install_all.sh
# Skip GPU check (testing): GPU_REQUIRED=false bash install_all.sh

set -Eeuo pipefail

# Main orchestration error handler
CURRENT_STEP_NAME="Orchestration"
trap 'echo "[ERROR] Installation orchestration failed at line $LINENO: $BASH_COMMAND" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and utilities
source "$SCRIPT_DIR/config/versions.env"
source "$SCRIPT_DIR/utils/logger.sh"
source "$SCRIPT_DIR/utils/check.sh"

trap 'log_failure "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" "${CURRENT_STEP_NAME:-Orchestration}"; exit 1' ERR

# ============================================================================
# SYSTEM VALIDATION
# ============================================================================

log_info "=================================================="
log_info "DeepStream 8.0 Installation - Ubuntu 24.04"
log_info "=================================================="

log_info "Starting system validation..."

# Validate system prerequisites
validate_system
validate_versions_before_install

require_sudo
ensure_user_owned_dir "$WORK_DIR"

log_info "Install user: $INSTALL_USER"
log_info "Install group: $INSTALL_GROUP"
log_info "Install home: $INSTALL_HOME"

log_info "Displaying system information..."
system_summary

# ============================================================================
# INSTALLATION ORCHESTRATION
# ============================================================================

declare -a INSTALL_SCRIPTS=(
    "01_prerequisites.sh"
    "02_cuda.sh"
    "03_tensorrt.sh"
    "04_deepstream.sh"
    "05_python_apps.sh"
)

declare -a SCRIPT_NAMES=(
    "System Prerequisites"
    "CUDA Toolkit"
    "TensorRT"
    "DeepStream Runtime"
    "Python Bindings"
)

INSTALL_DIR="$SCRIPT_DIR/install"
TOTAL_SCRIPTS=${#INSTALL_SCRIPTS[@]}
CURRENT_STEP=0
FAILED_SCRIPTS=()
SKIPPED_SCRIPTS=()

log_info "=================================================="
log_info "Installation Plan:"
log_info "=================================================="

for ((i=0; i<TOTAL_SCRIPTS; i++)); do
    printf "  %d. %s (%s)\n" "$((i+1))" "${SCRIPT_NAMES[$i]}" "${INSTALL_SCRIPTS[$i]}"
done

log_info "Work directory: $WORK_DIR"
log_info "=================================================="

# Execute each installation script
for ((i=0; i<TOTAL_SCRIPTS; i++)); do
    CURRENT_STEP=$((i+1))
    SCRIPT_NAME="${SCRIPT_NAMES[$i]}"
    CURRENT_STEP_NAME="$SCRIPT_NAME"
    SCRIPT_FILE="${INSTALL_SCRIPTS[$i]}"
    SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_FILE"
    
    log_info ""
    log_info "=================================================="
    log_info "Step $CURRENT_STEP/$TOTAL_SCRIPTS: $SCRIPT_NAME"
    log_info "Script: $SCRIPT_FILE"
    log_info "=================================================="
    
    # Verify script exists
    if [ ! -f "$SCRIPT_PATH" ]; then
        log_error "❌ Script not found: $SCRIPT_PATH"
        FAILED_SCRIPTS+=("$SCRIPT_FILE")
        continue
    fi
    
    # Make script executable
    chmod +x "$SCRIPT_PATH"
    
    # Execute script with error handling
    if bash "$SCRIPT_PATH"; then
        log_success "✅ $SCRIPT_NAME completed successfully"
    else
        EXIT_CODE=$?
        log_error "Failed step: $CURRENT_STEP/$TOTAL_SCRIPTS - $SCRIPT_NAME"
        log_error "Failed script: $SCRIPT_PATH"
        log_error "Exit code: $EXIT_CODE"
        log_error "See detailed line/command failure above and in: $LOG_FILE"
        log_error "❌ $SCRIPT_NAME failed with exit code $EXIT_CODE"
        FAILED_SCRIPTS+=("$SCRIPT_FILE")
        
        # For failed installation, option to continue or abort
        if [[ "${CONTINUE_ON_ERROR:-false}" != "true" ]]; then
            log_error "Aborting installation due to script failure"
            log_error "To continue on error (testing only): CONTINUE_ON_ERROR=true bash $0"
            exit 1
        fi
    fi
done

# ============================================================================
# INSTALLATION SUMMARY
# ============================================================================

log_info ""
log_info "=================================================="
log_info "Installation Summary"
log_info "=================================================="

if [ ${#FAILED_SCRIPTS[@]} -eq 0 ]; then
    log_success "✅ All installation steps completed successfully!"
    
    # Post-installation verification
    log_info ""
    log_info "Final system status:"
    system_summary
    
    log_info ""
    log_success "🎉 DeepStream 8.0 installation complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. To use Python bindings, activate the virtual environment:"
    log_info "     source $WORK_DIR/deepstream_venv/bin/activate"
    log_info ""
    log_info "  2. Test DeepStream installation:"
    log_info "     $DS_DIR/bin/deepstream-app --version-all"
    log_info ""
    log_info "  3. Run DeepStream sample applications:"
    log_info "     cd $DS_DIR/samples"
    log_info ""
    log_info "Documentation: https://docs.nvidia.com/deepstream/"
    
    exit 0
else
    log_error ""
    log_error "❌ Installation encountered errors in ${#FAILED_SCRIPTS[@]} script(s):"
    for script in "${FAILED_SCRIPTS[@]}"; do
        log_error "   - $script"
    done
    
    log_error ""
    log_error "Installation directory: $WORK_DIR"
    log_error "Log file: $LOG_FILE"
    log_error ""
    log_error "To retry individual scripts:"
    for script in "${FAILED_SCRIPTS[@]}"; do
        log_error "  bash $INSTALL_DIR/$script"
    done
    
    exit 1
fi
