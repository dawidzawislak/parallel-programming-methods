#!/bin/bash
#SBATCH --job-name=pcj_bench
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid
#SBATCH --account=plgmpr26-cpu

# Załaduj Javę
module load java/11

# Generowanie pliku z węzłami (tak jak poprzednio)
scontrol show hostnames $SLURM_JOB_NODELIST > raw_nodes.txt
> pcj_nodes.txt
for node in $(cat raw_nodes.txt); do
    for ((i=0; i<$SLURM_CPUS_PER_TASK; i++)); do
        echo $node >> pcj_nodes.txt
    done
done

MY_IP=$(hostname -i | awk '{print $1}')

# Uruchomienie benchmarków
# Pamiętaj: -cp musi zawierać pcj.jar i bieżący katalog (.)
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500 pcj_nodes.txt 1048576 32
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. MolDyn pcj_nodes.txt 131072 100
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. MonteCarlo pcj_nodes.txt 1000000
srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph1.txt 0