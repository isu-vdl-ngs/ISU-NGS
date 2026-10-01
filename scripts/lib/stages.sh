#!/usr/bin/env bash

###############################################################################
# Script Name: scripts/lib/stages.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Description: Stage functions for the NGS Illumina pipeline. This file is
#              always SOURCED (never executed directly) by run.sh, after
#              config.sh and common.sh have already been sourced and the
#              environment has been activated exactly once.
#
# Requirements:
#   - Bash 4+
#   - config.sh, common.sh already sourced by the caller
#
# Version:     1.0.0
###############################################################################

[[ -n "${STAGES_SH_LOADED:-}" ]] && return
STAGES_SH_LOADED=1

# ADAPTER LOADING

# Source every adapter file under $ADAPTERS_DIR/<subdir>/ into the current
# shell. Safe to call repeatedly (re-sourcing the same functions is harmless).
_load_adapters() {
    local subdir="$1"
    local dir="$PROJECT_ROOT/$ADAPTERS_DIR/$subdir"

    if [[ ! -d "$dir" ]]; then
        log "ERROR" "Adapter directory not found: $dir"
        exit 1
    fi

    local f
    for f in "$dir"/*.sh; do
        [[ -e "$f" ]] || continue
        source "$f"
    done
}

# TRIM STAGE: Trim one sample's paired reads via the configured TRIMMER adapter.
# Usage: trim_sample <R1_fastq> <R2_fastq> <sample_id> <trim_folder>
# Returns non-zero if the adapter fails or does not produce expected output.
trim_sample() {
    local R1_FASTQ="$1"
    local R2_FASTQ="$2"
    local SAMPLE_ID="$3"
    local TRIM_FOLDER="$4"

    local OUT_DIR="$TRIM_FOLDER/$SAMPLE_ID"
    mkdir -p "$OUT_DIR"

    _load_adapters "trim"
    local fn="trim_adapter_${TRIMMER}"
    if ! declare -f "$fn" >/dev/null; then
        log "ERROR" "Unknown TRIMMER='$TRIMMER' - no matching function $fn in $ADAPTERS_DIR/trim/"
        exit 1
    fi

    log "Run" "Running trimmer '$TRIMMER' for sample: $SAMPLE_ID"
    if ! "$fn" "$R1_FASTQ" "$R2_FASTQ" "$SAMPLE_ID" "$OUT_DIR"; then
        log "Error" "Trimmer '$TRIMMER' failed for sample $SAMPLE_ID"
        return 1
    fi

    local TRIMMED_R1="$OUT_DIR/${SAMPLE_ID}_R1_trimmed.fastq.gz"
    local TRIMMED_R2="$OUT_DIR/${SAMPLE_ID}_R2_trimmed.fastq.gz"
    if [[ ! -s "$TRIMMED_R1" || ! -s "$TRIMMED_R2" ]]; then
        log "Error" "Adapter '$TRIMMER' did not produce expected output: $TRIMMED_R1 / $TRIMMED_R2"
        return 1
    fi

    log "Info" "Trimming completed for $SAMPLE_ID"
    log "Info" "Creating symlinks for sample $SAMPLE_ID trim files"
    ln -sf "$TRIMMED_R1" "$TRIM_FOLDER/$(basename "$TRIMMED_R1")"
    ln -sf "$TRIMMED_R2" "$TRIM_FOLDER/$(basename "$TRIMMED_R2")"
}

# Run trimming for every sample listed in samples.csv.
# Usage: run_trim_stage <samples_csv> <sample_data_path> <trim_fastq_dir>
run_trim_stage() {
    local SAMPLES_CSV="$1"
    local SAMPLE_DATA_PATH="$2"
    local TRIM_FASTQ_DIR="$3"

    mkdir -p "$TRIM_FASTQ_DIR"

    while read -r sample; do
        [[ -z "$sample" ]] && continue

        local R1_PATH R2_PATH
        if ! R1_PATH=$(get_r1_fastq "$sample" "$SAMPLE_DATA_PATH"); then
            log "Warning" "R1 not found for sample $sample"
            continue
        fi
        if ! R2_PATH=$(get_r2_fastq "$R1_PATH"); then
            log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
            continue
        fi

        log "Info" "Trimming $sample"
        if ! trim_sample "$R1_PATH" "$R2_PATH" "$sample" "$TRIM_FASTQ_DIR"; then
            log "Warning" "Skipping remainder of trim stage for sample $sample due to failure above"
            continue
        fi
    done < <(tail -n +2 "$SAMPLES_CSV")
}

# FASTQC / MULTIQC STAGE: Run FastQC + MultiQC on a directory of fastq.gz files.
# Usage: run_fastqc_stage <input_dir> <analysis_dir> <label> <results_path>
# label names the output subfolders, e.g. "before_trim" / "after_trim"
run_fastqc_stage() {
    local INPUT_DIR="$1"
    local ANALYSIS_DIR="$2"
    local LABEL="$3"
    local RESULTS_PATH="$4"

    require_command "fastqc" "${ENVIRONMENT_PATH:-}"
    require_command "multiqc" "${ENVIRONMENT_PATH:-}"

    shopt -s nullglob
    local fastqs=("$INPUT_DIR"/*.fastq.gz)
    shopt -u nullglob
    if [[ ! -d "$INPUT_DIR" || ${#fastqs[@]} -eq 0 ]]; then
        log "Warning" "No fastq.gz files found in $INPUT_DIR, skipping FastQC/MultiQC ($LABEL)"
        return
    fi

    local FASTQC_DIR="$ANALYSIS_DIR/fastqc_${LABEL}"
    local MULTIQC_DIR="$ANALYSIS_DIR/multiqc_${LABEL}"
    mkdir -p "$FASTQC_DIR" "$MULTIQC_DIR"

    log "Run" "Running FastQC ($LABEL) on $INPUT_DIR"
    if ! fastqc -t "${THREADS:-4}" --quiet -o "$FASTQC_DIR" "${fastqs[@]}"; then
        log "Error" "FastQC ($LABEL) failed"
        return 1
    fi
    log "Info" "FastQC ($LABEL) completed. Output in $FASTQC_DIR"

    log "Run" "Running MultiQC ($LABEL) on $FASTQC_DIR"
    if ! multiqc "$FASTQC_DIR" -o "$MULTIQC_DIR"; then
        log "Error" "MultiQC ($LABEL) failed"
        return 1
    fi

    cp -r "$MULTIQC_DIR" "$RESULTS_PATH"
}

# READS CLASSIFICATION (KRAKEN2/etc.) + KRONA STAGE
# Classify one sample via the configured CLASSIFIER adapter and build its
# individual Krona plot. Usage: classify_sample <sample> <r1> <r2> <analysis_path>
classify_sample() {
    local SAMPLE="$1"
    local R1_PATH="$2"
    local R2_PATH="$3"
    local ANALYSIS_PATH="$4"

    local KDIR="$ANALYSIS_PATH/kraken2"
    mkdir -p "$KDIR"

    _load_adapters "classify"
    local fn="classify_adapter_${CLASSIFIER}"
    if ! declare -f "$fn" >/dev/null; then
        log "ERROR" "Unknown CLASSIFIER='$CLASSIFIER' - no matching function $fn in $ADAPTERS_DIR/classify/"
        exit 1
    fi

    log "Info" "Running classifier '$CLASSIFIER' on $SAMPLE"
    if ! "$fn" "$SAMPLE" "$R1_PATH" "$R2_PATH" "$KDIR"; then
        log "Error" "Classifier '$CLASSIFIER' failed for sample $SAMPLE"
        return 1
    fi

    local KRONA_INPUT="$KDIR/${SAMPLE}_krona_input.txt"
    if [[ ! -s "$KRONA_INPUT" ]]; then
        log "Error" "Adapter '$CLASSIFIER' did not produce expected $KRONA_INPUT"
        return 1
    fi

    require_command "ktImportTaxonomy" "${ENVIRONMENT_PATH:-}"
    log "Info" "Generating Krona plot for $SAMPLE"
    ktImportTaxonomy -o "$KDIR/${SAMPLE}_krona.html" "$KRONA_INPUT"
}

# Run classification for every sample, then build the combined Krona plot.
# Usage: run_classification_stage <samples_csv> <reads_dir> <analysis_path> <data_folder> <results_path>
#   reads_dir is either the raw sample-data path or the trimmed-reads dir,
#   depending on whether --kraken-from-trimmed was passed.
run_classification_stage() {
    local SAMPLES_CSV="$1"
    local READS_DIR="$2"
    local ANALYSIS_PATH="$3"
    local DATA_FOLDER="$4"
    local RESULTS_PATH="$5"

    local processed_samples=()

    while read -r sample; do
        [[ -z "$sample" ]] && continue

        local R1_PATH R2_PATH
        if ! R1_PATH=$(get_r1_fastq "$sample" "$READS_DIR"); then
            log "Warning" "R1 not found for sample $sample in $READS_DIR"
            continue
        fi
        if ! R2_PATH=$(get_r2_fastq "$R1_PATH"); then
            log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
            continue
        fi

        if ! classify_sample "$sample" "$R1_PATH" "$R2_PATH" "$ANALYSIS_PATH"; then
            log "Warning" "Excluding $sample from combined Krona plot due to failure above"
            continue
        fi

        processed_samples+=("$sample")
    done < <(tail -n +2 "$SAMPLES_CSV")

    if [[ ${#processed_samples[@]} -eq 0 ]]; then
        log "Warning" "No samples were classified; skipping combined Krona plot"
        return
    fi

    local combined="$ANALYSIS_PATH/kraken2/${DATA_FOLDER}_all_combined.html"
    local inputs=()
    local sample
    for sample in "${processed_samples[@]}"; do
        inputs+=("$ANALYSIS_PATH/kraken2/${sample}_krona_input.txt")
    done

    require_command "ktImportTaxonomy" "${ENVIRONMENT_PATH:-}"
    log "Info" "Generating combined Krona plot for the project"
    ktImportTaxonomy -o "$combined" "${inputs[@]}"

    cp "$combined" "$RESULTS_PATH"
}

# EXTRACTION + ASSEMBLY STAGE
# Extract reads for one sample/taxon (via the CLASSIFIER's paired extract
# adapter) and assemble them (via the ASSEMBLER adapter).
# Usage: run_extraction_sample <sample> <taxid> <name> <r1_path> <r2_path> <analysis_path> <results_path>
run_extraction_sample() {
    local SAMPLE="$1"
    local TAXID="$2"
    local NAME="$3"
    local R1_PATH="$4"
    local R2_PATH="$5"
    local ANALYSIS_PATH="$6"
    local RESULTS_PATH="$7"

    local KDIR="$ANALYSIS_PATH/kraken2"
    local EXTRACT_DIR="$ANALYSIS_PATH/extraction/$SAMPLE/$NAME"
    mkdir -p "$EXTRACT_DIR"

    local OUT_PREFIX="$EXTRACT_DIR/${SAMPLE}_${NAME}_taxid${TAXID}"
    local EXT_R1="${OUT_PREFIX}_R1.fastq.gz"
    local EXT_R2="${OUT_PREFIX}_R2.fastq.gz"

    _load_adapters "classify"
    local extract_fn="extract_adapter_${CLASSIFIER}"
    if ! declare -f "$extract_fn" >/dev/null; then
        log "ERROR" "Unknown CLASSIFIER='$CLASSIFIER' - no matching function $extract_fn in $ADAPTERS_DIR/classify/"
        exit 1
    fi

    log "Info" "Extracting reads for $SAMPLE / $NAME (taxid $TAXID)"
    if ! "$extract_fn" "$SAMPLE" "$TAXID" "$R1_PATH" "$R2_PATH" "$KDIR" "$EXT_R1" "$EXT_R2"; then
        log "Error" "Extraction failed for $SAMPLE / $NAME"
        return 1
    fi

    if [[ ! -s "$EXT_R1" || ! -s "$EXT_R2" ]]; then
        log "Warning" "Skipping assembly: extracted reads for $SAMPLE ($NAME) are empty or missing"
        return 0
    fi

    _load_adapters "assemble"
    local assemble_fn="assemble_adapter_${ASSEMBLER}"
    if ! declare -f "$assemble_fn" >/dev/null; then
        log "ERROR" "Unknown ASSEMBLER='$ASSEMBLER' - no matching function $assemble_fn in $ADAPTERS_DIR/assemble/"
        exit 1
    fi

    local ASSEMBLY_DIR="$EXTRACT_DIR/assembly"
    log "Info" "Running assembler '$ASSEMBLER' for $SAMPLE / $NAME"
    if ! "$assemble_fn" "$EXT_R1" "$EXT_R2" "$ASSEMBLY_DIR" "${THREADS:-4}" "${ASSEMBLY_MEM_GB:-16}"; then
        log "Error" "Assembler '$ASSEMBLER' failed for $SAMPLE / $NAME"
        return 1
    fi

    local CONTIGS="$ASSEMBLY_DIR/contigs.fasta"
    if [[ ! -s "$CONTIGS" ]]; then
        log "Warning" "Assembler '$ASSEMBLER' did not produce contigs.fasta for $SAMPLE / $NAME"
        return 0
    fi

    local RES_DIR="$RESULTS_PATH/$SAMPLE/$NAME"
    mkdir -p "$RES_DIR"
    cp "$CONTIGS" "$RES_DIR/${SAMPLE}_${NAME}.fasta"

    local STATS_DIR="$RES_DIR/stats"
    mkdir -p "$STATS_DIR"
    require_command "seqkit" "${ENVIRONMENT_PATH:-}"
    seqkit stats "$RES_DIR/${SAMPLE}_${NAME}.fasta" > "$STATS_DIR/seqkit_stats.txt"
}

# Run extraction + assembly for every "process" row in the taxonomy file.
# Usage: run_extraction_stage <taxonomy_file> <reads_dir> <analysis_path> <results_path>
#   reads_dir is either the raw sample-data path or the trimmed-reads dir,
#   depending on whether --extract-from-trimmed was passed.
#
# Only rows whose `status` column equals "process" (case-insensitive) are
# extracted/assembled. Rows marked "skip" are passed
run_extraction_stage() {
    local TAXONOMY_FILE="$1"
    local READS_DIR="$2"
    local ANALYSIS_PATH="$3"
    local RESULTS_PATH="$4"

    if [[ ! -d "$ANALYSIS_PATH/kraken2" ]]; then
        log "Error" "No classification output found. Run the classification stage first for this project."
        return 1
    fi

    migrate_taxonomy_csv_if_needed "$TAXONOMY_FILE"

    while IFS=',' read -r sample taxid name status; do
        [[ -z "$sample" ]] && continue

        local status_norm
        status_norm="$(echo "${status:-}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"

        if [[ "$status_norm" != "process" ]]; then
            log "Info" "Skipping $sample${name:+ / $name} (status='${status_norm:-<empty>}')"
            continue
        fi

        if [[ -z "$taxid" || -z "$name" ]]; then
            log "Warning" "Row for sample $sample is marked 'process' but taxid/name is blank - skipping"
            continue
        fi

        local R1_PATH R2_PATH
        if ! R1_PATH=$(get_r1_fastq "$sample" "$READS_DIR"); then
            log "Warning" "R1 not found for sample $sample in $READS_DIR"
            continue
        fi
        if ! R2_PATH=$(get_r2_fastq "$R1_PATH"); then
            log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
            continue
        fi

        run_extraction_sample "$sample" "$taxid" "$name" "$R1_PATH" "$R2_PATH" "$ANALYSIS_PATH" "$RESULTS_PATH" \
            || log "Warning" "Extraction/assembly failed for $sample / $name, continuing with next entry"
    done < <(tail -n +2 "$TAXONOMY_FILE")
}
