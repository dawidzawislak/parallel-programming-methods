#!/bin/bash
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=montecarlo_mpi
#SBATCH --output=out/mpi/std.out
#SBATCH --error=err/mpi/std.err

module load openmpi

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "MPI tasks: $SLURM_NTASKS"
echo "OMP threads: $OMP_NUM_THREADS"

srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo 1000000000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo 3000000000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo 8000000000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo 20000000000