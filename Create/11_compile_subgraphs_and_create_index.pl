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

die("./11_compile_subgraphs_and_create_index.pl outdir max_n") unless ( scalar(@ARGV) == 2 );
my $dir   = shift(@ARGV);
my $max_n = shift(@ARGV);
die("Not a directory: $dir") unless ( -d $dir );

&common_functions::log( "Compile subgraph index", 1, 1 );

for my $i ( 1 .. $max_n ) {
    open( IN, "<", "$dir/subgraphs_$i.uniq" ) or die("Cannot open file: $!");
    open( OUT, ">", "$dir/subgraphs" . sprintf( "%02d", $i ) . ".dat" ) or die("Cannot open file: $!");
    my $counter = 0;
    my $position;
    my @index;
    while ( defined( my $line = <IN> ) ) {
        chomp($line);
        my @fields = split( /\t/,  $line );
        my @matrix = split( /\s+/, $fields[0] );
        die("There should be no tags with code > 65535: $line\n") if ( grep( $_ > 65535, @tags ) );
        my $matrix = pack( "S*", @matrix );
        my $freq   = pack( "L",  $fields[2] );
        if ( $counter % 512 == 0 ) {
            $position = tell(OUT);
            push( @index, $matrix, $position );
        }
        print OUT $matrix, $freq;
        $counter++;
    }
    close(IN)  or die("Cannot close file: $!");
    close(OUT) or die("Cannot close file: $!");
    Storable::nstore( \@index, "$dir/subgraphs" . sprintf( "%02d", $i ) . ".idx" );
}

&common_functions::log( "Finished", 1, 1 );
