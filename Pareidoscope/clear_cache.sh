#!/bin/bash

find public/cache/ -type f -not -name 'queries.log' -print0 | xargs -0 rm
