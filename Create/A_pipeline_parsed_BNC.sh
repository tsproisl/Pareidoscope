#!/bin/bash

outdir="/localhome/Databases/temp/cwb/bnc_parsed"
corpus="/localhome/Corpora/BNC_parsed/bnc_parsed_1_6_9.xml.out"
corpusoutdir="/localhome/Databases/CWB/bnc_parsed"
corpusname="BNC_PARSED"
registryfile="bnc_parsed"
dbname="bnc_parsed.sqlite"
tagset="penn"
# maximal number of nodes in dependency subgraphs
max_n=5

export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5:/home/linguistik/tsproisl/local/lib/perl5/site_perl:$PERL5LIB"

#./01_cwb-encode_treebank.sh $corpus $corpusoutdir $registryfile $corpusname $outdir && \
#./03_fill_db_collect_ngrams.pl $outdir $corpusname $dbname $registryfile $tagset && \
./04_count_ngrams.sh $outdir "ngrams" && \
./05_create_chunk_db.sh $outdir $dbname && \
./06_collect_chunks_fill_db.pl $outdir $corpusname $dbname $registryfile && \
./04_count_ngrams.sh $outdir "chunks" && \
./07_compile_ngrams_and_create_index.pl $outdir "ngrams" && \
./07_compile_ngrams_and_create_index.pl $outdir "chunks" && \
./08_tabulate_dependencies.pl $outdir $corpusname $dbname && \
./09_create_batch_jobs.sh $outdir $max_n

printf "[%s] %s\n" $(date "+%T") "Now we need to use the cluster!"
