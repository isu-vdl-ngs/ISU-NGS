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
#              - saves important created configuration from pipeline and environment.
#                New created configuration variables are saved under `Others` section.
#              - CPU threads to be used for commands.
#                Modify threads to lower than result from running `nproc` command.
#
# Requirements:
#   - Bash 4+
#
# Version:     1.0.0
###############################################################################


# Environment
ENV_NAME="isu-ngs"
VERSION="0.9.1"

# Tool Versions
PYTHON_VERSION="3.13"
PERL_VERSION="5.32.1"
FASTQC_VERSION="0.12.1"
MULTIQC_VERSION="1.31"
TRIMMOMATIC_VERSION="0.40"
KRONA_VERSION="2.8.1"
ENTREZ_DIRECT_VERSION="24.0"
KRAKENTOOLS_VERSION="1.2.1"
KRAKEN2_VERSION="2.1.6"
SPADES_VERSION="4.2.0"
BIOPYTHON_VERSION="1.85"
QUALIMAP_VERSION="2.3"
GIT_VERSION="2.51.0"

# CLI/Utility Tools
WGET_VERSION="1.21.4"
SEQKIT_VERSION="2.10.1"
SEQTK_VERSION="1.5"
CURL_VERSION="8.14.1"

# Database URLs
KRAKEN2_DB_URL="https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20250714.tar.gz"
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

# Folder Structure
DATA_DIR="data"
ANALYSIS_DIR="analysis"
RESULTS_DIR="results"

# Process
THREADS="16"

# Others
