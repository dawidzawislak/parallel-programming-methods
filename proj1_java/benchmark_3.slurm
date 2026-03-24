#!/bin/bash
#SBATCH --job-name=pcj_bench
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=2
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid
#SBATCH --account=plgmpr26-cpu

BENCHMARK_NUMBER=$1
GRAPH_NUMBER=$2

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

if [[ "$BENCHMARK_NUMBER" == "1" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph1.txt 0
elif [[ "$BENCHMARK_NUMBER" == "2" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph2.txt 0
elif [[ "$BENCHMARK_NUMBER" == "3" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph3.txt 0
elif [[ "$BENCHMARK_NUMBER" == "4" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph4.txt 0
elif [[ "$BENCHMARK_NUMBER" == "5" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500 pcj_nodes.txt 1048576 32
elif [[ "$BENCHMARK_NUMBER" == "6" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. MolDyn pcj_nodes.txt 131072 100
elif [[ "$BENCHMARK_NUMBER" == "7" ]]; then
    srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. MonteCarlo pcj_nodes.txt 1000000
else
    echo "Invalid benchmark number: $BENCHMARK_NUMBER"
    echo "Usage: sbatch benchmark_easy.slurm <benchmark_number>"
    echo "Benchmark numbers:"
    echo "  1: graph1.txt"
    echo "  2: graph2.txt"
    echo "  3: graph3.txt"
    echo "  4: graph4.txt"
    echo "  5: Graph500 synthetic benchmark"
    echo "  6: Molecular Dynamics benchmark"
    echo "  7: Monte Carlo benchmark"
fi
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500 pcj_nodes.txt 1048576 32
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. MolDyn pcj_nodes.txt 131072 100
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. MonteCarlo pcj_nodes.txt 1000000
#srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph1.txt 0