#!/bin/bash

chunker=../../../Derived/Chunker/chunklink_2-2-2000_for_conll_tsproisl.pl
lemmatizer=../../../Derived/Lemmatizer/lemmatizer.pl
stan=../../../Software/stanford-parser-2010-11-30/

printf "[%s] %s\n" $(date "+%T") "Create dependencies"
java -mx2g -cp "$stan/stanford-parser.jar:" edu.stanford.nlp.trees.EnglishGrammaticalStructure -treeFile $1 -CCProcessed > $1.deps
printf "[%s] %s\n" $(date "+%T") "Create chunks and convert to xml"
perl $chunker $1 | \
perl -ne 's/\s+/\t/g; print $_ . "\n" if($. > 2);' | \
awk '{print $6"\t"$5"\t"$4"\t"$7}' | \
perl columns_to_xml.pl > $1.xml
printf "[%s] %s\n" $(date "+%T") "Add heads"
perl add_heads.pl $1.xml > $1.xml.new
mv $1.xml.new $1.xml
cd ../../../Derived/Lemmatizer
printf "[%s] %s\n" $(date "+%T") "Lemmatize"
perl lemmatizer.pl -T penn $1.xml
cd  ../../Databases/CWB/Create
printf "[%s] %s\n" $(date "+%T") "Add dependencies"
perl add_dependencies.pl $1.xml.lem $1.deps > $1.xml.lem.deps
printf "[%s] %s\n" $(date "+%T") "Remove temporary files"
rm $1.xml $1.deps
printf "[%s] %s\n" $(date "+%T") "Done"
