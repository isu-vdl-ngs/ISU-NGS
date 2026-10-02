#!/usr/bin/env bash
###############################################################################
# Adapter Type: classify (and its paired extract)
# Adapter Name: kraken2
#
# Contract - classify (required by scripts/lib/stages.sh):
#   classify_adapter_kraken2 <SAMPLE> <R1_PATH> <R2_PATH> <KDIR>
#
#   On success:
#     $KDIR/${SAMPLE}_report            (kraken-style report, for QC/reference)
#     $KDIR/${SAMPLE}_classify           (native per-read output, consumed
#                                         ONLY by extract_adapter_kraken2 below -
#                                         other classifiers are not expected to
#                                         produce or understand this format)
#     $KDIR/${SAMPLE}_krona_input.txt    (2 columns, tab-separated:
#                                         read_id<TAB>taxid, one row per
#                                         classified read, human reads
#                                         remapped to taxid 0 - this file's
#                                         format IS the standardized contract
#                                         that scripts/lib/stages.sh relies on
#                                         to build Krona plots, regardless of
#                                         which classifier produced it)
#
###############################################################################

classify_adapter_kraken2() {
    local SAMPLE="$1"
    local R1_PATH="$2"
    local R2_PATH="$3"
    local KDIR="$4"

    require_command "kraken2" "${ENVIRONMENT_PATH:-}"

    kraken2 --db "$PROJECT_ROOT/$KRAKEN2_DB_PATH" --threads "${THREADS:-4}" --paired \
        --gzip-compressed "$R1_PATH" "$R2_PATH" \
        --output "$KDIR/${SAMPLE}_classify" \
        --report "$KDIR/${SAMPLE}_report"

    # Extract only classified reads; reassign human reads (taxid 9606) to 0
    awk '$1 == "C" { $3 = ($3 == "9606" ? 0 : $3); print $2 "\t" $3 }' \
        "$KDIR/${SAMPLE}_classify" > "$KDIR/${SAMPLE}_krona_input.txt"
}

extract_adapter_kraken2() {
    local SAMPLE="$1"
    local TAXID="$2"
    local R1_PATH="$3"
    local R2_PATH="$4"
    local KDIR="$5"
    local OUT_R1="$6"
    local OUT_R2="$7"

    local CLASSIFY_FILE="$KDIR/${SAMPLE}_classify"
    local REPORT_FILE="$KDIR/${SAMPLE}_report"
    if [[ ! -s "$CLASSIFY_FILE" ]]; then
        log "ERROR" "Expected Kraken2 classify file not found: $CLASSIFY_FILE (did the classify stage run for this sample?)"
        return 1
    fi

    local EXTRACT_SCRIPT_PATH="$ENVIRONMENT_PATH/$EXTRACT_SCRIPT"
    if [[ ! -f "$EXTRACT_SCRIPT_PATH" ]]; then
        log "ERROR" "KrakenTools extract script not found at $EXTRACT_SCRIPT_PATH - is krakentools installed in this environment? Check EXTRACT_SCRIPT in config.sh and re-run 'bash setup.sh --env' if needed."
        return 1
    fi

    local TMP_R1="${OUT_R1%.gz}"
    local TMP_R2="${OUT_R2%.gz}"

    python3 "$EXTRACT_SCRIPT_PATH" \
        -k "$CLASSIFY_FILE" \
        -s "$R1_PATH" -s2 "$R2_PATH" \
        -o "$TMP_R1" -o2 "$TMP_R2" \
        --taxid "$TAXID" \
        --include-children \
        -r "$REPORT_FILE" \
        --fastq-output

    if [[ ! -s "$TMP_R1" || ! -s "$TMP_R2" ]]; then
        log "ERROR" "extract_kraken_reads.py did not produce expected output: $TMP_R1 / $TMP_R2"
        return 1
    fi

    if ! gzip -f "$TMP_R1"; then
        log "ERROR" "Failed to gzip $TMP_R1"
        return 1
    fi
    if ! gzip -f "$TMP_R2"; then
        log "ERROR" "Failed to gzip $TMP_R2"
        return 1
    fi
}
