#!/usr/bin/env bash
#SBATCH --job-name=benchmarks_gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --account=plgmpr26-gpu
#SBATCH --partition=plgrid-gpu-v100
#SBATCH --gres=gpu:1
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
module load cuda || true

export OMP_TARGET_OFFLOAD=MANDATORY

echo "Running on node: ${SLURMD_NODENAME:-unknown}"

if ! nvidia-smi -L >/dev/null 2>&1; then
    echo "No CUDA-capable GPU is visible in this allocation. Submit the job to a GPU node/partition and make sure the allocation includes a GPU."
    exit 1
fi

echo "Compiling kernels..."
gcc -fopenmp -foffload=nvptx-none="-misa=sm_70 -lm" -O3 matrix_gpu.c -o matrix_gpu -lm
gcc -fopenmp -foffload=nvptx-none="-misa=sm_70 -lm" -O3 mc_gpu.c -o mc_gpu -lm

RESULTS_CSV="benchmark_results_${SLURM_JOB_NAME:-bench}_${SLURM_JOB_ID:-local}.csv"
echo "benchmark,problem_size,gpu_count,time_ms,metric1,metric2" > "$RESULTS_CSV"

scale_to_target_matrix() {
    local n=512
    local max_n=16384  # ~2.8GB per matrix with 3 arrays, safe for V100
    while true; do
        echo "Running matrix_gpu n=$n"
        out=$(./matrix_gpu "$n" | tail -n1)
        # CSV: matrix_gpu,%d,1,%.6f,checksum
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
            echo "Reached max_n=$max_n; stopping scaling for matrix_gpu"
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
        echo "Running mc_gpu points=$points"
        out=$(./mc_gpu "$points" | tail -n1)
        # CSV: monte_carlo_pi_omp_gpu,%llu,1,%.6f,%.8f,%llu
        IFS=',' read -r bench pts gcount time_ms pi_est inside <<< "$out"
        echo "$out"
        echo "$bench,$pts,$gcount,$time_ms,$pi_est,$inside" >> "$RESULTS_CSV"
        time_val=$(awk -F',' '{print $4}' <<< "$out")
        if (( $(awk "BEGIN{print ($time_val >= $TARGET_MS)}") )); then
            echo "Reached target for monte carlo with points=$points (time $(awk "BEGIN{print $time_val/1000}")s)"
            break
        fi
        if [ "$points" -ge "$max_points" ]; then
            echo "Reached max_points=$max_points; stopping scaling for mc_gpu"
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
