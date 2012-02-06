#!/bin/bash

# create an empty SQLite database for chunk information

if [ $# -ne 2 ]
then
    echo "./05_create_chunk_db.sh outdir dbname"
    exit -1
fi

if [ ! -e "$1/$2" ]
then
    echo "File $1/$2 does not exist!"
    exit -1
fi

printf "[%s] %s\n" $(date "+%T") "Drop table 'chunks'"
sqlite3 "$1/$2" 'DROP TABLE IF EXISTS chunks;'

printf "[%s] %s\n" $(date "+%T") "Create table 'chunks'"
sqlite3 "$1/$2" 'CREATE TABLE chunks (
    chunkid INTEGER PRIMARY KEY,
    chunk VARCHAR(5) NOT NULL,
    frequency INTEGER NOT NULL,
    UNIQUE (chunk)
);'

printf "[%s] %s\n" $(date "+%T") "Drop table 'sentences'"
sqlite3 "$1/$2" 'DROP TABLE IF EXISTS sentences;'

printf "[%s] %s\n" $(date "+%T") "Create table 'sentences'"
sqlite3 "$1/$2" 'CREATE TABLE sentences (
    cpos INTEGER PRIMARY KEY,
    chunkseq TEXT NOT NULL,
    cposseq TEXT NOT NULL
);'

printf "[%s] %s\n" $(date "+%T") "You can now insert data into the database."
