#!/usr/bin/env bash

###############################################################################
# Script Name: scripts/utils/common.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: NGS Illumina pipeline common functions.
#              This script consists of functions to do the following:
#              - get_project_root: directory where this project is installed
#              - update_config_variable: updates variable value in config file
#              - log: logs info, warning, command, error, etc. from the pipeline
#              - require_command: checks if the command to be used is available,
#                and (optionally) that it resolves from inside the expected
#                environment prefix rather than a shadowing environment
#              - activate_env_from_file: use environment details file created to
#                initiate the environment directly. Idempotent: skips
#                re-activation if the target environment is already active.
#              - activate_env: extracts commands from environment details file
#                and activates the environment. Called by `activate_env_from_file`
#              - check_env_activated: checks if environment is properly activated
#                AND that required commands resolve from the expected prefix.
#                Called by `activate_env_from_file`.
#              - get_r1_fastq: gets forward read file path for a given sample
#              - get_r2_fastq: gets reverse read file path for sample's forward file
#
# Requirements:
#   - Bash 4+
#
# Version:     1.2.1
###############################################################################

[[ -n "${COMMON_SH_LOADED:-}" ]] && return
COMMON_SH_LOADED=1

# Get the project root directory
# Works whether inside a Git repo or ZIP download
get_project_root() {
    local dir
    dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/config/config.sh" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: Could not find project root containing config.sh" >&2
    return 1
}

# Find if variable in config file, replace or add the variable
update_config_variable() {
    local varname="$1"
    local varvalue="$2"
    local configfile="$3"

    local new_line="${varname}=\"${varvalue}\""
    local lockfile="${configfile}.lock"

    (
        # acquire lock (portable)
        exec 200>"$lockfile"
        flock -n 200 || return 1

        # remove ALL occurrences safely
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "/^[[:space:]]*${varname}[[:space:]]*=/d" "$configfile"
        else
            sed -i "/^[[:space:]]*${varname}[[:space:]]*=/d" "$configfile"
        fi

        # append single clean value
        echo "$new_line" >> "$configfile"
    )
}

# Log a message with timestamp
log() {
    local level="${1:-INFO}"
    shift || true
    local msg="$*"
    local level_upper
    level_upper=$(echo "$level" | tr '[:lower:]' '[:upper:]')

    # Define colors
    local nc='\033[0m'         # No Color
    local red='\033[0;31m'
    local yellow='\033[0;33m'
    local green='\033[0;32m'
    local cyan='\033[0;36m'
    local bright_blue='\033[1;34m'

    # Set color based on log level
    local color="$nc"
    case "$level_upper" in
        ERROR)
            color="$red"
            ;;
        WARNING|WARN)
            color="$yellow"
            ;;
        CMD)
            color="$cyan"
            ;;
        RUN)
            color="$bright_blue"
            ;;
        SUCCESS)
            color="$green"
            ;;
        INFO)
            color="$nc"
            ;;
        *)
            color="$nc"
            ;;
    esac

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "[${timestamp}] ${color}[$level_upper]${nc}"
    echo -e "$msg"
}

