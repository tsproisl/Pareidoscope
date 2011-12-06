#!/usr/bin/perl

use warnings;
use strict;

use Math::BigInt;#::GMP;

#printf("%d\n", &count_possible_graphs(2));
#printf("%d\n", &count_possible_graphs(3));
#printf("%d\n", &count_possible_graphs(4));
#printf("%d\n", &count_possible_graphs(5));

print &count_possible_graphs(2)->bstr(), "\n";
print &count_possible_graphs(3)->bstr(), "\n";
print &count_possible_graphs(4)->bstr(), "\n";
print &count_possible_graphs(5)->bstr(), "\n";

sub count_possible_graphs {
    my ($n) = @_;
    my $graphs = Math::BigInt->new("0");
    my $relations = Math::BigInt->new("55");
    my $possible_directed_edges   = $n * ( $n - 1 );
    my $possible_undirected_edges = $n * ( $n - 1 ) / 2;
    for ( my $i = 0; $i < 2**$possible_directed_edges; $i++ ) {
    #for ( my $i = 0; $i < 2**$possible_undirected_edges; $i++ ) {
        my $binary = sprintf( "%0${possible_directed_edges}b", $i );
	#my $binary = sprintf( "%0${possible_undirected_edges}b", $i );
        my $count = $binary =~ tr/1/1/;
        next if ( $count < $n - 1 );
        next unless ( &is_connected( $n, $binary ) );
	#$graphs++;
	$graphs->badd($relations->copy()->bpow(Math::BigInt->new("$count")));
    }
    return $graphs;
}

sub is_connected {
    my ( $n, $binary ) = @_;
    my @graph;

    # build graph
    for ( my $i = 0; $i < $n; $i++ ) {
        my @group = split( //, substr( $binary, 0, $n - 1, "" ) );
        my $j = 0;
        foreach (@group) {
            $j++ if ( $j == $i );
            last if ( $j >= $n );
            $graph[$i]->[$j] = $_;
            $j++;
        }
    }

    # check if graph is connected (DFS)
    my @visited = map( 0, ( 1 .. $n ) );
    my @stack = (0);
    while ( @stack > 0 ) {
        my $node = shift(@stack);
        if ( $visited[$node] ) {
            next;
        }
        else {
            $visited[$node] = 1;
            for ( my $i = 0; $i < $n; $i++ ) {
                next if ( $i == $node );

                # outgoing
                push( @stack, $i ) if ( $graph[$node]->[$i] );

                # incoming
                push( @stack, $i ) if ( $graph[$i]->[$node] );
            }
        }
    }

    # check if all nodes have been visited
    if ( ( join( "", @visited ) =~ tr/1/1/ ) == $n ) {
        return 1;
    }
    else {
        return 0;
    }
}
