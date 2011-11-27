#!/bin/bash

# Encode BNC vertical files in CWB binary format
# input: BNC vertical files from 01_*
# output: registered CWB encoded corpus

if [ $# != 5 ]
then
    printf "[%s] %s\n" $(date "+%T") "./02a_cwb-encode.sh corpus-indir corpus-outdir registry-file corpus-name outdir"
    exit -1
fi

if [ ! -d $1 -o ! -d $2 -o ! -d $5 ]
then
    printf "[%s] %s\n" $(date "+%T") "Not a directory"
    exit -1
fi

corpus=$1
data=$2
regfile=$3
name=$4
outdir=$5
registry="/localhome/Databases/CWB/registry"
files=

export CORPUS_REGISTRY="$registry"

for file in $corpus/*.vrt
do
    files="$files -f $file"
done
printf "[%s] %s\n" $(date "+%T") "Encoding the corpus"
cwb-encode -d $data $files -R "$registry/$regfile" -xsB -P lemma -P c5 -P wc -S file:0+name -S s:0+id+len
printf "[%s] %s\n" $(date "+%T") "Indexing and compressing the corpus"
cwb-make -M 500 -V "$name"
#printf "[%s] %s\n" $(date "+%T") "Exporting sentence positions"
#cwb-s-decode -r $registry $name -S s > "$outdir/${regfile}_s.txt"
printf "[%s] %s\n" $(date "+%T") "... done"
