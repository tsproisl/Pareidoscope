#!/bin/bash

outdir="/localhome/Databases/temp/cwb/anc_masc"
corpus="/localhome/Corpora/ANC_MASC_I/ANC_MASC_I.xml.out"
corpusoutdir="/localhome/Databases/CWB/anc_masc"
corpusname="ANC_MASC"
registryfile="anc_masc"
dbname="anc_masc.sqlite"
tagset="penn_extended"
# maximal number of nodes in dependency subgraphs
max_n=5

export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5:/home/linguistik/tsproisl/local/lib/perl5/site_perl:$PERL5LIB"

./01_cwb-encode.sh $corpus $corpusoutdir $registryfile $corpusname $outdir && \
./02_create_sqlite_db.sh $outdir $dbname && \
./03_fill_db_collect_ngrams.pl $outdir $corpusname $dbname $registryfile $tagset && \
./04_count_ngrams.sh $outdir "ngrams" && \
./05_create_chunk_db.sh $outdir $dbname && \
./06_collect_chunks_fill_db.pl $outdir $corpusname $dbname $registryfile && \
./04_count_ngrams.sh $outdir "chunks" && \
./07_compile_ngrams_and_create_index.pl $outdir "ngrams" && \
./07_compile_ngrams_and_create_index.pl $outdir "chunks" && \
./08_tabulate_dependencies.pl $outdir $corpusname $dbname && \
./09_create_batch_jobs.sh $outdir $max_n

printf "[%s] %s\n" $(date "+%T") "Now we need to use the cluster!"
