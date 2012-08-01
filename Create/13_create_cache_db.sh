#!/bin/bash

# create an empty SQLite database for lemma and type information

if [ $# -ne 2 ]
then
    echo "./13_create_cache_db.sh outdir dbname"
    exit -1
fi

if [ -e "$1/$2" ]
then
    echo "File $1/$2 already exists!"
    exit -1
fi

echo "Create SQLite database '$1/$2'"

echo "Create table 'queries'"
sqlite3 "$1/$2" 'CREATE TABLE queries (
    qid INTEGER PRIMARY KEY,
    corpus TEXT NOT NULL,
    class VARCHAR(10) NOT NULL,
    query TEXT NOT NULL,
    qlen INTEGER NOT NULL,
    time INTEGER NOT NULL,
    r1 INTEGER NOT NULL,
    n INTEGER NOT NULL,
    UNIQUE (corpus, class, query)
);'
# class: 
# struc  results contain structural data, e.g. n-grams
# lex    results contain lexical data

#echo "Create table 'results'"
#sqlite3 "$1/$2" 'CREATE TABLE results (
#    rid INTEGER PRIMARY KEY,
#    qid INTEGER NOT NULL,
#    result TEXT NOT NULL,
#    position INTEGER NOT NULL,
#    o11 INTEGER NOT NULL,
#    c1 INTEGER NOT NULL,
#    g2 INTEGER,
#    dice INTEGER,
#    FOREIGN KEY (qid) REFERENCES queries (qid) ON DELETE CASCADE,
#    UNIQUE (qid, result, position)
#);'

echo "Create trigger 'clean'"
#sqlite3 "$1/$2" 'CREATE TRIGGER clean INSERT ON queries BEGIN DELETE FROM queries WHERE time < new.time - 43200; END;'
#sqlite3 "$1/$2" 'CREATE TRIGGER clean INSERT ON queries BEGIN rmfile(SELECT qid FROM queries WHERE time < new.time - 43200); DELETE FROM queries WHERE time < new.time - 43200; END;'
sqlite3 "$1/$2" 'CREATE TRIGGER clean AFTER INSERT ON queries BEGIN SELECT logquery(class, query, datetime(time, "unixepoch", "localtime")) FROM queries WHERE qid = new.qid; SELECT rmfile(qid) FROM queries WHERE time < new.time - 1800; DELETE FROM queries WHERE time < new.time - 1800; END;'

#echo "Create index 'lemididx'"
#sqlite3 "$1/$2" 'CREATE INDEX lemididx ON types (lemid);'

echo "You can now insert data into the database."
