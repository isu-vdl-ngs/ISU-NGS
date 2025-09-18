#!/usr/bin/env bash

###############################################################################
# Script Name: trim.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: NGS Illumina paired-end reads trimming.
#              This script gets called based on the request of the user to trim
#              raw sample reads from the `run.sh` script.
#
# Requirements:
#   - Bash 4+
#   - Conda/mamba environment with: trimmomatic.
#   - NexteraPE-PE.fa
#   - config.sh, common.sh
#
# Version:     1.0.0
###############################################################################

set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: bash trim.sh <R1.fastq.gz> <R2.fastq.gz> <sample_id> <data_folder> <trim_folder> <config_sh_path>"
  exit 1
fi

R1_FASTQ="$1"
R2_FASTQ="$2"
SAMPLE_ID="$3"
DATA_FOLDER="$4"
TRIM_FOLDER="$5"
CONFIG_SH_PATH="$6"

# Load config and common utils
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

# Activate environment
activate_env_from_file "$ENV_ACTIVATION_FILE"

log "Run" "Running Trimmomatic for sample: $SAMPLE_ID"

# Output directory
OUT_DIR="$TRIM_FOLDER/$SAMPLE_ID"
mkdir -p "$OUT_DIR"

require_command "trimmomatic"

# Output files
TRIMMED_R1="$OUT_DIR/${SAMPLE_ID}_R1_trimmed.fastq.gz"
TRIMMED_R2="$OUT_DIR/${SAMPLE_ID}_R2_trimmed.fastq.gz"
UNPAIRED_R1="$OUT_DIR/${SAMPLE_ID}_FUP.fastq.gz"
UNPAIRED_R2="$OUT_DIR/${SAMPLE_ID}_RUP.fastq.gz"

# Run Trimmomatic PE
trimmomatic PE -threads 8 -phred33 \
  "$R1_FASTQ" "$R2_FASTQ" \
  "$TRIMMED_R1" "$UNPAIRED_R1" \
  "$TRIMMED_R2" "$UNPAIRED_R2" \
  ILLUMINACLIP:"$PROJECT_ROOT/$TRIM_ADAPTERS_FILE":2:30:10:8:true \
  LEADING:3 TRAILING:3 SLIDINGWINDOW:4:20 MINLEN:36

log "Info" "Trimmomatic ran for $SAMPLE_ID"

# Output trimmed R1 and R2 for downstream steps
echo "$TRIMMED_R1" "$TRIMMED_R2"

log "Info" "Creating symlinks for sample $SAMPLE_ID trim files"
ln -sf "$TRIMMED_R1" "$TRIM_FOLDER/$(basename "$TRIMMED_R1")"
ln -sf "$TRIMMED_R2" "$TRIM_FOLDER/$(basename "$TRIMMED_R2")"
