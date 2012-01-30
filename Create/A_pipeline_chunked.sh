#!/bin/bash

outdir="/localhome/Databases/temp/cwb/anc_masc"
corpusindir="/localhome/Corpora/ANC_MASC_I"
corpusoutdir="/localhome/Databases/CWB/anc_masc"
corpusname="ANC_MASC"
registryfile="anc_masc"
dbname="anc_masc.db"
chunkdb="anc_masc_chunks.db"

export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5:/home/linguistik/tsproisl/local/lib/perl5/site_perl:$PERL5LIB"
#export PERL5LIB="/home/linguistik/tsproisl/local/lib/perl5/site_perl:/home/linguistik/tsproisl/local/lib/perl5/site_perl/x86_64-linux-thread-multi"

#./01_cwb-encode.sh $corpusindir $corpusoutdir $registryfile $corpusname $outdir && \
# ./02_create_sqlite_db.sh $outdir $dbname && \
# ./03_fill_db_collect_ngrams.pl $outdir $corpusname $dbname $registryfile && \
# ./04_count_ngrams.sh $outdir "ngrams" && \
# ./05_create_chunk_db.sh $outdir $chunkdb && \
# ./06_collect_chunks_fill_db.pl $outdir $corpusname $dbname $chunkdb $registryfile && \
# ./04_count_ngrams.sh $outdir "chunks" && \
# ./07_compile_ngrams_and_create_index.pl $outdir "ngrams" && \
# ./07_compile_ngrams_and_create_index.pl $outdir "chunks" && \
./08_collect_dependencies.pl $outdir $corpusname $dbname $chunkdb $registryfile