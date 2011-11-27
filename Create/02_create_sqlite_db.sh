#!/bin/bash

# create an empty SQLite database for lemma and type information

if [ $# -ne 2 ]
then
    echo "./02_create_sqlite_db.sh outdir dbname"
    exit -1
fi

if [ -e "$1/$2" ]
then
    echo "File $1/$2 already exists!"
    exit -1
fi

echo "Create SQLite database '$1/$2'"

echo "Create table 'lemmata'"
sqlite3 "$1/$2" 'CREATE TABLE lemmata (
    lemid INTEGER PRIMARY KEY,
    lemma VARCHAR(255) NOT NULL,
    wc VARCHAR(10) NOT NULL,
    freq INTEGER NOT NULL,
    UNIQUE (lemma, wc)
);'

echo "Create table 'types'"
sqlite3 "$1/$2" 'CREATE TABLE types (
    typid INTEGER PRIMARY KEY,
    lemid INTEGER NOT NULL,
    type VARCHAR(255) NOT NULL,
    gramid INTEGER NOT NULL,
    freq INTEGER NOT NULL,
    posseq INTEGER,
    chunkseq INTEGER,
    FOREIGN KEY (lemid) REFERENCES lemmata (lemid),
    FOREIGN KEY (gramid) REFERENCES gramis (gramid),
    UNIQUE (type, gramid, lemid)
);'

echo "Create table 'gramis'"
sqlite3 "$1/$2" 'CREATE TABLE gramis (
    gramid INTEGER PRIMARY KEY,
    grami VARCHAR(25) NOT NULL, 
    UNIQUE (grami)
);'

echo "Create index 'lemididx'"
sqlite3 "$1/$2" 'CREATE INDEX lemididx ON types (lemid);'

echo "You can now insert data into the database."
