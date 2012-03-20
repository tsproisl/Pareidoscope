#!/bin/bash

outdir="/localhome/Databases/temp/cwb/oanc"
subgraphdir="/localhome/Databases/temp/cwb/oanc/subgraphs"
corpus="/localhome/Corpora/OANC/oanc_parsed_1_6_9.xml.out"
corpusoutdir="/localhome/Databases/CWB/oanc"
corpusname="OANC"
registryfile="oanc"
dbname="oanc.sqlite"
# maximal number of nodes in dependency subgraphs
max_n=5

export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5:/home/linguistik/tsproisl/local/lib/perl5/site_perl:$PERL5LIB"

./10_count_subgraphs.sh $subgraphdir $max_n && \
./11_compile_subgraphs_and_create_index.pl $subgraphdir $max_n
