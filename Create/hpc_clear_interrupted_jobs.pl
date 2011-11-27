#!/usr/bin/perl

use warnings;
use strict;

use lib "/home/hpc/slli/slli02/localbin/lib/perl/5.10.0";
use DBI;

my $database  = shift(@ARGV);
my $directory = shift(@ARGV);

my $dbh = DBI->connect("dbi:SQLite:$database") or die("Cannot connect: $DBI::errstr");

$dbh->do("BEGIN IMMEDIATE TRANSACTION");
my $get_unfinished_sentences = $dbh->prepare( "SELECT sid FROM sentences WHERE status=? AND sid IN (" . join( ", ", @ARGV ) . ")" );
my $set_status = $dbh->prepare(qq{UPDATE sentences SET status = ? WHERE sid = ?});
$dbh->do("COMMIT");

$dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
$get_unfinished_sentences->execute(3);
my $sids = $get_unfinished_sentences->fetchall_arrayref();
foreach my $sid ( map( $_->[0], @$sids ) ) {
    $set_status->execute( 6, $sid );
}

$dbh->do("COMMIT");
