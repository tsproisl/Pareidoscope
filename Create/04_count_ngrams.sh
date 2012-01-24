#!/bin/bash

# sort and count the ngrams
# input: ngrams.out
# output: ngrams.out.uniq

dir=$1
file=$2
filepath="$dir/$file.out"

if [ $(head -n 1 $filepath | grep -c -P '\t') -ne 1 ]
then
    echo "This script was written for files with two tab-seperated columns"
    exit -1;
fi

# http://www.admon.org/about-cpu-the-logical-and-physical-cores/
# CPU packages (may contain one or more processor cores)
packages=$(grep "^physical id" /proc/cpuinfo | sort | uniq | wc -l)
# cores for each CPU
cores_per_cpu=$(grep -m1 "cpu cores" /proc/cpuinfo | cut -d' ' -f3)
cores=$(( $packages * $cores_per_cpu ))

printf "[%s] %s\n" $(date "+%T") "Sort $filepath"
sort -S 50% --parallel=$core -T $dir -t ' ' -n -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 -k6,6 -k7,7 -k8,8 -k9,9 $filepath | uniq -c > $filepath.uniq

printf "[%s] %s\n" $(date "+%T") "Make frequency the last column"
perl -i -pe 's/^\s*(\d+)\s+(.+)$/$2\t$1/' $filepath.uniq
#cat $filepath.uniqa | perl -ne 'chomp;m/^\s*(\d+)\s+(.+)$/;print "$2\t$1\n";' > $filepath.uniq
#rm $filepath.uniqa

printf "[%s] %s\n" $(date "+%T") "Determine N"
n=$(awk '{ SUM += ($2*$3)} END { print SUM }' $filepath.uniq)
printf "[%s] %s\n" $(date "+%T") "N = $n"
printf "[%s] %s\n" $(date "+%T") "$file N = $n" >> logfile.txt

printf "[%s] %s\n" $(date "+%T") "Remove hapax patterns"
egrep -v '\t1\t' $filepath.uniq > $filepath.uniq.filtered
printf "[%s] %s\n" $(date "+%T") "Finished"
