#!/usr/bin/env bash

###############################################################################
# Script Name: kraken2DB.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: Kraken2 database setup for NGS.
#              This script creates/updated Kraken2 database at user defined
#              location and based on the URL for prebuilt Kraken2 database e.g.,
#              standard, viral, etc.
#              URL: https://benlangmead.github.io/aws-indexes/k2
#
#
# Requirements:
#   - Bash 4+
#   - config.sh, common.sh
#
# Version:     1.0.0
###############################################################################

# Read the following micromamba release for directions on its installation
# https://github.com/mamba-org/micromamba-releases

# Check if config file path is passed
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/config.sh"
    exit 1
fi

CONFIG_SH_PATH="$1"

# Source the config file to get variables
if [[ -f "$CONFIG_SH_PATH" ]]; then
    source "$CONFIG_SH_PATH"
else
    echo "Error: Config file not found at $CONFIG_SH_PATH"
    exit 1
fi

if [[ -f "$COMMON_SCRIPT" ]]; then
    source "$COMMON_SCRIPT"
else
    echo "Error: common.sh not found at $COMMON_SCRIPT"
    exit 1
fi

# Using prebuilt kraken2 database from the following list. Update URL to download new version
# https://benlangmead.github.io/aws-indexes/k2


# List of required variable names (as strings)
REQUIRED_VARS=(
    PROJECT_ROOT
    KRAKEN2_DB_URL
    KRAKEN2_DB_PATH
)

# Loop through and check if each is defined and non-empty
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        Log "ERROR" "$var is not set in config file"
        exit 1
    fi
done

KRAKEN2_DB_DIR=$PROJECT_ROOT/$KRAKEN2_DB_PATH

log "INFO" "Checking Kraken2 database directory"

if [[ -d "$KRAKEN2_DB_DIR" ]]; then
    if [[ -z "$(ls -A "$KRAKEN2_DB_DIR")" ]]; then
        # Exists and is empty — proceed silently
        log "INFO" "Directory '$KRAKEN2_DB_DIR' exists but is empty. Proceeding with download"
    else
        # Exists and not empty — prompt before deleting
        log "WARNING" "Directory '$KRAKEN2_DB_DIR' exists and is not empty."
        read -p "Delete and re-download the database? [y/N]: " confirm
        confirm="${confirm,,}"  # Convert to lowercase
        if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
            log "CMD" "Deleting directory '$KRAKEN2_DB_DIR'"
            rm -rf "$KRAKEN2_DB_DIR"
        else
            log "INFO" "Aborting database setup."
            exit 1
        fi
    fi
fi

log "Run" "Downloading and extracting Kraken2 database"
mkdir -p "$KRAKEN2_DB_DIR"
wget -O - "$KRAKEN2_DB_URL" | tar -xz -C "$KRAKEN2_DB_DIR"

log "SUCCESS" "Kraken2 database installed at $KRAKEN2_DB_DIR"
