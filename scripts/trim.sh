#!/usr/bin/env bash

###############################################################################
# Script Name: scripts/trim.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: Standalone wrapper for trimming a single sample's paired-end
#              reads.
#
# Requirements:
#   - Bash 4+
#   - Conda/mamba environment with the configured trimmer (we are using trimmomatic)
#   - config.sh, common.sh, lib/stages.sh, trim adapter
#
# Version:     2.0.0
###############################################################################

if [[ $# -lt 6 ]]; then
    echo "Usage: bash trim.sh <R1.fastq.gz> <R2.fastq.gz> <sample_id> <data_folder> <trim_folder> <config_sh_path>"
    exit 1
fi

R1_FASTQ="$1"
R2_FASTQ="$2"
SAMPLE_ID="$3"
DATA_FOLDER="$4"
TRIM_FOLDER="$5"
CONFIG_SH_PATH="$6"

if [[ -f "$CONFIG_SH_PATH" ]]; then
    source "$CONFIG_SH_PATH"
else
    echo "Error: Config file not found at $CONFIG_SH_PATH"
    exit 1
fi

if [[ -f "$PROJECT_ROOT/$COMMON_SCRIPT" ]]; then
    source "$PROJECT_ROOT/$COMMON_SCRIPT"
else
    echo "Error: common.sh not found at $PROJECT_ROOT/$COMMON_SCRIPT"
    exit 1
fi

if [[ -f "$PROJECT_ROOT/$STAGES_SCRIPT" ]]; then
    source "$PROJECT_ROOT/$STAGES_SCRIPT"
else
    log "ERROR" "stages.sh not found at $PROJECT_ROOT/$STAGES_SCRIPT"
    exit 1
fi

if [[ -z "${ENVIRONMENT_PATH:-}" || -z "${ENV_ACTIVATION_FILE:-}" ]]; then
    log "ERROR" "Environment not set up. Run 'bash setup.sh --env' first."
    exit 1
fi

# activate environment to perform trimming
activate_env_from_file "$ENV_ACTIVATION_FILE"

mkdir -p "$TRIM_FOLDER"

if ! trim_sample "$R1_FASTQ" "$R2_FASTQ" "$SAMPLE_ID" "$TRIM_FOLDER"; then
    log "ERROR" "Trimming failed for sample $SAMPLE_ID"
    exit 1
fi

# Output trimmed R1/R2 paths for any caller capturing stdout
echo "$TRIM_FOLDER/$SAMPLE_ID/${SAMPLE_ID}_R1_trimmed.fastq.gz" \
     "$TRIM_FOLDER/$SAMPLE_ID/${SAMPLE_ID}_R2_trimmed.fastq.gz"
