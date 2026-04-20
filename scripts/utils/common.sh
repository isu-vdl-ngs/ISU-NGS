#!/usr/bin/env bash

###############################################################################
# Script Name: common.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: NGS Illumina pipeline common functions.
#              This script consists of functions to do the following:
#              - get_project_root: directory where this project is installed
#              - update_config_variable: updates variable value in config file
#              - log: logs info, warning, command, error, etc. from the pipeline
#              - require_command: checks if the command to be used is available
#              - activate_env_from_file: use environment details file created to
#                initiate the environment directly
#              - activate_env: extracts commands from environment details file
#                and activates the environment. Called by `activate_env_from_file`
#              - check_env_activated: checks if environment is properly activated.
#                Called by `activate_env_from_file`.
#              - get_r1_fastq: gets forward read file path for a given sample
#              - get_r2_fastq: gets reverse read file path for sample's forward file
#
# Requirements:
#   - Bash 4+
#
# Version:     1.0.0
###############################################################################

# ------------------------
# Get the project root directory
# Works whether inside a Git repo or ZIP download
# ------------------------
get_project_root() {
    local dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
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


# ------------------------
# Find if variable in config file, replace or add the variable
# ------------------------
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

# ------------------------
# Log a message with timestamp
# ------------------------
log() {
    local level="${1:-INFO}"
    shift
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
    # Print with timestamp and appropriate color on terminal
    echo -e "[${timestamp}] ${color}[$level_upper]${nc}"
    echo -e "$msg"
}

# ------------------------
# Check if required command is available
# ------------------------
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log "ERROR" "Missing required command: $cmd"
        exit 1
    fi
}

# ------------------------
# Extract commands to automatically activate the environment
# ------------------------
check_env_activated() {
    local REQUIRED_CMDS=("fastqc" "multiqc" "kraken2")

    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR" "Environment not activated: '$cmd' is not available in PATH."
            exit 1
        fi
    done

    log "Info" "Environment activation test"
}

activate_env() {
    local activation_file="$1"

    ENV_ACTIVATE_CMDS=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[cmd\]\ (.*)$ ]]; then
            ENV_ACTIVATE_CMDS+=("${BASH_REMATCH[1]}")
        fi
    done < "$activation_file"

    if [[ ${#ENV_ACTIVATE_CMDS[@]} -eq 0 ]]; then
        log "ERROR" "No environment activation commands found in $activation_file" >&2
        exit 1
    fi
}

activate_env_from_file() {
    local activation_file="$1"

    activate_env "$activation_file"

    log "Info" "Activating environment using commands from $activation_file"

    for cmd in "${ENV_ACTIVATE_CMDS[@]}"; do
        if [[ "$cmd" =~ micromamba\ shell\ hook ]]; then
            # Temporarily disable unbound variable errors
            set +u
            eval "$cmd"
            set -u
        else
            eval "$cmd"
        fi
    done

    # Now confirm activation
    check_env_activated
    log "Success" "Environment activated"
}

# Return the path to the R1 FASTQ file for a given sample
get_r1_fastq() {
    local sample="$1"
    local data_path="$2"
    local sample_dir="$data_path/$sample"

    shopt -s nullglob
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

# Return the path to the R2 FASTQ file, inferred from the R1 path
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
