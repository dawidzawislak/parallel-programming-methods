#!/bin/bash

set -euo pipefail
set -o physical

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

cd "$SCRIPT_DIR" || exit 1

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S-%3N)"
RUN_DIR="${ROOT_DIR}/proj1_results/run_at_${TIMESTAMP}"
MAIN_OUT_FILE="${RUN_DIR}/main_output.txt"
MANIFEST_TSV="${RUN_DIR}/manifest.tsv"
JOBS_TSV="${RUN_DIR}/jobs.tsv"

# Optional:
#   ./main_run.sh
#   ./main_run.sh path/to/audit.sh
#   AUDIT_SCRIPT=path/to/audit.sh ./main_run.sh
AUDIT_SCRIPT="${1:-${AUDIT_SCRIPT:-${SCRIPT_DIR}/audit.sh}}"

mkdir -p "$RUN_DIR"
mkdir -p "$RUN_DIR/jobs"
mkdir -p "$RUN_DIR/audit"
mkdir -p "$RUN_DIR/meta"

exec >"$MAIN_OUT_FILE" 2>&1

echo "==== main_run.sh started ===="
echo "Timestamp: ${TIMESTAMP}"
echo "SCRIPT_DIR: ${SCRIPT_DIR}"
echo "ROOT_DIR: ${ROOT_DIR}"
echo "RUN_DIR: ${RUN_DIR}"
echo "MAIN_OUT_FILE: ${MAIN_OUT_FILE}"
echo "AUDIT_SCRIPT: ${AUDIT_SCRIPT}"
echo

if ! command -v sbatch >/dev/null 2>&1; then
    echo "ERROR: sbatch is not available in PATH"
    exit 1
fi

# Format:
#   job_name|workdir_rel|script_rel|args
declare -a JOB_DEFINITIONS=(
    "graph_omp|proj1/graph|proj1/graph/bfs_omp.sh"
    "graph_mpi|proj1/graph|proj1/graph/bfs_mpi.sh"
    "graph_hybrid|proj1/graph|proj1/graph/bfs_hybrid.sh"
    "graph_hybrid2|proj1/graph|proj1/graph/bfs_hybrid2.sh"

    "montecarlo_omp|proj1/montecarlo|proj1/montecarlo/mc_omp.sh"
    "montecarlo_mpi|proj1/montecarlo|proj1/montecarlo/mc_mpi.sh"
    "montecarlo_hybrid|proj1/montecarlo|proj1/montecarlo/mc_hybrid.sh"
    "montecarlo_hybrid2|proj1/montecarlo|proj1/montecarlo/mc_hybrid2.sh"

    "nbody_omp|proj1/nbody|proj1/nbody/nbody_omp.sh"
    "nbody_mpi|proj1/nbody|proj1/nbody/nbody_mpi.sh"
    "nbody_hybrid|proj1/nbody|proj1/nbody/nbody_hybrid.sh"
    "nbody_hybrid2|proj1/nbody|proj1/nbody/nbody_hybrid2.sh"

    "java_1_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|1"
    "java_2_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|2"
    "java_3_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|3"
    "java_4_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|4"
    "java_5_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|5"
    "java_6_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|6"
    "java_7_benchmark_easy|proj1_java|proj1_java/benchmark_easy.slurm|7"
)

{
    printf "job_name\tworkdir_rel\tscript_rel\tstdout\tstderr\n"
} >"$MANIFEST_TSV"

{
    printf "job_name\tjob_id\tstdout\tstderr\tscript_rel\n"
} >"$JOBS_TSV"

declare -a SUBMITTED_JOB_IDS=()

