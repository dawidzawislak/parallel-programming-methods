#!/bin/bash

set -euo pipefail
set -o physical

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# timestamp with 3 decimal places after seconds, e.g., 2024-06-01_12-30-45-123
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S-%3N)
OUTPUT_DIR="../proj1_results/run_at_${TIMESTAMP}"

mkdir -p "$OUTPUT_DIR"
# replace OUTPUT_DIR with resolved global path, regarding that this script is being run from SCRIPT_DIR
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

MAIN_OUT_FILE="${OUTPUT_DIR}/main_output.txt"

# redirect all output from this script to the main output file, so it does not apper in terminal, but is saved in the output directory
exec > "$MAIN_OUT_FILE" 2>&1

echo "Starting at ${TIMESTAMP}"
echo "Output will be saved to ${OUTPUT_DIR}"

