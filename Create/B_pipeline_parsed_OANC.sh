#!/bin/bash

outdir="/localhome/Databases/temp/cwb/oanc"
corpus="/localhome/Corpora/OANC/oanc_parsed_1_6_9.xml.out"
corpusoutdir="/localhome/Databases/CWB/oanc"
corpusname="OANC"
registryfile="oanc"
dbname="oanc.db"
chunkdb="oanc_chunks.db"
# maximal number of nodes in dependency subgraphs
max_n=5

export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5/site_perl:/home/linguistik/tsproisl/local/lib/perl5/site_perl/x86_64-linux-thread-multi"

#./10_count_subgraphs.sh $outdir $max_n && \
./11_compile_subgraphs_and_create_index.pl $outdir $max_n
