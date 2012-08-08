#!/bin/bash

find public/cache/ -type f -not -wholename '*.svn*' -a -not -name 'queries.log' -print0 | xargs -0 rm
