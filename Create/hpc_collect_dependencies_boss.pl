#!/usr/bin/perl

use warnings;
use strict;

use lib "/home/hpc/slli/slli02/localbin/lib/perl/5.10.0";
use DBI;

die("./hpc_collect_dependencies_boss.pl SENTENCE_DB DATA_DIRECTORY DB") unless(@ARGV == 3);
my $database = shift(@ARGV);
my $directory = shift(@ARGV);
my $info_db = shift(@ARGV);

my $dbh = DBI->connect("dbi:SQLite:$database") or die("Cannot connect: $DBI::errstr");

$dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
my $get_unfinished_sentences  = $dbh->prepare(qq{SELECT count(sid) FROM sentences WHERE status != 4 AND status != 6});
my $get_virgin_sentences      = $dbh->prepare(qq{SELECT sid FROM sentences WHERE status = 0 LIMIT 500});
my $get_interrupted_sentences = $dbh->prepare(qq{SELECT sid FROM sentences WHERE status = 5 LIMIT 10});
my $set_status                = $dbh->prepare(qq{UPDATE sentences SET status = ? WHERE sid = ?});
$dbh->do(qq{COMMIT});

my $normal_job_counter      = 0;
my $interrupted_job_counter = 0;

while ( &are_there_unfinished_jobs() ) {
    &start_normal_jobs();
    &start_interrupted_jobs();
    print "One round done\n";
    sleep(300);
}

$dbh->disconnect();

sub are_there_unfinished_jobs {
    $get_unfinished_sentences->execute();
    return ( $get_unfinished_sentences->fetchrow_array() )[0];
}

sub start_normal_jobs {
    print "Look for status == 0\n";
    while (1) {
	$dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
        $get_virgin_sentences->execute();
        my $resultsref = $get_virgin_sentences->fetchall_arrayref();
        if ( scalar(@$resultsref) == 0 ) {
	    $dbh->do(qq{COMMIT});
	    return;
	}
        $normal_job_counter++;
	my $jobname = sprintf("%06d.sh", $normal_job_counter);
	my @sids = map($_->[0], @$resultsref);
	my $sids = join(" ", @sids);
	foreach my $sid (@sids) {
	    $set_status->execute(1, $sid);
	}
	open(my $fh, ">", "$directory/jobs/$jobname") or die("Cannot open $directory/jobs/$jobname: $!");
	print $fh "#!/bin/bash -l
#
# eine CPU fuer 10min anfordern
#
#PBS -l nodes=1,walltime=00:10:00
#
# erste nichtleere Zeile ohne Kommentar: Start!

PFAD=/home/woody/slli/slli02

# SIGTERM abfangen, im Handler scratch-Verzeichnis retten
trap \"sleep 5 ; cd \$PFAD/collect_dependencies ; ./hpc_clear_normal_jobs.pl $database $directory $sids ; exit\" 15

# ... ab hier beginnt das eigentliche Jobskript
cd \$PFAD/collect_dependencies
./hpc_collect_dependencies_worker.pl $database $directory $info_db $sids
";
	close($fh) or die("Cannot close $directory/jobs/$jobname: $!");
	$dbh->do(qq{COMMIT});
	print "Submit $jobname\n";
	system("qsub -q serial -N $jobname < $directory/jobs/$jobname");
    }
    print "Done\n";
}

sub start_interrupted_jobs {
    print "Look for status == 5\n";
    while (1) {
	$dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
	$get_interrupted_sentences->execute();
	my $resultsref = $get_interrupted_sentences->fetchall_arrayref();
        if ( scalar(@$resultsref) == 0 ) {
	    $dbh->do(qq{COMMIT});
	    return;
	}
	my @sids = map($_->[0], @$resultsref);
	my @jobnames;
	foreach my $sid (@sids) {
	    $set_status->execute(1, $sid);
	    $interrupted_job_counter++;
	    my $jobname = sprintf("i%06d.sh", $interrupted_job_counter);
	    push(@jobnames, $jobname);
	    open(my $fh, ">", "$directory/jobs/$jobname") or die("Cannot open $directory/jobs/$jobname: $!");
	    print $fh "#!/bin/bash -l
#
# eine CPU fuer 6h anfordern
#
#PBS -l nodes=1,walltime=06:00:00
#
# erste nichtleere Zeile ohne Kommentar: Start!

PFAD=/home/woody/slli/slli02

# SIGTERM abfangen, im Handler scratch-Verzeichnis retten
trap \"sleep 5 ; cd \$PFAD/collect_dependencies ; ./hpc_clear_interrupted_jobs.pl $database $directory $sid ; exit\" 15

# ... ab hier beginnt das eigentliche Jobskript
cd \$PFAD/collect_dependencies
./hpc_collect_dependencies_worker.pl $database $directory $info_db $sid
";
	    close($fh) or die("Cannot close $directory/jobs/$jobname: $!");
	}
        $dbh->do(qq{COMMIT});
	foreach my $jobname (@jobnames) {
	    print "Submit $jobname\n";
	    system("qsub -q serial -N $jobname < $directory/jobs/$jobname");
	}
    }
    print "Done\n";
}
