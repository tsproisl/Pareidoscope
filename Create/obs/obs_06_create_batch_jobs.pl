#!/usr/bin/perl

# create jobs for HPC system
# input: hashdumps, split sentences
# output: enqueue.sh, jobs

use warnings;
use strict;

die("./06_create_batch_jobs.sh outdir") unless(scalar(@ARGV) == 1);
my $dir = shift(@ARGV);
die("Not a directory: $dir") unless(-d $dir);

my @bnctexts = <$dir/bncsentences/x*.bz2>;
my @hashdumps = <$dir/hashdumps/*.hash.bz2>;

my $anzahl = 3;

open(A, ">batch/enqueue.sh") or die("Cannot open: $!");

my $i = 0;
foreach my $bnctext (@bnctexts){
    my $bncbase;
    $bnctext =~ m{/([^/]+\.bz2)$};
    $bncbase = $1;
    $i++;
    my $j = 0;
    my @hashes = @hashdumps;
    my @hashbases;
    #foreach my $hashdump (@hashdumps){
    while(scalar(@hashes)){
	my $hashdump = shift(@hashes);
	my $hashbase;
	$hashdump =~ m{/([^/]+\.hash\.bz2)$};
	$hashbase = $1;
	push(@hashbases, $hashbase);
	if((scalar(@hashbases) == $anzahl) or (scalar(@hashes) == 0)){
	    $j++;
	    my $i1 = sprintf("%01d", $i);
	    my $j3 = sprintf("%03d", $j);
	    my $hbs = join("\n", map("cp /wsfs/slli/slli02/idx/$_ .\nbunzip2 $_", @hashbases));
	    undef(@hashbases);
	    print A sprintf("qsub -N job%s-%s -q serial -M tsproisl\@linguistik.uni-erlangen.de -m a /home/rrze/slli/slli02/cwb_types2ngrams/jobs/job%s-%s.sh\n", $i1, $j3, $i1, $j3);
	    open(B, ">batch/jobs/job$i1-$j3.sh") or die("Cannot open: $!");
	    print B
"#!/bin/bash -l
# eine CPU fuer 1h anfordern
#PBS -l nodes=1,walltime=01:00:00
TMP=/scratch/\${USER}/\${PBS_JOBID}
mkdir -p \$TMP
cd \$TMP
cp /wsfs/slli/slli02/bnc/$bncbase .
if  [ ! -e $bncbase ]
then
    echo 'Could not copy $bncbase. Aborting' >&2
    exit -1
fi
bunzip2 $bncbase
$hbs
/home/rrze/slli/slli02/cwb_types2ngrams/07_types2ngrams_batch.pl $i1 $j3 \$TMP
sort -n -T \$TMP -k1,1 -k2,2 -k3,3 -k4,4 $i1-$j3.txt > $i1-$j3.sort
mv $i1-$j3.sort $i1-$j3.txt
bzip2 $i1-$j3.txt
sleep 1
cd /wsfs/slli/slli02/out
mv \$TMP/$i1-$j3.txt.bz2 .
rm -rf \$TMP
";
	    close(B) or die("Cannot close: $!");
	}
    }
}
