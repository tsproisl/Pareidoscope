#!/bin/bash

outdir="/localhome/Databases/temp/cwb/bnc_parsed"
corpus="/localhome/Corpora/BNC_parsed/bnc_parsed_1_6_9.xml.out"
corpusoutdir="/localhome/Databases/CWB/bnc_parsed"
corpusname="BNC_PARSED"
registryfile="bnc_parsed"
dbname="bnc_parsed.sqlite"
# maximal number of nodes in dependency subgraphs
max_n=5

export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5:/home/linguistik/tsproisl/local/lib/perl5/site_perl:$PERL5LIB"

./10_count_subgraphs.sh $outdir $max_n && \
./11_compile_subgraphs_and_create_index.pl $outdir $max_n
