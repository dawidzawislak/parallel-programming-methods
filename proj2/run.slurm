#!/bin/bash
#SBATCH --job-name=omp_gpu_matrix
#SBATCH --partition=plgrid-gpu-v100
#SBATCH --account=plgmpr26-gpu
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --output=output.txt
#SBATCH --error=error.txt

module purge
module load gcc
module load cuda

module list

export OMP_TARGET_OFFLOAD=MANDATORY

echo "=== COMPILING ==="
gcc -fopenmp -foffload=nvptx-none -O2 matrix_gpu.c -o matrix_gpu
gcc -fopenmp -O2 matrix_cpu.c -o matrix_cpu

echo "=== RUNNING GPU ==="
./matrix_gpu
echo "=== RUNNING CPU ==="
./matrix_cpu

echo "=== END JOB ==="