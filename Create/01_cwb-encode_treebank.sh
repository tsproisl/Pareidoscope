#!/bin/bash

# Encode XML file in CWB binary format
# input: Chunked and lemmatized XML file
# output: registered CWB encoded corpus

if [ $# != 5 ]
then
    printf "[%s] %s\n" $(date "+%T") "./01_cwb-encode_treebank.sh corpus corpus-outdir registry-file corpus-name outdir"
    exit -1
fi

if [ ! -f $1 -o ! -d $2 -o ! -d $5 ]
then
    printf "[%s] %s\n" $(date "+%T") "Not a directory or file"
    exit -1
fi

corpus=$1
data=$2
regfile=$3
name=$4
outdir=$5
registry="/localhome/Databases/CWB/registry"

export CORPUS_REGISTRY="$registry"
export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5/site_perl"

printf "[%s] %s\n" $(date "+%T") "Encoding the corpus"
cwb-encode -d $data -f $corpus -R "$registry/$regfile" -xsB -P pos -P lemma -P wc -P indep -P outdep -P root -S s:0+id+id_md5_base64+original_id+len -S adjp:0 -S advp:0 -S conjp:0 -S intj:0 -S lst:0 -S np:0 -S o:0 -S pp:0 -S prt:0 -S qp:0 -S sbar:0 -S ucp:0 -S vp:0 -S h:0 -S text:0+id+original_id -0 corpus
printf "[%s] %s\n" $(date "+%T") "Indexing and compressing the corpus"
cwb-make -M 500 -V "$name"
printf "[%s] %s\n" $(date "+%T") "... done"
