#!/usr/bin/env bash

###############################################################################
# Script Name: config.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: Configuration for ISU-NGS pipeline.
#              This file is extremely crucial that helps to make this pipeline
#              modular, reusable, portable, customizable, manageable, expandable
#              while assisting in it being centralized and version controlled.
#              Along with that it helps in the creation of automated environment.
#              The file consists of the following:
#              - current version of the ISU-NGS pipeline.
#              - folder structure of the pipeline to make it modular, reproducible.
#              - environment package versions.
#              - Kraken2 database URL and relative path.
#              - path to important scripts.
#              - tool selection (which adapter implementation each stage uses).
#              - saves important created configuration from pipeline and environment.
#                New created configuration variables are saved under `Others` section.
#              - CPU threads to be used for commands.
#                Modify threads to lower than result from running `nproc` command.
#
# Requirements:
#   - Bash 4+
#
###############################################################################

# only allow simple assignments
set -euo pipefail

# Environment
ENV_NAME="isu-ngs"
VERSION="0.9.8"

# Tool Versions
# Leave a version blank to install the latest available version for that tool which fulfills requisites.
PYTHON_VERSION="3.12"
PERL_VERSION=
FASTQC_VERSION=
MULTIQC_VERSION=
TRIMMOMATIC_VERSION=
KRONA_VERSION=
ENTREZ_DIRECT_VERSION=
KRAKENTOOLS_VERSION=
KRAKEN2_VERSION=
SPADES_VERSION=
BIOPYTHON_VERSION=
QUALIMAP_VERSION=
GIT_VERSION=
SRATOOLS_VERSION=
PARALLEL_VERSION=

# CLI/Utility Tools
WGET_VERSION=
SEQKIT_VERSION=
SEQTK_VERSION=
CURL_VERSION=

# Database URLs
KRAKEN2_DB_URL="https://genome-idx.s3.amazonaws.com/kraken/k2_minusb_20260226.tar.gz"
KRAKEN2_DB_PATH="db/kraken2_db"

# Scripts
EXTRACT_SCRIPT="bin/extract_kraken_reads.py"
SPADES_SCRIPT="bin/spades.py"
ENV_SETUP_SCRIPT="setup/envs.sh"
KRAKEN2DB_SETUP_SCRIPT="setup/kraken2DB.sh"
COMMON_SCRIPT="scripts/utils/common.sh"
CONFIG_SCRIPT="config/config.sh"
TRIM_SCRIPT="scripts/trim.sh"
TRIM_ADAPTERS_FILE="scripts/utils/NexteraPE-PE.fa"
STAGES_SCRIPT="scripts/lib/stages.sh"
ADAPTERS_DIR="scripts/lib/adapters"

# Tool Selection
# Change these to swap which implementation each pipeline stage uses,
# WITHOUT touching any pipeline code. Each value must match the name of a
# function inside a file under $ADAPTERS_DIR/<stage>/, e.g. TRIMMER="fastp"
# requires a function trim_adapter_fastp() defined in
# scripts/lib/adapters/trim/fastp.sh. See scripts/lib/adapters/README.md
# (or the header comment in scripts/lib/stages.sh) for the exact contract
# each adapter type must satisfy.
TRIMMER="trimmomatic"     # scripts/lib/adapters/trim/trimmomatic.sh
CLASSIFIER="kraken2"      # scripts/lib/adapters/classify/kraken2.sh (also provides matching read extraction)
ASSEMBLER="spades"        # scripts/lib/adapters/assemble/spades.sh

# Folder Structure
DATA_DIR="data"
ANALYSIS_DIR="analysis"
RESULTS_DIR="results"
SETUP_LOGS_DIR="logs/setup"
RUN_LOGS_DIR="logs/run"

# Process
THREADS="4"
ASSEMBLY_MEM_GB="16"

# Others
