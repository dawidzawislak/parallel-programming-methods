#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=montecarlo_omp
#SBATCH --output=out/omp/std.out
#SBATCH --error=err/omp/std.err

module load openmpi

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "MPI tasks: $SLURM_NTASKS"
echo "OMP threads: $OMP_NUM_THREADS"

CONFIG_FILE_PATH="../../run_configs/montecarlo.txt"
COMMAND=(
    srun
    --mpi=pmix
    --export=ALL,OMPI_MCA_psec=^munge
    ./montecarlo
)

mapfile -t config_lines < "$CONFIG_FILE_PATH"

for line in "${config_lines[@]}"; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    echo ""
    echo "Running command:"
    printf '    %q ' "${COMMAND[@]}" "$line"
    echo ""
    echo ""

    "${COMMAND[@]}" "$line"
done

# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo
# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo
# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo
# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./montecarlo

echo "MonteCarlo benchmark completed."