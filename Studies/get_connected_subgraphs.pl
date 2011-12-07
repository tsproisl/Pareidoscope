#!/usr/bin/perl

use warnings;
use strict;

use Graph::Directed;

# https://mpi-inf.mpg.de/departments/d5/teaching/ss09/queryoptimization/lecture8.pdf
#
# EnumerateCsg(G)
# for all i ∈ [n − 1, ... , 0] descending {
#     emit {v_i};
#     EnumerateCsgRec(G , {v_i}, B_i );
# }
#
# EnumerateCsgRec(G, S, X)
# N = N(S) \ X;
# for all S' ⊆ N, S' = ∅, enumerate subsets first {
#     emit (S ∪ S');
# }
# for all S' ⊆ N, S' = ∅, enumerate subsets first {
#     EnumerateCsgRec(G, (S ∪ S'), (X ∪ N));
# }

my $graph = Graph::Directed->new;

sub enumerate_connected_subgraphs {
    my ($graph, $max_n) = @_;
    for (my $i = $#$graph_ref; $i >= 0; $i--) {
	# emit node $i
	my $subgraph;
	&enumerate_connected_subgraphs_recursive($graph, $subgraph, [0 .. $i]);
    }
}

sub enumerate_connected_subgraphs_recursive {
    my ($graph, $subgraph, $prohibited_nodes) = @_;
    # determine all edges to neighbouring nodes that are not
    # prohibited
    my @edges;
    for (my $i = ) {
    }
    # c.f. perldoc -f delete for difference of sets
    my @sets_of_edges;
    foreach my $set (@sets_of_edges) {
	#
	foreach () {
	    my $local_subgraph;
	    &enumerate_connected_subgraphs_recursive($graph, $local_subgraph, [sort keys map($_ => 1, )]);
	}
    }
}
