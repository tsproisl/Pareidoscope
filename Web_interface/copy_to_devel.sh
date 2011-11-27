#!/bin/bash

apache="/srv/www/homepages/tsproisl/pareidoscope/devel"

cp pareidoscope.cgi $apache/.
cp localdata_client.pm $apache/.
cp entities.pm $apache/.
cp statistics.pm $apache/.
cp executequeries.pm $apache/.
cp config.pm $apache/.
cp pareidoscope.conf $apache/.
cp kwic.pm $apache/.
cp Envision.css $apache/../Envision12/.
cp images/*.png $apache/../.
cp templates/*[^~] $apache/.
