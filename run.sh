#!/usr/bin/env bash

###############################################################################
# Script Name: run.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: NGS Illumina paired-end reads assembly - Main file.
#
#              WORKFLOW:
#                1. Preprocess (always runs first): checks/normalizes the
#                   data folder, and creates samples.csv and taxonomy_template.csv.
#                   Workflow stops here for you to edit the taxonomy file.
#                2. Phase 1 (no --taxonomy given): trim, FastQC/MultiQC,
#                   classification (Kraken2/etc.) + Krona.
#                3. Phase 2 (--taxonomy given): extraction + assembly,
#                   processing only taxonomy rows whose `status` column
#                   is "process" (see taxonomy_template.csv).
#
# Usage:       bash run.sh [OPTIONS]
#              see output of bash run.sh --help for more
#
# Requirements:
#   - Bash 4+
#   - Conda/mamba environment with: fastqc, multiqc, trimmomatic, kraken2, krona, spades, etc.
#   - config.sh, common.sh, lib/stages.sh
#
# Version:     3.0.0
###############################################################################

handle_interrupt() {
    echo ""
    log "Warning" "Run interrupted by user (Ctrl+C). Exiting."
    exit 130
}
trap handle_interrupt INT

print_usage() {
    echo "Usage: bash run.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --data <folder>         Relative path to folder inside data/ (required)"
    echo "  --taxonomy <file>       Path to taxonomy_template.csv (runs extraction/assembly phase)"
    echo "  --preprocess            Only check data and create/update the taxonomy file, then stop"
    echo "  --no-preprocess         Override DO_PREPROCESS_ONLY=true from a --params file"
    echo "  --params <file>         Load flags from a params file (see config/run.params.example)."
    echo "                          Explicit flags on the command line override values from this file."
    echo "  --no-trim               Skip trimming step"
    echo "  --kraken-from-trimmed   Use trimmed reads for classification & Krona"
    echo "  --extract-from-trimmed  Use trimmed reads for de novo assembly"
    echo "  --no-kraken             Skip classification/Krona"
    echo "  --no-fastqc             Skip FastQC/MultiQC"
    echo "  --no-extract            Skip extraction & assembly"
    echo "  --help                  Show help message"
}

parse_args() {
    # Defaults - a --params file (if given) can override these; an
    # explicit command-line flag always overrides the params file.
    DO_FASTQC=true
    DO_TRIM=true
    DO_KRAKEN=true
    DO_EXTRACTION=true
    DO_PREPROCESS_ONLY=false
    KRAKEN_FROM_TRIMMED=false
    EXTRACT_FROM_TRIMMED=false
    TAXONOMY_FILE=""
    DATA_FOLDER=""
    SHOW_HELP=false

    # find --params (if given) and update variables sourced using the set values from file.
    local args=("$@")
    local i
    for ((i = 0; i < ${#args[@]}; i++)); do
        if [[ "${args[$i]}" == "--params" ]]; then
            local params_file="${args[$((i + 1))]:-}"
            if [[ -z "$params_file" ]]; then
                log "ERROR" "--params requires a file argument"
                exit 1
            fi
            if [[ ! -f "$params_file" ]]; then
                log "ERROR" "Params file not found: $params_file"
                exit 1
            fi
            log "Info" "Loading run parameters from $params_file"
            source "$params_file"
            break
        fi
    done

    # command line argument parsing (overrides params file)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --params)
                # Already processed loaded above.
                shift
                ;;
            --data)
                DATA_FOLDER="${2:-}"
                if [[ -z "$DATA_FOLDER" ]]; then
                    log "ERROR" "--data requires a folder argument"
                    exit 1
                fi
                shift
                ;;
            --taxonomy)
                TAXONOMY_FILE="${2:-}"
                if [[ -z "$TAXONOMY_FILE" ]]; then
                    log "ERROR" "--taxonomy requires a file argument"
                    exit 1
                fi
                shift
                ;;
            --preprocess) DO_PREPROCESS_ONLY=true ;;
            --no-preprocess) DO_PREPROCESS_ONLY=false ;;
            --no-trim) DO_TRIM=false ;;
            --kraken-from-trimmed) KRAKEN_FROM_TRIMMED=true ;;
            --extract-from-trimmed) EXTRACT_FROM_TRIMMED=true ;;
            --no-kraken) DO_KRAKEN=false ;;
            --no-fastqc) DO_FASTQC=false ;;
            --no-extract) DO_EXTRACTION=false ;;
            --help) SHOW_HELP=true ;;
            *) log "Error" "Unknown argument: $1"; print_usage; exit 1 ;;
        esac
        shift
    done

    if $SHOW_HELP; then
        print_usage
        exit 0
    fi

    if [[ -z "$DATA_FOLDER" ]]; then
        log "ERROR" "--data <folder> is required (directly, or via --params)."
        exit 1
    fi
}

