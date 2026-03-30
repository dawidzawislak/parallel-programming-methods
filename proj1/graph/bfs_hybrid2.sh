#!/bin/bash
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=bfs_hybrid2
#SBATCH --mem=20G
#SBATCH --output=out/hybrid2/std.out
#SBATCH --error=err/hybrid2/std.err

module load openmpi

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "MPI tasks: $SLURM_NTASKS"
echo "OMP threads: $OMP_NUM_THREADS"

srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./bfs generator/graphs/graph1.txt
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./bfs generator/graphs/graph2.txt
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./bfs generator/graphs/graph3.txt
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./bfs generator/graphs/graph4.txt