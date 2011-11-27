#!/usr/bin/perl

# create array of every 585th n-gram for use in binary search
# input: ngrams.out.uniq
# output: ngrams.idx

use warnings;
use strict;

use Storable;

die("./09d_create_ngrams_index.pl outdir") unless(scalar(@ARGV) == 1);
my $dir = shift(@ARGV);
die("Not a directory: $dir") unless(-d $dir);

open(FH, "<$dir/ngrams.out.uniq") or die("Cannot open: $!");
my $counter = 0;
my $position;
my @index;
#$position = tell(FH);
while(defined(my $line = <FH>)){
    if($counter % 585 == 0){
	my ($ngram, $length, $freq) = split(/\t/, $line);
	push(@index, pack("C9", (split(/ /, $ngram), 0, 0, 0, 0, 0, 0, 0, 0, 0)[0..8]), $counter);
    }
    $counter++;
    #print $position, "\n";
    #$position = tell(FH);
}
close(FH) or die("Cannot close: $!");
Storable::nstore(\@index, "$dir/ngrams.idx");
