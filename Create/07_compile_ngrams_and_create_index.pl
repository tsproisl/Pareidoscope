#!/usr/bin/perl

# create binary indexes of ngrams for faster lookup
# input: ngrams.out.uniq
# output: ngrams01.dat (tag1 ngfreq)
#         ngrams01.idx
#         ...
#         ngrams09.dat (tag1 tag2 tag3 ... tag9 ngfreq)
#         ngrams09.idx

use warnings;
use strict;

use Storable;
use common_functions;

# record: (c5){9} length frequency

die("./07_compile_ngrams_and_create_index.pl outdir file") unless ( scalar(@ARGV) == 2 );
my $dir  = shift(@ARGV);
my $file = shift(@ARGV);
die("Not a directory: $dir") unless ( -d $dir );

my @dats;

for my $i ( 1 .. 9 ) {
    open( $dats[$i], ">", "$dir/$file" . sprintf( "%02d", $i ) . ".dat" ) or die("Cannot open file: $!");
}
open( IN, "<$dir/$file.out.uniq.filtered" ) or die("Cannot open file: $!");

&common_functions::log( "Compile ngram index", 1, 1 );
my @counter = ( undef, 0, 0, 0, 0, 0, 0, 0, 0, 0 );
my $position;
my @index;
while ( defined( my $line = <IN> ) ) {
    chomp($line);
    my @fields = split( /\t/,  $line );
    my @tags   = split( /\s+/, $fields[0] );
    die("There should be no tags with code > 255: $line\n") if ( grep( $_ > 255, @tags ) );
    my $tags   = pack( "C*", @tags );
    my $ngfreq = pack( "L",  $fields[2] );
    if ( $counter[ scalar(@tags) ] % 512 == 0 ) {
        $position = tell( $dats[ scalar(@tags) ] );
        push( @{ $index[ scalar(@tags) ] }, $tags, $position );
    }
    print { $dats[ scalar(@tags) ] } $tags, $ngfreq;
    $counter[ scalar(@tags) ]++;
}

for my $i ( 1 .. 9 ) {
    close( $dats[$i] ) or die("Cannot close file: $!");
    Storable::nstore( $index[$i], "$dir/$file" . sprintf( "%02d", $i ) . ".idx" );
}
close(IN) or die("Cannot close file: $!");

&common_functions::log( "Finished", 1, 1 );
