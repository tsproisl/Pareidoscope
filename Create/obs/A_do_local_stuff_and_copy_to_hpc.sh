#!/bin/bash

#outdir="/localhome/Databases/temp/cwb"
outdir="/localhome/Databases/temp/cwb/wiki005"
#corpusindir="/localhome/Corpora/BNC_vrt"
corpusindir="/localhome/Corpora/wikipedia_en_20100312"
#corpusoutdir="/localhome/Databases/CWB/bnc"
corpusoutdir="/localhome/Databases/CWB/wiki005"
#corpusname="BNC_UTF8"
corpusname="WIKI005"
#registryfile="bnc_utf8"
registryfile="wiki005"
#dbname="bnc_utf8.db"
dbname="wiki005.db"

#./02a_cwb-encode_wiki.sh $corpusindir $corpusoutdir $registryfile $corpusname $outdir && \
./02b_create_sqlite_db.sh $outdir $dbname && \
./03a_create_indexes.pl $outdir $corpusname $dbname $registryfile && \
./04_sort_uniq-c.sh $outdir && \
./09c_compile_ngram_index.pl $outdir && \
./09d_create_ngrams_index.pl $outdir

# not needed anymore:
##./05a_create_ngram_hash_dumps.pl $outdir $dbname && \
##./05c_split_pack_sentences.sh $outdir && \
##./06_create_batch_jobs.pl $outdir && \
##./08a_copy_to_hpc.sh $outdir
