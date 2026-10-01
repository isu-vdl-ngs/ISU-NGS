#!/usr/bin/env bash
###############################################################################
# Adapter Type: assemble
# Adapter Name: spades
#
# Contract (required by scripts/lib/stages.sh):
#   assemble_adapter_spades <R1> <R2> <OUT_DIR> <THREADS> <MEM_GB>
#
#   On success:
#     $OUT_DIR/contigs.fasta
#
###############################################################################

assemble_adapter_spades() {
    local R1="$1"
    local R2="$2"
    local OUT_DIR="$3"
    local THREADS_ARG="$4"
    local MEM_GB="$5"

    require_command "spades.py" "${ENVIRONMENT_PATH:-}"

    spades.py -1 "$R1" -2 "$R2" -o "$OUT_DIR" -t "$THREADS_ARG" -m "$MEM_GB"
}
