#!/bin/bash
#SBATCH --job-name=pcj_bench
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=24:00:00
#SBATCH --partition=plgrid
#SBATCH --account=plgmpr26-cpu

# Załaduj Javę
module load java/11

TEMP_DIR="$(pwd)/temp"
mkdir -p "$TEMP_DIR"
echo "Using temporary directory: $TEMP_DIR"

PCJ_NODES_FILE="${TEMP_DIR}/pcj_nodes_${SLURM_JOB_ID}.txt"
RAW_NODES_FILE="${TEMP_DIR}/raw_nodes_${SLURM_JOB_ID}.txt"
touch $RAW_NODES_FILE $PCJ_NODES_FILE
    
# Generowanie pliku z węzłami (tak jak poprzednio)
scontrol show hostnames $SLURM_JOB_NODELIST > $RAW_NODES_FILE
> $PCJ_NODES_FILE
for node in $(cat $RAW_NODES_FILE); do
    for ((i=0; i<$SLURM_CPUS_PER_TASK; i++)); do
        echo $node >> $PCJ_NODES_FILE
    done
done

MY_IP=$(hostname -i | awk '{print $1}')

# Uruchomienie benchmarków
# Pamiętaj: -cp musi zawierać pcj.jar i bieżący katalog (.)

CONFIG_DIR_PATH=$1
COMMAND=(
    srun
    java
    "-Dpcj.network.address=$MY_IP"
    -cp
    "pcj.jar:."
    Graph500FromFile
    "$PCJ_NODES_FILE"
)

for graph_file in "$CONFIG_DIR_PATH"/graph*.txt; do
    
    echo ""
    echo "Running command:"
    printf '    %q ' "${COMMAND[@]}" "$graph_file" 0
    echo ""

    "${COMMAND[@]}" "$graph_file" 0
done

# srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph1.txt 0
# srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph2.txt 0
# srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph3.txt 0
# srun java -Dpcj.network.address=$MY_IP -cp pcj.jar:. Graph500FromFile pcj_nodes.txt ../proj1/graph/generator/graphs/graph4.txt 0

echo "Graph benchmark completed."

rm -f $RAW_NODES_FILE $PCJ_NODES_FILE