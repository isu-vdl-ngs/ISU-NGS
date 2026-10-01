#!/usr/bin/env bash

###############################################################################
# Script Name: setup/kraken2DB.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: Kraken2 database setup for NGS.
#              This script creates/updated Kraken2 database at user defined
#              location and based on the URL for prebuilt Kraken2 database e.g.,
#              standard, viral, etc.
#              URL: https://benlangmead.github.io/aws-indexes/k2
#
# Requirements:
#   - Bash 4+
#   - config.sh, common.sh
#
# Version:     1.1.0
###############################################################################

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/config.sh"
    exit 1
fi

CONFIG_SH_PATH="$1"

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

# Using prebuilt kraken2 database from the following list. Update URL in
# config file to download a different version:
# https://benlangmead.github.io/aws-indexes/k2

REQUIRED_VARS=(
    PROJECT_ROOT
    KRAKEN2_DB_URL
    KRAKEN2_DB_PATH
)

# check if required variables have value or not
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var+x}" ]]; then
        log "ERROR" "$var is not set in config file"
        exit 1
    fi
done

KRAKEN2_DB_DIR="$PROJECT_ROOT/$KRAKEN2_DB_PATH"

log "INFO" "Checking Kraken2 database directory"

if [[ -d "$KRAKEN2_DB_DIR" ]]; then
    if [[ -z "$(ls -A "$KRAKEN2_DB_DIR")" ]]; then
        log "INFO" "Directory '$KRAKEN2_DB_DIR' exists but is empty. Proceeding with download"
    else
        log "WARNING" "Directory '$KRAKEN2_DB_DIR' exists and is not empty."
        read -r -p "Delete and re-download the database? [y/N]: " confirm
        confirm="${confirm,,}"
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
