#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --time=00:30:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=benchmarks_cpu
#SBATCH --mem=20G
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err

set -euo pipefail

# Determine script directory: prefer $SLURM_SUBMIT_DIR, fall back to BASH_SOURCE
if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
    HERE_DIR="$SLURM_SUBMIT_DIR"
else
    HERE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
fi

echo "Script directory: $HERE_DIR"
cd "$HERE_DIR" || { echo "Failed to cd to $HERE_DIR"; exit 1; }
echo "Current working directory: $(pwd)"
echo "Files in current directory:"
ls -lh *.c *.sh 2>/dev/null | head -20 || true

TARGET_MS=100000.0

module load gcc/12.3.0 || true

echo "Running on node: ${SLURMD_NODENAME:-unknown}"

echo "Compiling kernels..."
gcc -fopenmp -O3 matrix_cpu.c -o matrix_cpu
gcc -fopenmp -O3 mc_cpu.c -o mc_cpu

RESULTS_CSV="benchmark_results_${SLURM_JOB_NAME:-bench}_${SLURM_JOB_ID:-local}.csv"
echo "benchmark,problem_size,gpu_count,time_ms,metric1,metric2" > "$RESULTS_CSV"

scale_to_target_matrix() {
    local n=512
    local max_n=16384  # ~2.8GB per matrix with 3 arrays, safe for V100
    while true; do
        echo "Running matrix_cpu n=$n"
        out=$(./matrix_cpu "$n" | tail -n1)
        # CSV: matrix_cpu,%d,1,%.6f,checksum
        IFS=',' read -r bench size gcount time_ms checksum <<< "$out"
        echo "$out"
        echo "$bench,$size,$gcount,$time_ms,$checksum," >> "$RESULTS_CSV"
        # compare time
        time_val=$(awk -F',' '{print $4}' <<< "$out")
        time_sec=$(awk "BEGIN{print $time_val/1000.0}")
        if (( $(awk "BEGIN{print ($time_val >= $TARGET_MS)}") )); then
            echo "Reached target for matrix with n=$n (time ${time_sec}s)"
            break
        fi
        if [ "$n" -ge "$max_n" ]; then
            echo "Reached max_n=$max_n; stopping scaling for matrix_cpu"
            break
        fi
        # scale up
        n=$(( n * 2 ))
    done
}

scale_to_target_pi() {
    local points=300000000   # Start at 100M points
    local max_points=100000000000  # Cap at 10B points
    while true; do
        echo "Running mc_cpu points=$points"
        out=$(./mc_cpu "$points" | tail -n1)
        # CSV: monte_carlo_pi_omp_cpu,%llu,1,%.6f,%.8f,%llu
        IFS=',' read -r bench pts gcount time_ms pi_est inside <<< "$out"
        echo "$out"
        echo "$bench,$pts,$gcount,$time_ms,$pi_est,$inside" >> "$RESULTS_CSV"
        time_val=$(awk -F',' '{print $4}' <<< "$out")
        if (( $(awk "BEGIN{print ($time_val >= $TARGET_MS)}") )); then
            echo "Reached target for monte carlo with points=$points (time $(awk "BEGIN{print $time_val/1000}")s)"
            break
        fi
        if [ "$points" -ge "$max_points" ]; then
            echo "Reached max_points=$max_points; stopping scaling for mc_cpu"
            break
        fi
        # scale up
        points=$(( points * 2 ))
    done
}

echo "Starting adaptive runs (target ~${TARGET_MS} ms)..."
# scale_to_target_matrix
scale_to_target_pi

echo "All runs appended to $RESULTS_CSV"
echo "Note: make $HERE_DIR/run_benchmarks.sh executable: chmod +x run_benchmarks.sh"
