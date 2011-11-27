#!/bin/bash

if [ $# != 1 ]
then
    printf "[%s] %s\n" $(date "+%T") "./08c_mergecount.sh outdir"
    exit -1
fi

if [ ! -d $1 ]
then
    printf "[%s] %s\n" $(date "+%T") "Not a directory"
    exit -1
fi

dir=$1

cd "$dir/types2ngrams"

printf "[%s] %s\n" $(date "+%T") "Start..."

sort -S 512M -T . -n -m -k1,1 -k2,2 -k3,3 -k4,4 ?-???.txt | uniq -c | perl -ne 'chomp;m/^\s*(\d+)\s+(.+)$/;print "$2\t$1\n";' > type_ngram_position_ngfreq_freq.uniq

printf "[%s] %s\n" $(date "+%T") "Finished"