# Normalize *_1.fastq/_2.fastq to *_R1/_R2.fastq.gz, then group each sample's
# R1/R2 files into their own subfolder under SAMPLE_DATA_PATH.
normalize_and_group_samples() {
    local SAMPLE_DATA_PATH="$1"

    local f
    for f in "$SAMPLE_DATA_PATH"/*_1.fastq; do
        [[ -e "$f" ]] || continue
        log "Info" "Normalizing the raw data"
        local base="${f%_1.fastq}"
        mv "${base}_1.fastq" "${base}_R1.fastq"
        mv "${base}_2.fastq" "${base}_R2.fastq"
        gzip "${base}_R1.fastq"
        gzip "${base}_R2.fastq"
    done

    local r1_file
    for r1_file in "$SAMPLE_DATA_PATH"/*_R1*.fastq.gz; do
        [[ -e "$r1_file" ]] || continue

        local filename sample_name sample_dir
        filename=$(basename "$r1_file")
        sample_name="${filename%%_R1*}"
        sample_dir="$SAMPLE_DATA_PATH/$sample_name"
        mkdir -p "$sample_dir"

        mv "$SAMPLE_DATA_PATH/${sample_name}_R1"*.fastq.gz "$sample_dir/" 2>/dev/null || true
        mv "$SAMPLE_DATA_PATH/${sample_name}_R2"*.fastq.gz "$sample_dir/" 2>/dev/null || true
    done
}

# Preprocess: create/update samples.csv and taxonomy_template.csv from the data folder
# Note: new samples are added; existing rows/edits are never touched.
generate_or_update_manifest() {
    local SAMPLE_DATA_PATH="$1"
    local SAMPLES_CSV="$2"
    local TAXONOMY_CSV="$3"

    local discovered=()
    local d
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        discovered+=("$d")
    done < <(find "$SAMPLE_DATA_PATH" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

    if [[ ${#discovered[@]} -eq 0 ]]; then
        log "Warning" "No sample subfolders found under $SAMPLE_DATA_PATH"
    fi

    # samples.csv
    if [[ ! -f "$SAMPLES_CSV" ]]; then
        log "Info" "Creating samples.csv at $SAMPLES_CSV"
        echo "sample_id" > "$SAMPLES_CSV"
        local s
        for s in "${discovered[@]}"; do
            echo "$s" >> "$SAMPLES_CSV"
        done
    else
        log "Info" "samples.csv already exists - checking for newly added samples"
        local -A have=()
        local s
        while IFS= read -r s; do
            [[ -z "$s" ]] && continue
            have["$s"]=1
        done < <(tail -n +2 "$SAMPLES_CSV")

        for s in "${discovered[@]}"; do
            if [[ -z "${have[$s]:-}" ]]; then
                log "Info" "New sample discovered: $s - adding to samples.csv"
                echo "$s" >> "$SAMPLES_CSV"
            fi
        done

        for s in "${!have[@]}"; do
            if [[ ! -d "$SAMPLE_DATA_PATH/$s" ]]; then
                log "Warning" "Sample '$s' is listed in samples.csv but not found under $SAMPLE_DATA_PATH"
            fi
        done
    fi

    # taxonomy_template.csv
    migrate_taxonomy_csv_if_needed "$TAXONOMY_CSV"

    if [[ ! -f "$TAXONOMY_CSV" ]]; then
        log "Info" "Creating taxonomy_template.csv at $TAXONOMY_CSV"
        echo "sample_id,taxid,name,status" > "$TAXONOMY_CSV"
        local s
        for s in "${discovered[@]}"; do
            echo "${s},,,skip" >> "$TAXONOMY_CSV"
        done
    else
        log "Info" "taxonomy_template.csv already exists - preserving existing rows/edits, adding any new samples"
        local -A have_tax=()
        local s
        while IFS=',' read -r s _taxid _name _status; do
            [[ -z "$s" ]] && continue
            have_tax["$s"]=1
        done < <(tail -n +2 "$TAXONOMY_CSV")

        for s in "${discovered[@]}"; do
            if [[ -z "${have_tax[$s]:-}" ]]; then
                log "Info" "New sample discovered: $s - adding a 'skip' row to taxonomy_template.csv"
                echo "${s},,,skip" >> "$TAXONOMY_CSV"
            fi
        done
    fi
}

# Symlink each sample's raw R1/R2 into RAW_FASTQ_DIR.
create_raw_input_symlinks() {
    local SAMPLES_CSV="$1"
    local SAMPLE_DATA_PATH="$2"
    local RAW_FASTQ_DIR="$3"

    mkdir -p "$RAW_FASTQ_DIR"
    log "Info" "Detecting FASTQ file pairs for raw FastQC input..."

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

        log "Info" "Creating symlinks for sample $sample"
        ln -sf "$R1_PATH" "$RAW_FASTQ_DIR/$(basename "$R1_PATH")"
        ln -sf "$R2_PATH" "$RAW_FASTQ_DIR/$(basename "$R2_PATH")"
    done < <(tail -n +2 "$SAMPLES_CSV")
}

main() {
    PROJECT_ROOT="$(pwd)"

    CONFIG_SH_PATH="$PROJECT_ROOT/config/config.sh"
    if [[ -f "$CONFIG_SH_PATH" ]]; then
        source "$CONFIG_SH_PATH"
    else
        echo "Error: config.sh not found at $CONFIG_SH_PATH"
        echo "Please check if you have the latest version of the scripts"
        exit 1
    fi

    COMMON_SH_PATH="$PROJECT_ROOT/$COMMON_SCRIPT"
    if [[ -f "$COMMON_SH_PATH" ]]; then
        source "$COMMON_SH_PATH"
    else
        echo "Error: common.sh not found at $COMMON_SH_PATH"
        exit 1
    fi

    STAGES_SH_PATH="$PROJECT_ROOT/$STAGES_SCRIPT"
    if [[ -f "$STAGES_SH_PATH" ]]; then
        source "$STAGES_SH_PATH"
    else
        log "ERROR" "stages.sh not found at $STAGES_SH_PATH"
        exit 1
    fi

    mkdir -p "$PROJECT_ROOT/$SETUP_LOGS_DIR"
    LOG_FILE="$PROJECT_ROOT/$SETUP_LOGS_DIR/run_$(date +%F_%H-%M-%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1

    parse_args "$@"

    SAMPLE_DATA_PATH="$PROJECT_ROOT/$DATA_DIR/$DATA_FOLDER"
    if [[ ! -d "$SAMPLE_DATA_PATH" ]]; then
        log "ERROR" "Provided data path not found: $SAMPLE_DATA_PATH"
        exit 1
    fi

    SAMPLE_ANALYSIS_PATH="$PROJECT_ROOT/$ANALYSIS_DIR/$DATA_FOLDER"
    SAMPLE_RESULTS_PATH="$PROJECT_ROOT/$RESULTS_DIR/$DATA_FOLDER"
    mkdir -p "$SAMPLE_ANALYSIS_PATH" "$SAMPLE_RESULTS_PATH"

    SAMPLES_CSV="$SAMPLE_ANALYSIS_PATH/samples.csv"
    TAXONOMY_CSV="$SAMPLE_ANALYSIS_PATH/taxonomy_template.csv"
    RAW_FASTQ_DIR="$SAMPLE_ANALYSIS_PATH/inputs"
    TRIM_FASTQ_DIR="$SAMPLE_ANALYSIS_PATH/trimmed"

    # Preprocess
    normalize_and_group_samples "$SAMPLE_DATA_PATH"
    generate_or_update_manifest "$SAMPLE_DATA_PATH" "$SAMPLES_CSV" "$TAXONOMY_CSV"

    if $DO_PREPROCESS_ONLY; then
        log "Success" "Preprocessing complete for data folder: $DATA_FOLDER"
        log "Info" "Review/edit $TAXONOMY_CSV : fill in taxid + name for samples you know, and set status to 'process' for rows you want extracted later."
        log "Info" "Then run one of:"
        log "CMD" "bash run.sh --data $DATA_FOLDER                                   # trim / QC / classify"
        log "CMD" "bash run.sh --data $DATA_FOLDER --taxonomy $TAXONOMY_CSV          # extract + assemble (after classification has run)"
        exit 0
    fi

    if [[ -z "${ENVIRONMENT_PATH:-}" ]]; then
        log "ERROR" "ENVIRONMENT_PATH is not set. Run 'bash setup.sh --env' first."
        exit 1
    fi
    if [[ -z "${ENV_ACTIVATION_FILE:-}" ]]; then
        log "ERROR" "ENV_ACTIVATION_FILE is not set. Run 'bash setup.sh --env' first."
        exit 1
    fi

    # Activate the environment before running any pipeline tool runs
    activate_env_from_file "$ENV_ACTIVATION_FILE"

    if [[ -z "$TAXONOMY_FILE" ]]; then
        # Phase 1: trim, QC, classify
        if $DO_TRIM; then
            if ! ( run_trim_stage "$SAMPLES_CSV" "$SAMPLE_DATA_PATH" "$TRIM_FASTQ_DIR" ); then
                log "Warning" "Trim stage encountered errors; continuing with remaining stages"
            fi
        fi

        if $DO_FASTQC; then
            create_raw_input_symlinks "$SAMPLES_CSV" "$SAMPLE_DATA_PATH" "$RAW_FASTQ_DIR"

            if ! ( run_fastqc_stage "$RAW_FASTQ_DIR" "$SAMPLE_ANALYSIS_PATH" "before_trim" "$SAMPLE_RESULTS_PATH" ); then
                log "Warning" "FastQC (before_trim) encountered errors; continuing"
            fi

            if [[ ! -d "$TRIM_FASTQ_DIR" ]]; then
                log "Error" "No trimmed files found. Possibly you forgot/skipped trimming originally. Please run:"
                log "CMD" "bash run.sh --data $DATA_FOLDER --no-kraken --no-fastqc --no-extract"
            else
                if ! ( run_fastqc_stage "$TRIM_FASTQ_DIR" "$SAMPLE_ANALYSIS_PATH" "after_trim" "$SAMPLE_RESULTS_PATH" ); then
                    log "Warning" "FastQC (after_trim) encountered errors; continuing"
                fi
            fi

            find "$RAW_FASTQ_DIR" -type l -exec rm {} +
        fi

        if $DO_KRAKEN; then
            local kraken_reads_dir="$SAMPLE_DATA_PATH"
            if $KRAKEN_FROM_TRIMMED; then
                if [[ ! -d "$TRIM_FASTQ_DIR" ]]; then
                    log "Error" "No trimmed files found. Possibly you forgot/skipped trimming originally. Please run:"
                    log "CMD" "bash run.sh --data $DATA_FOLDER --no-kraken --no-fastqc --no-extract"
                else
                    kraken_reads_dir="$TRIM_FASTQ_DIR"
                fi
            fi
            if ! ( run_classification_stage "$SAMPLES_CSV" "$kraken_reads_dir" "$SAMPLE_ANALYSIS_PATH" "$DATA_FOLDER" "$SAMPLE_RESULTS_PATH" ); then
                log "Warning" "Classification stage encountered errors; continuing"
            fi
        fi

    else
        # Phase 2: extract + assemble (only taxonomy rows marked "process")
        log "Info" "Taxonomy file provided: $TAXONOMY_FILE"

        if [[ ! -d "$SAMPLE_ANALYSIS_PATH/kraken2" ]]; then
            log "Error" "No classification output found. Possibly you forgot/skipped classification originally."
            log "Info" "Command using raw data:"
            log "CMD" "bash run.sh --data $DATA_FOLDER --no-trim --no-fastqc --no-extract"
            log "Info" "Command using trimmed data:"
            log "CMD" "bash run.sh --data $DATA_FOLDER --no-trim --no-fastqc --no-extract --kraken-from-trimmed"
            exit 1
        fi

        local extract_reads_dir="$SAMPLE_DATA_PATH"
        if $EXTRACT_FROM_TRIMMED; then
            if [[ ! -d "$TRIM_FASTQ_DIR" ]]; then
                log "Error" "No trimmed files found. Possibly you forgot/skipped trimming originally. Please run:"
                log "CMD" "bash run.sh --data $DATA_FOLDER --no-kraken --no-fastqc --no-extract"
                exit 1
            fi
            extract_reads_dir="$TRIM_FASTQ_DIR"
        fi

        if $DO_EXTRACTION; then
            if ! ( run_extraction_stage "$TAXONOMY_FILE" "$extract_reads_dir" "$SAMPLE_ANALYSIS_PATH" "$SAMPLE_RESULTS_PATH" ); then
                log "Warning" "Extraction stage encountered errors"
            fi
        fi
    fi

    log "Success" "run.sh completed for data folder: $DATA_FOLDER"
}

main "$@"
