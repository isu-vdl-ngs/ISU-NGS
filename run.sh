#!/usr/bin/env bash

###############################################################################
# Script Name: run.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: NGS Illumina paired-end reads assembly.
#              This modular script creates quality report for the sample and
#              performs read trimming, classification (Kraken2),
#              Krona visualization, and extraction + assembly for selected taxa.
#              The script is highly customizable.
#
# Usage:       bash run.sh [OPTIONS]
#              see output of bash run.sh --help for more
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

# Subshell to skip issue with other user defined env variables being unbound
(
    # Define project root as current working directory similar to setup.sh
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

    # Default variables
    DO_FASTQC=true
    DO_TRIM=true
    DO_KRAKEN=true
    DO_KRONA=true
    DO_EXTRACTION=true
    KRAKEN_FROM_TRIMMED=false
    EXTRACT_FROM_TRIMMED=false
    TAXONOMY_FILE=""
    DATA_FOLDER=""
    SHOW_HELP=false

    LOG_FILE="$PROJECT_ROOT/$SETUP_LOGS_DIR/run_$(date +%F_%H-%M-%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1

    # Parse command line arguments
    print_usage() {
        echo "Usage: bash run.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --data <folder>         Relative path to folder inside data/"
        echo "  --taxonomy <file>       Path to taxonomy_template.csv"
        echo "  --no-trim               Skip trimming step"
        echo "  --kraken-from-trimmed   Use trimmed reads for Kraken2 & Krona"
        echo "  --extract-from-trimmed  Use trimmed reads for de novo assembly"
        echo "  --no-kraken             Skip Kraken2/Krona"
        echo "  --no-fastqc             Skip FastQC/MultiQC"
        echo "  --no-extract            Skip extraction & assembly"
        echo "  --help                  Show help message"
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data) DATA_FOLDER="$2"; shift ;;
            --taxonomy) TAXONOMY_FILE="$2"; shift ;;
            --no-trim) DO_TRIM=false ;;
            --kraken-from-trimmed) KRAKEN_FROM_TRIMMED=true ;;
            --no-kraken) DO_KRAKEN=false; DO_KRONA=false ;;
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
        log "ERROR" "--data <folder> is required."
        exit 1
    fi

    # Activate environment
    activate_env_from_file "$ENV_ACTIVATION_FILE"

    SAMPLE_DATA_PATH="$PROJECT_ROOT/$DATA_DIR/$DATA_FOLDER"
    if [[ ! -d "$SAMPLE_DATA_PATH" ]]; then
        log "ERROR" "Provided data path not found: $SAMPLE_DATA_PATH"
        exit 1
    fi

    SAMPLE_ANALYSIS_PATH="$PROJECT_ROOT/$ANALYSIS_DIR/$DATA_FOLDER"
    SAMPLE_RESULTS_PATH="$PROJECT_ROOT/$RESULTS_DIR/$DATA_FOLDER"
    mkdir -p "$SAMPLE_ANALYSIS_PATH" "$SAMPLE_RESULTS_PATH"

    # Create samples.csv and taxonomy_template.csv if doesn't exist
    SAMPLES_CSV="$SAMPLE_ANALYSIS_PATH/samples.csv"
    TAXONOMY_CSV="$SAMPLE_ANALYSIS_PATH/taxonomy_template.csv"

    # Create folders corresponding to samples using text before _R1/_R2
    for r1_file in "$SAMPLE_DATA_PATH"/*_R1*.fastq.gz; do
        # Skip if no files matched
        [[ -e "$r1_file" ]] || continue

        # Get filename without path
        filename=$(basename "$r1_file")
        # Extract sample name (everything before _R1)
        sample_name="${filename%%_R1*}"

        # Create sample specific folder
        sample_dir="$SAMPLE_DATA_PATH/$sample_name"
        mkdir -p "$sample_dir"

        # Move R1 and R2 files into the folder
        mv "$SAMPLE_DATA_PATH/${sample_name}_R1"*.fastq.gz "$sample_dir/" 2>/dev/null
        mv "$SAMPLE_DATA_PATH/${sample_name}_R2"*.fastq.gz "$sample_dir/" 2>/dev/null
    done

    if [[ -z "$TAXONOMY_FILE" ]]; then
        # First phase: no taxonomy provided. Assuming initial run. Generate sample list and taxonomy template

        log "Info" "Generating new samples.csv at $SAMPLES_CSV"
        echo "sample_id" > "$SAMPLES_CSV"
        find "$SAMPLE_DATA_PATH" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | awk '{print $1}' >> "$SAMPLES_CSV"

        log "Info" "Creating taxonomy_template.csv at $TAXONOMY_CSV"
        echo "sample_id,taxid,name" > "$TAXONOMY_CSV"
        tail -n +2 "$SAMPLES_CSV" | while read -r sample; do
            echo "$sample,," >> "$TAXONOMY_CSV"
        done

        # Analysis folder with softlinks
        RAW_FASTQ_DIR="$SAMPLE_ANALYSIS_PATH/inputs"
        mkdir -p "$RAW_FASTQ_DIR"

        log "Info" "Detecting FASTQ file pairs..."
        tail -n +2 "$SAMPLES_CSV" | while read -r sample; do
            sample_dir="$SAMPLE_DATA_PATH/$sample"
            log "Info" "Processing sample: $sample"

            R1_PATH=$(get_r1_fastq "$sample" "$SAMPLE_DATA_PATH")
            if [[ -z "$R1_PATH" ]]; then
                log "Warning" "R1 not found for sample $sample"
                continue
            fi

            R2_PATH=$(get_r2_fastq "$R1_PATH")
            if [[ -z "$R2_PATH" ]]; then
                log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
                continue
            fi

            log "Info" "Creating symlinks for sample $sample"
            ln -sf "$R1_PATH" "$RAW_FASTQ_DIR/$(basename "$R1_PATH")"
            ln -sf "$R2_PATH" "$RAW_FASTQ_DIR/$(basename "$R2_PATH")"
        done

        # Analysis folder with softlinks
        TRIM_FASTQ_DIR="$SAMPLE_ANALYSIS_PATH/trimmed"

        if $DO_TRIM; then
            while read -r sample; do
                R1_PATH=$(get_r1_fastq "$sample" "$SAMPLE_DATA_PATH")
                if [[ -z "$R1_PATH" ]]; then
                    log "Warning" "R1 not found for sample $sample"
                    continue
                fi

                R2_PATH=$(get_r2_fastq "$R1_PATH")
                if [[ -z "$R2_PATH" ]]; then
                    log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
                    continue
                fi

                log "Info" "Trimming $sample"
                bash "$PROJECT_ROOT/$TRIM_SCRIPT" "$R1_PATH" "$R2_PATH" "$sample" "$DATA_FOLDER" "$TRIM_FASTQ_DIR" "$CONFIG_SH_PATH"
            done < <(tail -n +2 "$SAMPLES_CSV")
        fi

        if $DO_FASTQC; then
            require_command "fastqc"
            require_command "multiqc"

            log "Run" "Running FastQC on all raw FASTQ files in $RAW_FASTQ_DIR"
            FASTQC_BEFORE_TRIM_DIR="$SAMPLE_ANALYSIS_PATH/fastqc_before_trim"
            mkdir -p "$FASTQC_BEFORE_TRIM_DIR"
            fastqc -t 8 --quiet -o "$FASTQC_BEFORE_TRIM_DIR" "$RAW_FASTQ_DIR"/*.fastq.gz
            log "Info" "FastQC completed. Output in $FASTQC_BEFORE_TRIM_DIR"

            log "Run" "Running MultiQC on FASTQC reports from raw FASTQ files in $FASTQC_BEFORE_TRIM_DIR"
            MULTIQC_BEFORE_TRIM_DIR="$SAMPLE_ANALYSIS_PATH/multiqc_before_trim"
            mkdir -p "$MULTIQC_BEFORE_TRIM_DIR"
            # for AI summary need to create and provide ACCESS_TOKEN. Maybe later
            multiqc "$FASTQC_BEFORE_TRIM_DIR" -o "$MULTIQC_BEFORE_TRIM_DIR"

            # Add in results folder
            cp -r "$MULTIQC_BEFORE_TRIM_DIR" "$SAMPLE_RESULTS_PATH"

            if [[ ! -d "$TRIM_FASTQ_DIR" ]]; then
                echo "Error" "No trimmed files found. Possibly you forgot/skipped trimming originally. Please run the below command for this project"
                echo "cmd" "bash run.sh --data $DATA_FOLDER --no-kraken --no-fastqc --no-extract"
            else
                log "Run" "Running FastQC on all trimmed FASTQ files in $TRIM_FASTQ_DIR"
                FASTQC_AFTER_TRIM_DIR="$SAMPLE_ANALYSIS_PATH/fastqc_after_trim"
                mkdir -p "$FASTQC_AFTER_TRIM_DIR"
                fastqc -t 8 --quiet -o "$FASTQC_AFTER_TRIM_DIR" "$TRIM_FASTQ_DIR"/*.fastq.gz
                log "Info" "FastQC completed. Output in $FASTQC_AFTER_TRIM_DIR"

                log "Run" "Running MultiQC on FASTQC reports from trimmed FASTQ files in $FASTQC_AFTER_TRIM_DIR"
                MULTIQC_AFTER_TRIM_DIR="$SAMPLE_ANALYSIS_PATH/multiqc_after_trim"
                mkdir -p "$MULTIQC_AFTER_TRIM_DIR"
                # for AI summary need to create and provide ACCESS_TOKEN. Maybe later
                multiqc "$FASTQC_AFTER_TRIM_DIR" -o "$MULTIQC_AFTER_TRIM_DIR"

                # Add in results folder
                cp -r "$MULTIQC_AFTER_TRIM_DIR" "$SAMPLE_RESULTS_PATH"
            fi

            # remove symlinks
            find $RAW_FASTQ_DIR -type l -exec rm {} +
        fi

        if $DO_KRAKEN; then
            require_command "kraken2"
            while read -r sample; do
                if $KRAKEN_FROM_TRIMMED; then
                    if [[ ! -d "$TRIM_FASTQ_DIR/$sample" ]]; then
                        echo "Error" "No trimmed files found. Possibly you forgot/skipped trimming originally. Please run the below command for this project"
                        echo "cmd" "bash run.sh --data $DATA_FOLDER --no-kraken --no-fastqc --no-extract"
                    else
                        R1_PATH=$(get_r1_fastq "$sample" "$TRIM_FASTQ_DIR")
                        if [[ -z "$R1_PATH" ]]; then
                            log "Warning" "R1 not found for sample $sample"
                            continue
                        fi
                        R2_PATH=$(get_r2_fastq "$R1_PATH")
                        if [[ -z "$R2_PATH" ]]; then
                            log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
                            continue
                        fi
                fi
                else
                    R1_PATH=$(get_r1_fastq "$sample" "$SAMPLE_DATA_PATH")
                    if [[ -z "$R1_PATH" ]]; then
                        log "Warning" "R1 not found for sample $sample"
                        continue
                    fi
                    R2_PATH=$(get_r2_fastq "$R1_PATH")
                    if [[ -z "$R2_PATH" ]]; then
                        log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
                        continue
                    fi
                fi

                log "Info" "Running Kraken2 on $sample"
                mkdir -p "$SAMPLE_ANALYSIS_PATH/kraken2"
                kraken2 --db $PROJECT_ROOT/$KRAKEN2_DB_PATH --threads $THREADS --paired --gzip-compressed $R1_PATH $R2_PATH --output "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_classify --report "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_report
                # Extract only the classified reads and reassign human reads to taxid 0
                awk '$1 == "C" { $3 = ($3 == "9606" ? 0 : $3); print $2 "\t" $3 }' "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_classify > "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_krona_input.txt
                log "Info" "Generating krona plot on $sample"
                ktImportTaxonomy -o "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_krona.html "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_krona_input.txt

            done < <(tail -n +2 "$SAMPLES_CSV")

            log "Info" "Generate combined krona plot for the project"
            ktImportTaxonomy -o "$SAMPLE_ANALYSIS_PATH/kraken2/$DATA_FOLDER"_all_combined.html `while read sample; do echo "$SAMPLE_ANALYSIS_PATH/kraken2/$sample"_krona_input.txt; done < <(tail -n +2 "$SAMPLES_CSV")`

            # Add in results folder
            cp "$SAMPLE_ANALYSIS_PATH/kraken2/$DATA_FOLDER"_all_combined.html "$SAMPLE_RESULTS_PATH"
        fi
    else
        log "Info" "Taxonomy file provided: $TAXONOMY_FILE"
        if [[ ! -d "$SAMPLE_ANALYSIS_PATH/kraken2" ]]; then
            echo "Error" "No kraken2 output files found. Possibly you forgot/skipped to run kraken2/krona originally. Please run the below command for this project"
            echo "Info" "Command using raw data:"
            echo "cmd" "bash run.sh --data $DATA_FOLDER --no-trim --no-fastqc --no-extract"
            echo "Info" "Command using trimmed data:"
            echo "cmd" "bash run.sh --data $DATA_FOLDER --no-trim --no-fastqc --no-extract --kraken-from-trimmed"
        else
            while IFS=',' read -r sample taxid name ; do
                if $EXTRACT_FROM_TRIMMED; then
                    if [[ ! -d "$TRIM_FASTQ_DIR" ]]; then
                        echo "Error" "No trimmed files found. Possibly you forgot/skipped trimming originally. Please run the below command for this project"
                        echo "cmd" "bash run.sh --data $DATA_FOLDER --no-kraken --no-fastqc --no-extract"
                    else
                        TRIM_FASTQ_DIR="$SAMPLE_ANALYSIS_PATH/trimmed"
                        R1_PATH=$(get_r1_fastq "$sample" "$TRIM_FASTQ_DIR")
                        if [[ -z "$R1_PATH" ]]; then
                            log "Warning" "R1 not found for sample $sample"
                            continue
                        fi
                        R2_PATH=$(get_r2_fastq "$R1_PATH")
                        if [[ -z "$R2_PATH" ]]; then
                            log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
                            continue
                        fi
                    fi
                else
                    R1_PATH=$(get_r1_fastq "$sample" "$SAMPLE_DATA_PATH")
                    if [[ -z "$R1_PATH" ]]; then
                        log "Warning" "R1 not found for sample $sample"
                        continue
                    fi
                    R2_PATH=$(get_r2_fastq "$R1_PATH")
                    if [[ -z "$R2_PATH" ]]; then
                        log "Warning" "R2 not found for sample $sample (R1: $(basename "$R1_PATH"))"
                        continue
                    fi
                fi

                # Kraken output file
                KRAKEN_PATH="$SAMPLE_ANALYSIS_PATH/kraken2/$sample"

                # Create path for extracted reads
                SAMPLE_EXTRACTION_PATH="$SAMPLE_ANALYSIS_PATH/extraction/$sample/$name"
                mkdir -p "$SAMPLE_EXTRACTION_PATH"

                # Output prefix
                OUTPUT_PREFIX="$SAMPLE_EXTRACTION_PATH/${sample}_${name}_taxid${taxid}"

                # Run KrakenTools to extract reads
                #python3 "$ENVIRONMENT_PATH/$EXTRACT_SCRIPT" -k "$KRAKEN_PATH"_classify -s "$R1_PATH" -s2 "$R2_PATH" -o "$OUTPUT_PREFIX"_R1.fastq.gz -o2 "$OUTPUT_PREFIX"_R2.fastq.gz --taxid "$taxid" --include-children --fastq-output --report "$KRAKEN_PATH"_report
                python3 "$ENVIRONMENT_PATH/$EXTRACT_SCRIPT" -k "$KRAKEN_PATH"_classify -s "$R1_PATH" -s2 "$R2_PATH" -o "$OUTPUT_PREFIX"_R1.fastq.gz -o2 "$OUTPUT_PREFIX"_R2.fastq.gz --taxid "$taxid" --fastq-output

                # De novo: SPAdes
                if [[ ! -s "$R1" || ! -s "$R2" ]]; then
                    log "Warning" "Skipping SPAdes: Extracted reads for $sample ($name) are empty or missing"
                else
                    spades.py -1 "$OUTPUT_PREFIX"_R1.fastq.gz -2 "$OUTPUT_PREFIX"_R2.fastq.gz -o "$SAMPLE_EXTRACTION_PATH/spades" -t "$THREADS" -m 16

                    # Add in results folder
                    mkdir -p "$SAMPLE_RESULTS_PATH/$sample/$name"
                    cp "$SAMPLE_EXTRACTION_PATH/spades/contigs.fasta" "$SAMPLE_RESULTS_PATH/$sample/$name/$sample_$name.fasta"

                    ## quality of sequence alignment data
                    STATS_PATH="$SAMPLE_RESULTS_PATH/$sample/$name/stats"
                    mkdir -p "$STATS_PATH"
                    # Quast without reference
                    #require_command "quast"
                    #quast "$SAMPLE_RESULTS_PATH/$sample/$name/$sample_$name.fasta" -o "$STATS_PATH/quast_output"

                    # Seqkit
                    require_command "seqkit"
                    seqkit stats "$SAMPLE_RESULTS_PATH/$sample/$name/$sample_$name.fasta" > "$STATS_PATH/seqkit_stats.txt"
                fi
            done < <(tail -n +2 "$TAXONOMY_FILE")
        fi
    fi
)
