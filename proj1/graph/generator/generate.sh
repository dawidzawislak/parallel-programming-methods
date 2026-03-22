#!/bin/bash

declare -a nodes=(4096 8192 32768 65536)
declare -a edges=(32768 131072 524288 1048576)

for i in ${!nodes[@]}; do
    N=${nodes[i]}
    E=${edges[i]}
    outfile="graphs/graph$((i+1)).txt"
    echo "Generating graph $outfile: N=$N, E=$E"
    ./gen_rmat $N $E $outfile
done