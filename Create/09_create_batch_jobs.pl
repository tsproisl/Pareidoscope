#!/usr/bin/perl

use warnings;
use strict;

# für OANC: 10 Jobs à 3 Stunden

die("./hpc_01_collect_dependency_subgraphs.pl dependencies.out dependency_relations.dump max_n") unless ( scalar(@ARGV) == 3 );
my $dependencies = shift(@ARGV);
my $relations    = shift(@ARGV);
my $max_n        = shift(@ARGV);

my $nr = 5;
my $jobnr = sprintf("%03d", $nr);
my $infiles;

#open(JOB, ">:encoding(utf8)", "subgraphjob_$jobnr") or die("Cannot open subgraphjob_$jobnr: $!");

print "#!/bin/bash -l
#
# allocate 1 node (4 CPUs) for 3 hours
# sufficient for 100,000 sentences
#PBS -l nodes=1:ppn=4,walltime=03:00:00
#
# job name 
#PBS -N subgraphjob_$jobnr
#
# stdout and stderr files
#PBS -o job${jobnr}.out -e job${jobnr}.err
#
# first non-empty non-comment line ends PBS options

files=($infiles)
cd \$TMPDIR
cp $relations $infiles .

for (( i=0 ; i < \${#files[@]} ; i++ ))
do
    perl hpc_01_collect_dependency_subgraphs.pl \${files[\$i]} $relations subgraphs_${jobnr}_\$i.txt $max_n &
done

# Don't execute the next command until subshells finish.
wait

for (( i=1 ; i <= $max_n ; i++ ))
do
    grep \"\\t\$i\$\" subgraphs_${jobnr}_*.txt > \$FASTTMP/subgraphs_${jobnr}_\$i.txt &
done

wait

rm $infiles subgraphs_${jobnr}_*.txt
";
