#!/usr/bin/perl

# create binary index of ngrams for faster lookup
# input: ngrams.out.uniq
# output: ngrams.dat (tag1 tag2 tag3 ... tag9 length ngfreq)

use warnings;
use strict;

use common_functions;

# record: (c5){9} length frequency

die("./09c_compile_ngram_index.pl outdir") unless(scalar(@ARGV) == 1);
my $dir = shift(@ARGV);
die("Not a directory: $dir") unless(-d $dir);

open(DAT, ">$dir/ngrams.dat") or die("Cannot open file: $!");

open(IN, "<$dir/ngrams.out.uniq") or die("Cannot open file: $!");

&common_functions::log("Compile ngram index", 1, 1);
while(defined(my $line = <IN>)){
    chomp($line);
    my @fields = split(/\t/, $line);
    my @tags = split(/\s+/, $fields[0]);
    #@tags = (@tags, 255, 255, 255, 255, 255, 255, 255, 255, 255)[0..8];
    @tags = (@tags, 0, 0, 0, 0, 0, 0, 0, 0, 0)[0..8];
    #print join("-", @tags), "\n";
    print DAT pack("C10L", @tags, @fields[1..$#fields]);
}
close(DAT) or die("Cannot close file: $!");
&common_functions::log("Finished", 1, 1);
