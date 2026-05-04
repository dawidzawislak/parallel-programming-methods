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
ls -lh *.cu *.sh 2>/dev/null | head -20

NVCC=${NVCC:-nvcc}
TARGET_MS=10000.0

module load gcc/12.3.0 || true
module load cuda || true

echo "Running on node: ${SLURMD_NODENAME:-unknown}"

if ! nvidia-smi -L >/dev/null 2>&1; then
    echo "No CUDA-capable GPU is visible in this allocation. Submit the job to a GPU node/partition and make sure the allocation includes a GPU."
    exit 1
fi

echo "Compiling kernels..."
$NVCC -Wno-deprecated-gpu-targets -ccbin g++ -O2 -lineinfo \
    -gencode arch=compute_70,code=sm_70 \
    -gencode arch=compute_70,code=compute_70 \
    -gencode arch=compute_80,code=sm_80 \
    -gencode arch=compute_80,code=compute_80 \
    "$HERE_DIR/matrix_multiply.cu" -o "$HERE_DIR/matrix_multiply" || { echo "nvcc build failed for matrix_multiply"; exit 1; }

$NVCC -Wno-deprecated-gpu-targets -ccbin g++ -O2 -lineinfo \
    -gencode arch=compute_70,code=sm_70 \
    -gencode arch=compute_70,code=compute_70 \
    -gencode arch=compute_80,code=sm_80 \
    -gencode arch=compute_80,code=compute_80 \
    "$HERE_DIR/monte_carlo_pi.cu" -o "$HERE_DIR/monte_carlo_pi" || { echo "nvcc build failed for monte_carlo_pi"; exit 1; }

RESULTS_CSV="benchmark_results_${SLURM_JOB_NAME:-bench}_${SLURM_JOB_ID:-local}.csv"
echo "benchmark,problem_size,gpu_count,time_ms,metric1,metric2" > "$RESULTS_CSV"

scale_to_target_matrix() {
    local n=256
    local max_n=16384  # ~2.8GB per matrix with 3 arrays, safe for V100
    while true; do
        echo "Running matrix_multiply n=$n"
        out=$(./matrix_multiply "$n" | tail -n1)
        # CSV: matrix_multiply,%d,1,%.6f,checksum
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
            echo "Reached max_n=$max_n; stopping scaling for matrix_multiply"
            break
        fi
        # scale up
        n=$(( n * 2 ))
    done
}

scale_to_target_pi() {
    local points=100000000   # Start at 100M points
    local max_points=10000000000  # Cap at 10B points
    while true; do
        echo "Running monte_carlo_pi points=$points"
        out=$(./monte_carlo_pi "$points" | tail -n1)
        # CSV: monte_carlo_pi,%llu,1,%.6f,%.8f,%llu
        IFS=',' read -r bench pts gcount time_ms pi_est inside <<< "$out"
        echo "$out"
        echo "$bench,$pts,$gcount,$time_ms,$pi_est,$inside" >> "$RESULTS_CSV"
        time_val=$(awk -F',' '{print $4}' <<< "$out")
        if (( $(awk "BEGIN{print ($time_val >= $TARGET_MS)}") )); then
            echo "Reached target for monte carlo with points=$points (time $(awk "BEGIN{print $time_val/1000}")s)"
            break
        fi
        if [ "$points" -ge "$max_points" ]; then
            echo "Reached max_points=$max_points; stopping scaling for monte_carlo_pi"
            break
        fi
        # scale up
        points=$(( points * 2 ))
    done
}

echo "Starting adaptive runs (target ~${TARGET_MS} ms)..."
scale_to_target_matrix
scale_to_target_pi

echo "All runs appended to $RESULTS_CSV"
echo "Note: make $HERE_DIR/run_benchmarks.sh executable: chmod +x run_benchmarks.sh"
