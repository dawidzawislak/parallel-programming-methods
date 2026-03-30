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

mkdir -p "$RUN_DIR/jobs" "$RUN_DIR/audit" "$RUN_DIR/meta"

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
#   short_name|workdir_rel|script_rel|args
#
# short_name must be exactly 4 characters.
# Final job name is:
#   <short_name><config_suffix>
# so total length must be exactly 8 characters.
declare -a JOB_DEFINITIONS=(
    # "c_gr|proj1/graph|proj1/graph/bfs_main.sh|${ROOT_DIR}/run_configs/graphs"
    # "c_mn|proj1/montecarlo|proj1/montecarlo/mc_main.sh|${ROOT_DIR}/run_configs/montecarlo.txt"
    # "c_nb|proj1/nbody|proj1/nbody/nbody_main.sh|${ROOT_DIR}/run_configs/nbody.txt"

    "j_gr|proj1_java/|proj1_java/graph_benchmark.slurm|${ROOT_DIR}/run_configs/graphs"
    "j_nb|proj1_java/|proj1_java/moldyn_benchmark.slurm|${ROOT_DIR}/run_configs/nbody.txt"
    # "j_mc|proj1_java/|proj1_java/montecarlo_benchmark.slurm|${ROOT_DIR}/run_configs/montecarlo.txt"
)

# Format:
#   nodes|cpus_per_task|suffix
#
# suffix must be exactly 4 characters.
declare -a CONFIGURATIONS=(
    "8|1|n8c1"
    "4|2|n4c2"
    # "2|4|n2c4"
    # "1|8|n1c8"
)

printf "job_name\tworkdir_rel\tscript_rel\tstdout\tstderr\n" >"$MANIFEST_TSV"
printf "job_name\tjob_id\tstdout\tstderr\tscript_rel\n" >"$JOBS_TSV"

declare -a SUBMITTED_JOB_IDS=()

require_exact_length() {
    local label="$1"
    local value="$2"
    local expected_length="$3"

    if [[ "${#value}" -ne "$expected_length" ]]; then
        echo "ERROR: ${label} must be exactly ${expected_length} characters, got '${value}' (${#value})"
        exit 1
    fi
}

require_existing_dir() {
    local path="$1"
    local description="$2"

    if [[ ! -d "$path" ]]; then
        echo "ERROR: missing ${description}: ${path}"
        exit 1
    fi
}

require_existing_file() {
    local path="$1"
    local description="$2"

    if [[ ! -f "$path" ]]; then
        echo "ERROR: missing ${description}: ${path}"
        exit 1
    fi
}

submit_benchmark_job() {
    local job_name="$1"
    local workdir_rel="$2"
    local script_rel="$3"
    local args="$4"
    local nodes="$5"
    local cpus_per_task="$6"

    local workdir_abs="${ROOT_DIR}/${workdir_rel}"
    local script_abs="${ROOT_DIR}/${script_rel}"
    local stdout_file="${RUN_DIR}/jobs/${job_name}.out"
    local stderr_file="${RUN_DIR}/jobs/${job_name}.out"

    require_exact_length "job_name" "$job_name" 8
    require_existing_dir "$workdir_abs" "workdir for ${job_name}"
    require_existing_file "$script_abs" "script for ${job_name}"

    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$job_name" \
        "$workdir_rel" \
        "$script_rel" \
        "$stdout_file" \
        "$stderr_file" >>"$MANIFEST_TSV"

    echo "Submitting benchmark job: ${job_name}"
    echo "  workdir        : ${workdir_abs}"
    echo "  script         : ${script_abs}"
    echo "  stdout         : ${stdout_file}"
    echo "  stderr         : ${stderr_file}"
    echo "  nodes          : ${nodes}"
    echo "  cpus-per-task  : ${cpus_per_task}"
    echo "  args           : ${args:-<none>}"

    local -a sbatch_cmd=(
        sbatch
        --parsable
        --exclusive
        --nodes="$nodes"
        --cpus-per-task="$cpus_per_task"
        --chdir="$workdir_abs"
        --job-name="$job_name"
        --output="$stdout_file"
        --error="$stderr_file"
        "$script_abs"
    )

    if [[ -n "$args" ]]; then
        sbatch_cmd+=("$args")
    fi

    local job_id
    job_id="$("${sbatch_cmd[@]}")"

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
    IFS='|' read -r short_name workdir_rel script_rel args <<<"$definition"

    require_exact_length "short_name" "$short_name" 4

    for configuration in "${CONFIGURATIONS[@]}"; do
        IFS='|' read -r nodes cpus_per_task config_suffix <<<"$configuration"

        require_exact_length "config suffix" "$config_suffix" 4

        submit_benchmark_job \
            "${short_name}${config_suffix}" \
            "$workdir_rel" \
            "$script_rel" \
            "$args" \
            "$nodes" \
            "$cpus_per_task"
    done
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
    AUDIT_STDERR="${RUN_DIR}/audit/err.txt"

    echo "Submitting audit job with dependency afterany:${DEPENDENCY_LIST}"
    echo "  audit script: ${AUDIT_SCRIPT}"
    echo "  stdout      : ${AUDIT_STDOUT}"
    echo "  stderr      : ${AUDIT_STDERR}"

    AUDIT_JOB_ID="$(
        sbatch \
            --parsable \
            --job-name="audit001" \
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