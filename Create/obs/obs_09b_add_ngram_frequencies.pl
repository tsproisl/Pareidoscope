#!/usr/bin/perl

# add information about in how many ngrams a type occurs to SQLite database
# input: binary index and data files
# output: updated database

use warnings;
use strict;
use common_functions;
use DBI;

die("./09b_add_ngram_frequencies outdir dbname") unless(scalar(@ARGV) == 2);
my $dir = shift(@ARGV);
my $dbname = shift(@ARGV);
die("Not a directory: $dir") unless(-d $dir);


open(IDX, "<$dir/index.dat") or die("Cannot open file: $!");
open(DAT, "<$dir/data.dat") or die("Cannot open file: $!");
my $dbh = DBI->connect( "dbi:SQLite:$dir/$dbname" ) or die("Cannot connect: $DBI::errstr");
my $updatengfreq = $dbh->prepare(qq{UPDATE types SET ngfreq=? WHERE typid=?});
$dbh->do(qq{BEGIN TRANSACTION});

my $position = 0;
my $size = length(pack("Q", 0));
my $recordsize = length(pack("LCLL", 0,0,0));
my $buffermax = (1024 * 1024) - ((1024 * 1024) % $recordsize);
seek(IDX, 0, 2) or die("Error while seeking index file");
my $indexsize = tell(IDX) / $size;
&common_functions::log("Index with $indexsize entries", 1, 1);
while($position < $indexsize){
    my $idx_entry;
    seek(IDX, $position*$size, 0) or die("Error while seeking index file");
    my $chrs = read(IDX, $idx_entry, $size*2);
    my $data_offset;
    my $data_size;
    if($chrs == $size*2){
	my ($a, $b) = unpack("QQ", $idx_entry);
	$data_offset = $a;
	$data_size = $b - $a;
    }else{
	$data_offset = unpack("Q", $idx_entry);
	seek(DAT, 0, 2) or die("Error while seeking data file");
	$data_size = tell(DAT) - $data_offset;
    }
    if($data_offset == 1){
	&common_functions::log("Skip $position", 1, 1);
	$position++;
	next;
    }
    my $check;
    my $sum;
    seek(DAT, $data_offset, 0) or die("Error while seeking data file");
    read(DAT, $check, length(pack("L", 0)));
    ($check) = unpack("L", $check);
    die("Some miscalculation occured: $position != $check") unless($position == $check - 1);
    my $datpos = tell(DAT);
    #&common_functions::log("Processing $position", 1, 1);
    while($datpos < $data_size + $data_offset){
	my $entry;
	my $buffersize = $data_size + $data_offset - $datpos > $buffermax ? $buffermax : $data_size + $data_offset - $datpos;
	my $datchrs = read(DAT, $entry, $buffersize);
	my @line = unpack("(LCLL)*", $entry);
	$sum += &do_summing(\@line);
	$datpos = tell(DAT);
    }
    $updatengfreq->execute($sum, $check);
    $position++;
}

$dbh->do(qq{COMMIT});
$updatengfreq->finish();
$dbh->disconnect();
close(IDX) or die("Cannot close file: $!");
close(DAT) or die("Cannot close file: $!");
&common_functions::log("Finished", 1, 1);

sub do_summing{
    my ($lineref) = @_;
    my $sum = 0;
    for(my $i = 3; $i <= $#$lineref; $i += 4){
	$sum += $lineref->[$i];
    }
    return $sum;
}
