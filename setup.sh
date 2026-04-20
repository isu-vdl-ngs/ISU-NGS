#!/usr/bin/env bash

###############################################################################
# Script Name: setup.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: Micromamba environment and Kraken2 database setup for NGS.
#              This modular script creates/updated Kraken2 database along with
#              creates new micromamba environment automatically based on the
#              configuration provided. The script is highly customazable.
#
# Usage:       bash setup.sh [OPTIONS]
#              see output of bash setup.sh --help for more
#
# Requirements:
#   - Bash 4+
#   - Conda/mamba environment with: fastqc, multiqc, trimmomatic, kraken2, krona, spades, etc.
#   - config.sh, common.sh
#
# Version:     1.0.0
###############################################################################

# Function to handle Ctrl+C
handle_interrupt() {
    echo ""
    log "Warning" "Setup interrupted by user (Ctrl+C). Exiting."
    exit 130
}

# Set the trap for SIGINT (Ctrl+C)
trap handle_interrupt INT

# Define project root as current working directory
PROJECT_ROOT="$(pwd)"

# Path to config.sh
CONFIG_SH_PATH="$PROJECT_ROOT/config/config.sh"

if [[ -f "$CONFIG_SH_PATH" ]]; then
    source "$CONFIG_SH_PATH"
else
    echo "Error: config.sh not found at $CONFIG_SH_PATH"
    echo "Please check if you have the latest version of the scripts"
    exit 1
fi

# Resolve absolute path to common.sh using relative path from config
COMMON_SH_PATH="$PROJECT_ROOT/$COMMON_SCRIPT"

if [[ -f "$COMMON_SH_PATH" ]]; then
    source "$COMMON_SH_PATH"
else
    echo "Error: common.sh not found at $COMMON_SH_PATH"
    exit 1
fi

# Update/Add PROJECT_ROOT if present in config
update_config_variable "PROJECT_ROOT" "$PROJECT_ROOT" "$CONFIG_SH_PATH"
log "Info" "Updated PROJECT_ROOT in config.sh"

# Setup folders for data analysis
mkdir -p $PROJECT_ROOT/$DATA_DIR
mkdir -p $PROJECT_ROOT/$ANALYSIS_DIR
mkdir -p $PROJECT_ROOT/$RESULTS_DIR
mkdir -p $PROJECT_ROOT/$SETUP_LOGS_DIR
mkdir -p $PROJECT_ROOT/$RUN_LOGS_DIR

LOG_FILE="$PROJECT_ROOT/$SETUP_LOGS_DIR/setup_$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log "Info" "Using project root: $PROJECT_ROOT"
log "Info" "Loaded config from: $CONFIG_SH_PATH"
log "Info" "Sourced common utilities from: $COMMON_SH_PATH"

#Test Micromamba availability
if ! command -v micromamba >/dev/null 2>&1; then
    msg=$(cat << 'EOF'

micromamba is not installed.

To continue, run:

    bash <(curl -Ls https://micro.mamba.pm/install.sh)


Then restart your terminal (recommended),
Or, reload your shell config:

    source ~/.bashrc   (bash)
    source ~/.zshrc    (zsh)

Then re-run this script.
EOF
)
    log "ERROR" "${msg}"
    exit 1
fi

# Default flags
DO_SETUP_ENV=false
DO_SETUP_DB=false
SHOW_HELP=false
SHOW_DETAILS=false

show_help() {
    echo "Usage: bash $0 [--env] [--db] [--all] [--help]"
    echo "  --env       Setup/Update environment only"
    echo "  --db        Setup/Update database only"
    echo "  --all       Setup/Update both environment and database (default if no args)"
    echo "  --show      Show both environment and database details (if set)"
    echo "  -h, --help  Show this help message"
}

setup_env() (
    trap 'log "Error" "Setup cancelled by user."; exit 1' INT
    log "Run" "Starting environment setup"

    # Ask user where to install the environment
    read -p "Install environment in current folder ($(pwd))? (y/n): " answer

    case "$answer" in
        [Yy]* )
            INSTALL_PATH="$(pwd)"
        ;;
        [Nn]* )
            read -p "Provide full path or folder name to install inside: " user_path
            if [[ "$user_path" = /* ]]; then
                INSTALL_PATH="$user_path"
            else
                INSTALL_PATH="$(pwd)/$user_path"
            fi
        ;;
        * )
            log "Error" "Please answer y or n."
            exit 1
        ;;
    esac

    log "Info" "Environment will be installed inside: $INSTALL_PATH"

    # Update/Add ENVIRONMENT_ROOT if present in config
    update_config_variable "ENVIRONMENT_ROOT" "$INSTALL_PATH" "$CONFIG_SH_PATH"
    log "Info" "Updated ENVIRONMENT_ROOT in config.sh"

    # Call the envs.sh script
    ENV_SCRIPT_PATH="$PROJECT_ROOT/$ENV_SETUP_SCRIPT"
    if [[ -f "$ENV_SCRIPT_PATH" ]]; then
        log "Info" "Running environment setup script: $ENV_SCRIPT_PATH"
        bash "$ENV_SCRIPT_PATH" "$CONFIG_SH_PATH"
    else
        log "Error" "Environment setup script not found at $ENV_SCRIPT_PATH"
        exit 1
    fi
)

setup_db() (
    trap 'log "Error" "Setup cancelled by user."; exit 1' INT
    log "Run" "Setting up kraken2 database"
    # Run db setup script here
    KRAKEN2DB_SCRIPT_PATH="$PROJECT_ROOT/$KRAKEN2DB_SETUP_SCRIPT"
    if [[ -f "$KRAKEN2DB_SCRIPT_PATH" ]]; then
        log "Info" "Running Kraken2DB setup script: $KRAKEN2DB_SCRIPT_PATH"
        bash "$KRAKEN2DB_SCRIPT_PATH" "$CONFIG_SH_PATH"
    else
        log "Error" "Kraken2DB setup script not found at $KRAKEN2DB_SCRIPT_PATH"
        exit 1
    fi
)

show_details() {
    echo "Environment setup path: ${ENVIRONMENT_PATH:-Not set}"
    echo "Project root: ${PROJECT_ROOT:-Not set}"

    echo ""

    if [[ -d "$PROJECT_ROOT/$KRAKEN2_DB_PATH" ]]; then
        if [[ $(ls -A "$PROJECT_ROOT/$KRAKEN2_DB_PATH") ]]; then
            echo "Kraken2 DB directory contents:"
            ls -l "$PROJECT_ROOT/$KRAKEN2_DB_PATH"
        else
            echo "Kraken2 DB directory exists but is empty."
        fi
    else
        echo "Kraken2 DB directory does not exist."
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            DO_SETUP_ENV=true
            shift
            ;;
        --db)
            DO_SETUP_DB=true
            shift
            ;;
        --all)
            DO_SETUP_ENV=true
            DO_SETUP_DB=true
            shift
            ;;
        --show)
            SHOW_DETAILS=true
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            log "Error" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# If no args given, default to --all
if ! $DO_SETUP_ENV && ! $DO_SETUP_DB && ! $SHOW_HELP; then
    DO_SETUP_ENV=true
    DO_SETUP_DB=true
fi

if $SHOW_DETAILS; then
    show_details
    exit 0
fi

if $SHOW_HELP; then
    show_help
    exit 0
fi

if $DO_SETUP_ENV; then
    setup_env
fi

if $DO_SETUP_DB; then
    setup_db
fi
