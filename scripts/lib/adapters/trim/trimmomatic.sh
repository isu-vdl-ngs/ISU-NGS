#!/usr/bin/env bash
###############################################################################
# Adapter Type: trim
# Adapter Name: trimmomatic
#
# Contract (required by scripts/lib/stages.sh):
#   trim_adapter_trimmomatic <R1_FASTQ> <R2_FASTQ> <SAMPLE_ID> <OUT_DIR>
#
#   On success:
#     $OUT_DIR/${SAMPLE_ID}_R1_trimmed.fastq.gz
#     $OUT_DIR/${SAMPLE_ID}_R2_trimmed.fastq.gz
###############################################################################

trim_adapter_trimmomatic() {
    local R1_FASTQ="$1"
    local R2_FASTQ="$2"
    local SAMPLE_ID="$3"
    local OUT_DIR="$4"

    require_command "trimmomatic" "${ENVIRONMENT_PATH:-}"

    local TRIMMED_R1="$OUT_DIR/${SAMPLE_ID}_R1_trimmed.fastq.gz"
    local TRIMMED_R2="$OUT_DIR/${SAMPLE_ID}_R2_trimmed.fastq.gz"
    local UNPAIRED_R1="$OUT_DIR/${SAMPLE_ID}_FUP.fastq.gz"
    local UNPAIRED_R2="$OUT_DIR/${SAMPLE_ID}_RUP.fastq.gz"

    trimmomatic PE -threads "${THREADS:-4}" -phred33 \
        "$R1_FASTQ" "$R2_FASTQ" \
        "$TRIMMED_R1" "$UNPAIRED_R1" \
        "$TRIMMED_R2" "$UNPAIRED_R2" \
        ILLUMINACLIP:"$PROJECT_ROOT/$TRIM_ADAPTERS_FILE":2:30:10:8:true \
        LEADING:3 TRAILING:3 SLIDINGWINDOW:4:20 MINLEN:36
}
