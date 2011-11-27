#!/bin/bash

# copy files from HPC system
# input: list of types and their ngrams

if [ $# != 1 ]
then
    printf "[%s] %s\n" $(date "+%T") "./08a_copy_to_hpc.sh outdir"
    exit -1
fi

if [ ! -d $1 ]
then
    printf "[%s] %s\n" $(date "+%T") "Not a directory"
    exit -1
fi

dir=$1
hpc="slli02@sfront03.rrze.uni-erlangen.de"

scp $hpc:/data/wsfs/slli/slli02/out/* $dir/types2ngrams/.

printf "[%s] %s\n" $(date "+%T") "For your convenience I will now also bunzip2 the files"

cd $dir/types2ngrams
for file in *.bz2
do
    printf "[%s] %s\n" $(date "+%T") "Processing $file"
    bunzip2 $file
done
printf "[%s] %s\n" $(date "+%T") "Finished!"
printf "[%s] %s\n" $(date "+%T") "You can now execute mergecount.sh, i.e. sort -T . -n -m -k1,1 -k2,2 -k3,3 -k4,4 ?-???.txt | uniq -c | perl -ne 'chomp;m/^\s*(\d+)\s+(.+)$/;print \"$2\t$1\n\";' > type_ngram_position_ngfreq_freq.uniq"
