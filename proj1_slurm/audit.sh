#!/bin/bash

set -euo pipefail
set -o physical

: "${RUN_DIR:?RUN_DIR is required}"
: "${JOBS_TSV:?JOBS_TSV is required}"
: "${MANIFEST_TSV:?MANIFEST_TSV is required}"

AUDIT_REPORT="${RUN_DIR}/audit/report.txt"

{
    echo "==== audit started ===="
    echo "RUN_DIR=${RUN_DIR}"
    echo "JOBS_TSV=${JOBS_TSV}"
    echo "MANIFEST_TSV=${MANIFEST_TSV}"
    echo

    echo "Submitted jobs:"
    cat "${JOBS_TSV}"
    echo

    echo "Per-job status from sacct:"
    echo

    tail -n +2 "${JOBS_TSV}" | while IFS=$'\t' read -r job_name job_id stdout_file stderr_file script_rel; do
        echo "--- ${job_name} (${job_id}) ---"
        sacct -j "${job_id}" --format=JobID,JobName%30,State,ExitCode,Elapsed -P || true
        echo
    done

    echo "==== audit finished ===="
} >"${AUDIT_REPORT}" 2>&1