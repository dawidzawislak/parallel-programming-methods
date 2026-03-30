#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --account=plgmpr26-cpu
#SBATCH --partition=plgrid
#SBATCH --job-name=nbody_omp
#SBATCH --output=out/omp/std.out
#SBATCH --error=err/omp/std.err

module load openmpi

export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "MPI tasks: $SLURM_NTASKS"
echo "OMP threads: $OMP_NUM_THREADS"

CONFIG_FILE_PATH=$1 #"../../run_configs/nbody.txt"
COMMAND=(
    srun
    --mpi=pmix
    --export=ALL,OMPI_MCA_psec=^munge
    ./nbody
)

mapfile -t config_lines < "$CONFIG_FILE_PATH"

for line in "${config_lines[@]}"; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    read -r -a line_args <<< "$line"

    echo ""
    echo "Running command:"
    printf '    %q ' "${COMMAND[@]}" "${line_args[@]}"
    echo ""
    echo ""

    "${COMMAND[@]}" "${line_args[@]}"
done

# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 4000 50
# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 6000 75
# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 9000 100
# srun --mpi=pmix --export=ALL,OMPI_MCA_psec=^munge ./nbody 12000 100

echo "N-body benchmark completed."