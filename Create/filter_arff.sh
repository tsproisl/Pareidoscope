#!/bin/bash

head -n 403 ANC_MASC_I.arff
tail +404 ANC_MASC_I.arff | egrep "^'$1'"
