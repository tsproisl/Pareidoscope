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

#./01_cwb-encode_treebank.sh $corpus $corpusoutdir $registryfile $corpusname $outdir && \
#./02_create_sqlite_db.sh $outdir $dbname && \
#./03_fill_db_collect_ngrams.pl $outdir $corpusname $dbname $registryfile && \
#./04_count_ngrams.sh $outdir "ngrams" && \
#./05_create_chunk_db.sh $outdir $chunkdb && \
#./06_collect_chunks_fill_db.pl $outdir $corpusname $dbname $chunkdb $registryfile && \
#./04_count_ngrams.sh $outdir "chunks" && \
#./07_compile_ngrams_and_create_index.pl $outdir "ngrams" && \
#./07_compile_ngrams_and_create_index.pl $outdir "chunks" #&& \
#./08_tabulate_dependencies.pl $outdir $corpusname $dbname && \
./09_create_batch_jobs.sh $outdir $max_n

printf "[%s] %s\n" $(date "+%T") "Now we need to use the cluster!"
