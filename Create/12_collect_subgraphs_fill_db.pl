#!/usr/bin/perl

# Determine in how many subgraphs a word form occurs
# input: Hashdumps from the cluster (subgraphs_*.dump)
# output: more data in the database

use warnings;
use strict;
use open qw(:std :utf8);

use Carp;
use common_functions;
use DBI;
use Storable;
use List::Util qw(sum);
use List::MoreUtils qw(uniq);

croak("./12_collect_subgraphs_fill_db.pl outdir dbname dump [dump ...]") unless ( scalar(@ARGV) >= 3 );
my $outdir  = shift(@ARGV);
my $dbname  = shift(@ARGV);
croak("Not a directory: $outdir") unless ( -d $outdir );

my $maxloglevel = 3;

my %subgraphs;
my @dumps = map {Storable::retrieve($_)} @ARGV;
for my $word_form (uniq(map {keys %{$_}} @dumps)){
    $subgraphs{$word_form} = sum(map {$_->{$word_form} || 0} @dumps);
}
common_functions::log( "N (Perl) = " . sum(values %subgraphs), 1, $maxloglevel );

my $dbh         = DBI->connect("dbi:SQLite:$outdir/$dbname") or croak("Cannot connect: $DBI::errstr");
$dbh->do(qq{PRAGMA encoding = 'UTF-8'});
$dbh->do(qq{DROP TABLE IF EXISTS depseqs});
$dbh->do(qq{CREATE TABLE depseqs (type TEXT NOT NULL, lowertype TEXT NOT NULL, depseq INTEGER NOT NULL, UNIQUE (type))});
$dbh->do(qq{CREATE INDEX lowertypedepsidx ON depseqs (lowertype)});
my $insert_depseq = $dbh->prepare(qq{INSERT INTO depseqs (type, lowertype, depseq) VALUES (?, ?, ?)});
$dbh->do(qq{BEGIN TRANSACTION});
while (my ($type, $depseq) = each %subgraphs) {
    $insert_depseq->execute($type, lc $type, $depseq);
}
$dbh->do(qq{COMMIT});
$dbh->disconnect();
common_functions::log( "Finished", 1, $maxloglevel );
