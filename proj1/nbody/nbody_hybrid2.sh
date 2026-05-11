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

mpicc -O3 -march=native -ffast-math -fopenmp nbody.c -o nbody

srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 50 5000 
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 80 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 110 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 140 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 170 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 200 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 230 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 260 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 290 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 320 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 350 5000
srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 380 5000