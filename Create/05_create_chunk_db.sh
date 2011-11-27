#!/bin/bash

# create an empty SQLite database for chunk information

if [ $# -ne 2 ]
then
    echo "./05_create_chunk_db.sh outdir dbname"
    exit -1
fi

if [ -e "$1/$2" ]
then
    echo "File $1/$2 already exists!"
    exit -1
fi

echo "Create SQLite database '$1/$2'"

echo "Create table 'chunks'"
sqlite3 "$1/$2" 'CREATE TABLE chunks (
    chunkid INTEGER PRIMARY KEY,
    chunk VARCHAR(5) NOT NULL,
    frequency INTEGER NOT NULL,
    UNIQUE (chunk)
);'

echo "Create table 'sentences'"
sqlite3 "$1/$2" 'CREATE TABLE sentences (
    cpos INTEGER PRIMARY KEY,
    chunkseq TEXT NOT NULL,
    cposseq TEXT NOT NULL
);'

echo "You can now insert data into the database."
