#!/bin/bash

if [ $# -ne 2 ]
then
    echo "./10_count_subgraphs.sh outdir max_n"
    exit -1
fi

outdir=$1
max_n=$2

# http://www.admon.org/about-cpu-the-logical-and-physical-cores/
# CPU packages (may contain one or more processor cores)
packages=$(grep "^physical id" /proc/cpuinfo | sort | uniq | wc -l)
# cores for each CPU
cores_per_cpu=$(grep -m1 "cpu cores" /proc/cpuinfo | cut -d' ' -f3)
cores=$(( $packages * $cores_per_cpu ))

cd $outdir

for (( n=0 ; n<=$max_n ; n++))
do
    keys=""
    n_square=$(( $n ** 2 ))
    for (( i=0 ; i<=$n_square ; i++))
    do
	keys="$keys -k$i,$i"
    done
    printf "[%s] %s\n" $(date "+%T") "Sort subgraphs_*_$n"
    sort -S 50% --parallel=$cores -T $outdir $keys subgraphs_*_$n.txt | uniq -c > subgraphs_$n.uniq
    printf "[%s] %s\n" $(date "+%T") "Make frequency the last column"
    perl -i -pe 's/^\s*(\d+)\s+(.+)$/$2\t$1/' subgraphs_$n.uniq
    rm subgraphs_*_$n.txt
done
