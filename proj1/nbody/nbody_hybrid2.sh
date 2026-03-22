#!/bin/bash
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:10:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=nbody_hybrid2
#SBATCH --output=out/hybrid2/std.out
#SBATCH --error=err/hybrid2/std.err

module load openmpi

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "MPI tasks: $SLURM_NTASKS"
echo "OMP threads: $OMP_NUM_THREADS"

srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 4000 50
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 6000 75
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 9000 100
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 12000 100