#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --time=00:30:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=bfs_omp
#SBATCH --mem=20G
#SBATCH --output=out/omp/std.out
#SBATCH --error=err/omp/std.err

module load openmpi

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "=== COMPILING ==="
gcc -fopenmp -O2 matrix_cpu.c -o matrix_cpu

echo "=== RUNNING CPU ==="
./matrix_cpu

echo "=== END JOB ==="