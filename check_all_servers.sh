#!/bin/bash

for nr in $(seq 14 35)
do
    echo "clue$nr"
    perl check_server.pl "clue$nr" 4878
done
