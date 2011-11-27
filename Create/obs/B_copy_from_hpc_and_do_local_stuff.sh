#!/bin/bash

outdir="/localhome/Databases/temp/cwb"
dbname="bnc_utf8.db"


./08b_copy_from_hpc.sh $outdir && \
./08c_mergecount.sh $outdir && \
./09a_compile_index.pl $outdir && \
./09b_add_ngram_frequencies.pl $outdir $dbname && \
./09c_compile_ngram_index.pl $outdir
