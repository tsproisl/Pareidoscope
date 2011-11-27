#!/bin/bash

# create smaller files with approx. 1.2 mio sentences each
# input: sentences.out
# output split files

if [ $# != 1 ]
then
    printf "[%s] %s\n" $(date "+%T") "./05c_split_pack_sentences.sh outdir"
    exit -1
fi

if [ ! -d $1 ]
then
    printf "[%s] %s\n" $(date "+%T") "Not a directory"
    exit -1
fi

dir=$1

cd $dir
printf "[%s] %s\n" $(date "+%T") "Split file"
split -l 1203399 "$dir/sentences.out"
printf "[%s] %s\n" $(date "+%T") "Compress split files"
for file in x*
do
    bzip2 $file
done
mv x* bncsentences/
printf "[%s] %s\n" $(date "+%T") "Finished"
printf "[%s] %s\n" $(date "+%T") "You can now run 06_*"
