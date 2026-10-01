#!/usr/bin/env bash

###############################################################################
# Script Name: setup/envs.sh
# Author:      Anugrah Saxena
# Email:       anugrah@iastate.edu
# Date:        2025-09-18
# Description: Micromamba environment setup script called by setup.sh.
#              This script creates new micromamba environment automatically
#              based on the configuration provided and saves details in
#              activation_steps.txt file to be extracted.
#
# Requirements:
#   - Bash 4+
#   - config.sh, common.sh
#
# Version:     1.1.1
###############################################################################

handle_interrupt() {
    echo ""
    log "Warning" "Setup interrupted by user (Ctrl+C). Exiting."
    exit 130
}
trap handle_interrupt INT

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/config.sh"
    exit 1
fi

CONFIG_SH_PATH="$1"

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

# List of required variable names (as strings)
REQUIRED_VARS=(
    ENVIRONMENT_ROOT
    VERSION
    PYTHON_VERSION
)

# Loop through and check if each is defined and non-empty.
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var+x}" ]]; then
        log "ERROR" "$var is not set in config file"
        exit 1
    fi
done

# Get the absolute path to the folder containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENVIRONMENT_PATH="${ENVIRONMENT_ROOT}/envs/ngs${VERSION}"

# defining $MAMBA_ROOT_PREFIX for micromamba's shell-hook functions.
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$ENVIRONMENT_ROOT/.mamba_root}"
mkdir -p "$MAMBA_ROOT_PREFIX"

micromamba create -y -p "$ENVIRONMENT_PATH" -c conda-forge -c bioconda "python=${PYTHON_VERSION}"

eval "$(micromamba shell hook --shell bash)"
micromamba activate "$ENVIRONMENT_PATH"

# generate package specs from config.sh's version variables.
pkgspec() {
    local name="$1"
    local ver="$2"
    if [[ -n "$ver" ]]; then
        echo "${name}=${ver}"
    else
        echo "$name"
    fi
}

PACKAGES=(
    "$(pkgspec kraken2 "$KRAKEN2_VERSION")"
    "$(pkgspec fastqc "$FASTQC_VERSION")"
    "$(pkgspec multiqc "$MULTIQC_VERSION")"
    "$(pkgspec trimmomatic "$TRIMMOMATIC_VERSION")"
    "$(pkgspec krona "$KRONA_VERSION")"
    "$(pkgspec entrez-direct "$ENTREZ_DIRECT_VERSION")"
    "$(pkgspec krakentools "$KRAKENTOOLS_VERSION")"
    "$(pkgspec wget "$WGET_VERSION")"
    "$(pkgspec seqkit "$SEQKIT_VERSION")"
    "$(pkgspec seqtk "$SEQTK_VERSION")"
    "$(pkgspec qualimap "$QUALIMAP_VERSION")"
    "$(pkgspec biopython "$BIOPYTHON_VERSION")"
    "$(pkgspec spades "$SPADES_VERSION")"
    "$(pkgspec perl "$PERL_VERSION")"
    "$(pkgspec curl "$CURL_VERSION")"
    "$(pkgspec git "$GIT_VERSION")"
    "$(pkgspec sra-tools "$SRATOOLS_VERSION")"
    "$(pkgspec parallel "$PARALLEL_VERSION")"
    # If you add a new adapter under scripts/lib/adapters/ that needs a
    # package not already listed above (e.g. fastp, centrifuge, megahit),
    # add it here so `bash setup.sh --env` installs it too.
)

micromamba install -y -c conda-forge -c bioconda "${PACKAGES[@]}"

log "Success" "Micromamba environment for ISU-NGS Pipeline at path: ${ENVIRONMENT_PATH}"
log "Info" "Activate your environment by using the below commands:"
log "CMD" 'eval "$(micromamba shell hook --shell bash)"'
log "CMD" "micromamba activate ${ENVIRONMENT_PATH}"

# Update/Add ENVIRONMENT_PATH where its installed if present in config
update_config_variable "ENVIRONMENT_PATH" "$ENVIRONMENT_PATH" "$CONFIG_SH_PATH"
log "Info" "Updated ENVIRONMENT_PATH in config.sh"

update_config_variable "MAMBA_ROOT_PREFIX" "$MAMBA_ROOT_PREFIX" "$CONFIG_SH_PATH"
log "Info" "Updated MAMBA_ROOT_PREFIX in config.sh"

ENV_ACTIVATION_FILE="$SCRIPT_DIR/activation_steps.txt"
log "Info" "Check $ENV_ACTIVATION_FILE file on how to initiate the environment along with shortcut"

update_config_variable "ENV_ACTIVATION_FILE" "$ENV_ACTIVATION_FILE" "$CONFIG_SH_PATH"
log "Info" "Updated ENV_ACTIVATION_FILE in config.sh"

# Run updateTaxonomy.sh for krona
bash "$ENVIRONMENT_PATH/opt/krona/updateTaxonomy.sh"
log "Info" "Ran Krona's updateTaxonomy.sh"

# Create Environment activation file
cat <<EOF > "$ENV_ACTIVATION_FILE"
# paste (line only after cmd) the below commands on your screen start your environment if needed for debugging
[cmd] export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX}"
[cmd] eval "\$(micromamba shell hook --shell bash)"
[cmd] micromamba activate ${ENVIRONMENT_PATH}

# Optional Step, you can create a shortcut / alias command of your own to run it easily everytime
# Step 1) Copy the below lines

function ngsload() {
        export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX}"
        eval "\$(micromamba shell hook --shell bash)"
        micromamba activate ${ENVIRONMENT_PATH}
}

# On terminal/command line do the following
# Step 2) vim ~/.bashrc
# Step 3) Press i and paste using your cursor/mouse
# Step 4) Press Esc button and then :wq
# Step 5) source ~/.bashrc
# Now, whenever you type 'ngsload' on your screen and Press Enter it will start your environment

# Have a wonderful rest of your day :)
EOF