submit_benchmark_job() {
    local job_name="$1"
    local workdir_rel="$2"
    local script_rel="$3"

    local workdir_abs="${ROOT_DIR}/${workdir_rel}"
    local script_abs="${ROOT_DIR}/${script_rel}"
    local job_dir="${RUN_DIR}/jobs/${job_name}"
    local stdout_file="${job_dir}/out.txt"
    local stderr_file="${job_dir}/out.txt"

    mkdir -p "$job_dir"

    if [[ ! -d "$workdir_abs" ]]; then
        echo "ERROR: missing workdir for ${job_name}: ${workdir_abs}"
        exit 1
    fi

    if [[ ! -f "$script_abs" ]]; then
        echo "ERROR: missing script for ${job_name}: ${script_abs}"
        exit 1
    fi

    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$job_name" \
        "$workdir_rel" \
        "$script_rel" \
        "$stdout_file" \
        "$stderr_file" >>"$MANIFEST_TSV"

    echo "Submitting benchmark job: ${job_name}"
    echo "  workdir: ${workdir_abs}"
    echo "  script : ${script_abs}"
    echo "  stdout : ${stdout_file}"
    echo "  stderr : ${stderr_file}"

    local job_id
    job_id="$(
        sbatch \
            --parsable \
            --chdir="$workdir_abs" \
            --job-name="$job_name" \
            --output="$stdout_file" \
            --error="$stderr_file" \
            "$script_abs" "$args"
    )"

    SUBMITTED_JOB_IDS+=("$job_id")

    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$job_name" \
        "$job_id" \
        "$stdout_file" \
        "$stderr_file" \
        "$script_rel" >>"$JOBS_TSV"

    echo "  submitted as job_id=${job_id}"
    echo
}

for definition in "${JOB_DEFINITIONS[@]}"; do
    IFS='|' read -r job_name workdir_rel script_rel args <<<"$definition"
    submit_benchmark_job "$job_name" "$workdir_rel" "$script_rel"
done

echo "All benchmark jobs submitted."
echo "Submitted job IDs: ${SUBMITTED_JOB_IDS[*]}"
echo

if (( ${#SUBMITTED_JOB_IDS[@]} == 0 )); then
    echo "ERROR: no benchmark jobs were submitted"
    exit 1
fi

DEPENDENCY_LIST="$(IFS=:; echo "${SUBMITTED_JOB_IDS[*]}")"

AUDIT_JOB_ID=""
if [[ -f "$AUDIT_SCRIPT" ]]; then
    if [[ ! -x "$AUDIT_SCRIPT" ]]; then
        chmod u+x "$AUDIT_SCRIPT"
    fi

    AUDIT_STDOUT="${RUN_DIR}/audit/out.txt"
    AUDIT_STDERR="${RUN_DIR}/audit/out.txt"

    echo "Submitting audit job with dependency afterany:${DEPENDENCY_LIST}"
    echo "  audit script: ${AUDIT_SCRIPT}"
    echo "  stdout      : ${AUDIT_STDOUT}"
    echo "  stderr      : ${AUDIT_STDERR}"

    AUDIT_JOB_ID="$(
        sbatch \
            --parsable \
            --job-name="proj1_audit" \
            --dependency="afterany:${DEPENDENCY_LIST}" \
            --output="$AUDIT_STDOUT" \
            --error="$AUDIT_STDERR" \
            --export="ALL,RUN_DIR=${RUN_DIR},JOBS_TSV=${JOBS_TSV},MANIFEST_TSV=${MANIFEST_TSV},MAIN_OUT_FILE=${MAIN_OUT_FILE}" \
            --wrap "bash \"${AUDIT_SCRIPT}\""
    )"

    echo "Audit job submitted as job_id=${AUDIT_JOB_ID}"
    echo
else
    echo "Audit script not found, skipping audit job submission:"
    echo "  ${AUDIT_SCRIPT}"
    echo
fi

cat >"${RUN_DIR}/meta/summary.txt" <<EOF
timestamp=${TIMESTAMP}
run_dir=${RUN_DIR}
main_out_file=${MAIN_OUT_FILE}
manifest_tsv=${MANIFEST_TSV}
jobs_tsv=${JOBS_TSV}
benchmark_job_ids=${SUBMITTED_JOB_IDS[*]}
audit_script=${AUDIT_SCRIPT}
audit_job_id=${AUDIT_JOB_ID}
EOF

echo "==== submission summary ===="
echo "Run dir         : ${RUN_DIR}"
echo "Manifest        : ${MANIFEST_TSV}"
echo "Jobs TSV        : ${JOBS_TSV}"
echo "Benchmark count : ${#SUBMITTED_JOB_IDS[@]}"
echo "Audit job id    : ${AUDIT_JOB_ID:-<not submitted>}"
echo "==== main_run.sh finished ===="