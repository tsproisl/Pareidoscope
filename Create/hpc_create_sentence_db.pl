#!/usr/bin/perl

use warnings;
use strict;

use DBI;
use CWB::CQP;
use CWB::CL;

use common_functions;

my $maxloglevel = 3;

die("./hpc_create_sentence_db.pl outdir corpus-name sentencedbname regfile") unless ( scalar(@ARGV) == 4 );
my $outdir  = shift(@ARGV);
my $corpus  = shift(@ARGV);
my $dbname  = shift(@ARGV);
my $regfile = shift(@ARGV);
die("Not a directory: $outdir") unless ( -d $outdir );

my $dbh = DBI->connect("dbi:SQLite:$outdir/$dbname") or die("Cannot connect: $DBI::errstr");
&common_functions::log( "Create database $outdir/$dbname.", 1, $maxloglevel );
$dbh->do(qq{CREATE TABLE sentences (sid INTEGER PRIMARY KEY, words TEXT, poses TEXT, lemmata TEXT, wcs TEXT, indeps TEXT, outdeps TEXT, positions TEXT, status INTEGER)});
$dbh->do(qq{CREATE INDEX statusidx ON sentences (status)});
my $insert_sentence = $dbh->prepare(qq{INSERT INTO sentences (sid, words, poses, lemmata, wcs, indeps, outdeps, positions, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)});

my $cqp = new CWB::CQP;
$cqp->set_error_handler('die');    # built-in, useful for one-off scripts
$cqp->exec("set Registry '/localhome/Databases/CWB/registry'");
$cqp->exec($corpus);
$CWB::CL::Registry = '/localhome/Databases/CWB/registry';
my $corpus_handle = new CWB::CL::Corpus $corpus;

$cqp->exec("A = <s> [] expand to s");
my ($size) = $cqp->exec("size A");
&common_functions::log( "Finished query. There are $size sentences.", 1, $maxloglevel );
$cqp->exec("tabulate A match s_id, match .. matchend word, match .. matchend pos, match .. matchend lemma, match .. matchend wc, match .. matchend indep, match .. matchend outdep, match .. matchend > \"$outdir/tabulate_dependencies.out\"");
open( TAB, "<:encoding(utf8)", "$outdir/tabulate_dependencies.out" ) or die("Cannot open $outdir/tabulate.out: $!");
&common_functions::log( "Finished tabulating results.", 1, $maxloglevel );

$dbh->do(qq{BEGIN TRANSACTION});
while ( defined( my $match = <TAB> ) ) {
    chomp($match);
    my ( $sid, $words, $poses, $lemmata, $wcs, $indeps, $outdeps, $positions ) = split( /\t/, $match );
    $insert_sentence->execute( $sid, $words, $poses, $lemmata, $wcs, $indeps, $outdeps, $positions, 0 );
}
$dbh->do(qq{COMMIT});

close(TAB) or die("Cannot close $outdir/tabulate_dependencies.out: $!");

$dbh->disconnect();

