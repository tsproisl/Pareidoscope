#!/usr/bin/perl

use warnings;
use strict;

# für OANC: 10 Jobs à 3 Stunden

my $jobnr = sprintf("%03d", $nr);
my $hashdump;
my $infiles;
my $max_n;

print "#!/bin/bash -l
#
# allocate 1 node (4 CPUs) for 3 hours
#PBS -l nodes=1:ppn=4,walltime=03:00:00
#
# job name 
#PBS -N Subgraphjob_$jobnr
#
# stdout and stderr files
#PBS -o job${jobnr}.out -e job${jobnr}.err
#
# first non-empty non-comment line ends PBS options

cd \$TMPDIR
cp $hashdump $infiles .

for (( i=0 ; i < 4 ; i++ ))
do
    perl hpc_01_collect_dependency_subgraphs.pl $infiles[\$i] $hashdump subgraphs_${jobnr}_\$i.txt $max_n &
done

# Don't execute the next command until subshells finish.
wait

for (( i=1 ; i <= $max_n ; i++ ))
do
    grep \"\t\$i\$\" subgraphs_${jobnr}_*.txt > \$FASTTMP/subgraphs_${jobnr}_\$i.txt &
done

wait

rm $infiles subgraphs_${jobnr}_*.txt
";
