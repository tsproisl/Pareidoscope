#!/bin/bash

# copy files to HPC system
# input: hashdumps, split sentences

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

printf "[%s] %s\n" $(date "+%T") "Compress hashdumps"
for dump in $dir/hashdumps/*.hash
do
    bzip2 $dump
done
printf "[%s] %s\n" $(date "+%T") "Done"

scp 07_types2ngrams_batch.pl $hpc:~/cwb_types2ngrams/.
scp -r batch/* $hpc:~/cwb_types2ngrams/.
scp $dir/bncsentences/*.bz2 $hpc:/data/wsfs/slli/slli02/bnc/.
scp $dir/hashdumps/*.bz2 $hpc:/data/wsfs/slli/slli02/idx/.

printf "[%s] %s\n" $(date "+%T") "You can now start enqueue.sh on the HPC system"
