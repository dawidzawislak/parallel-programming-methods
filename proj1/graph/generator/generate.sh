#!/bin/bash

declare -a nodes=(100000 500000 1000000 2000000)
declare -a edges=(40000000 200000000 400000000 800000000)

for i in ${!nodes[@]}; do
    N=${nodes[i]}
    E=${edges[i]}
    outfile="../../../run_configs/graphs/graph$((i+1)).txt"
    echo "Generating graph $outfile: N=$N, E=$E"
    ./gen_rmat $N $E $outfile
done