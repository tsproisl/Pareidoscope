#!/bin/bash

here=$(pwd)
#www=/www/homepages/tsproisl/pareidoscope/devel/user_data
www=/www/homepages/tsproisl/pareidoscope/cgi-bin/user_data
cd $www
ls | egrep '^[[:digit:]]+$' | xargs rm -f
rm -f cache.db
rm -f cache/data/*
rm -f cache/index/*
/localhome/Diss/trunk/Resources/Pareidoscope/Create/12_create_cache_db.sh $www cache.db
chmod 666 cache.db