# Check if required command is available.
# Usage: require_command <cmd> [expected_prefix]
require_command() {
    local cmd="$1"
    local expected_prefix="${2:-}"
    local cmd_path

    if ! cmd_path="$(command -v "$cmd" 2>/dev/null)"; then
        log "ERROR" "Missing required command: $cmd"
        exit 1
    fi

    if [[ -n "$expected_prefix" && "$cmd_path" != "$expected_prefix"/* ]]; then
        log "ERROR" "'$cmd' resolved to $cmd_path, but expected it under $expected_prefix. Another environment on this system is shadowing it in PATH."
        exit 1
    fi
}

# Check that required pipeline commands resolve from the expected
# environment prefix, not from some other environment shadowing PATH.
# Usage: check_env_activated <expected_prefix>
check_env_activated() {
    local expected_prefix="$1"
    local REQUIRED_CMDS=("fastqc" "multiqc" "kraken2")

    local cmd
    for cmd in "${REQUIRED_CMDS[@]}"; do
        require_command "$cmd" "$expected_prefix"
    done

    log "Info" "Environment activation verified at $expected_prefix"
}

# Log which environment (path + name/version) and which tool versions are used.
log_environment_info() {
    log "Info" "Using environment: ${ENV_NAME:-unknown} v${VERSION:-unknown}"
    log "Info" "Environment path: ${ENVIRONMENT_PATH:-unknown}"

    local tool version_output
    for tool in python3 perl fastqc multiqc trimmomatic kraken2 spades.py seqkit ktImportTaxonomy; do
        if command -v "$tool" &>/dev/null; then
            version_output="$("$tool" --version 2>&1 | head -n 1)" || version_output="(version check failed)"
            log "Info" "  $tool ($(command -v "$tool")): $version_output"
        else
            log "Warning" "  $tool: not found in PATH"
        fi
    done
}

# Extract [cmd] lines to auto activate the environment
activate_env() {
    local activation_file="$1"

    ENV_ACTIVATE_CMDS=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[cmd\]\ (.*)$ ]]; then
            ENV_ACTIVATE_CMDS+=("${BASH_REMATCH[1]}")
        fi
    done < "$activation_file"

    if [[ ${#ENV_ACTIVATE_CMDS[@]} -eq 0 ]]; then
        log "ERROR" "No environment activation commands found in $activation_file"
        exit 1
    fi
}

# Activate the environment described in activation_steps.txt.
activate_env_from_file() {
    local activation_file="$1"

    activate_env "$activation_file"

    # micromamba/conda activate sets CONDA_PREFIX to the active env's path
    if [[ -n "${CONDA_PREFIX:-}" && "$CONDA_PREFIX" == "$ENVIRONMENT_PATH" ]]; then
        log "Info" "Environment already active at $ENVIRONMENT_PATH, skipping re-activation"
    else
        log "Info" "Activating environment using commands from $activation_file"
        local cmd
        for cmd in "${ENV_ACTIVATE_CMDS[@]}"; do
            if [[ "$cmd" =~ micromamba\ shell\ hook ]]; then
                set +u
                if ! eval "$cmd"; then
                    set -u
                    log "ERROR" "Activation command failed: $cmd"
                    exit 1
                fi
                set -u
            else
                if ! eval "$cmd"; then
                    log "ERROR" "Activation command failed: $cmd"
                    exit 1
                fi
            fi
        done
    fi

    check_env_activated "$ENVIRONMENT_PATH"
    log "Success" "Environment activated"
}

migrate_taxonomy_csv_if_needed() {
    local TAXONOMY_CSV="$1"

    [[ -f "$TAXONOMY_CSV" ]] || return 0

    local header
    header="$(head -n 1 "$TAXONOMY_CSV")"

    case "$header" in
        "sample_id,taxid,name,status")
            return 0
            ;;
        "sample_id,taxid,name")
            log "Info" "Migrating $TAXONOMY_CSV to add a 'status' column (filled-in rows -> process, blank rows -> skip)"
            local tmp="${TAXONOMY_CSV}.tmp.$$"
            {
                echo "sample_id,taxid,name,status"
                while IFS=',' read -r sample taxid name; do
                    [[ -z "$sample" ]] && continue
                    local status="skip"
                    if [[ -n "$taxid" && -n "$name" ]]; then
                        status="process"
                    fi
                    echo "${sample},${taxid},${name},${status}"
                done < <(tail -n +2 "$TAXONOMY_CSV")
            } > "$tmp"
            mv "$tmp" "$TAXONOMY_CSV"
            ;;
        *)
            log "Warning" "Unrecognized header in $TAXONOMY_CSV ('$header') - leaving file as-is. Expected 'sample_id,taxid,name,status'."
            ;;
    esac
}

# Return the path to the R1 FASTQ file for a given sample.
get_r1_fastq() {
    local sample="$1"
    local data_path="$2"
    local sample_dir="$data_path/$sample"

    shopt -s nullglob
    local fq1
    for fq1 in "$sample_dir"/*_R1_*.fastq.gz "$sample_dir"/*_R1.fastq.gz \
               "$sample_dir"/*_1.fastq.gz "$sample_dir"/*_1.fq.gz \
               "$sample_dir"/*.1.fastq.gz "$sample_dir"/*.R1.fastq.gz; do
        if [[ -f "$fq1" ]]; then
            echo "$fq1"
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

# Return the path to the R2 FASTQ file, inferred from the R1 path.
get_r2_fastq() {
    local r1_path="$1"

    local fq2="${r1_path/_R1_/_R2_}"
    fq2="${fq2/_R1./_R2.}"
    fq2="${fq2/_1./_2.}"
    fq2="${fq2/.1./.2.}"
    fq2="${fq2/.R1./.R2.}"

    if [[ -f "$fq2" ]]; then
        echo "$fq2"
        return 0
    else
        return 1
    fi
}
