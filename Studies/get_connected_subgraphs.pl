#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;

use lib "/home/linguistik/tsproisl/local/lib/perl5/site_perl";
use Graph::Directed;
use CWB::CQP;
use CWB::CL;
use Set::Object;

my $outdir = "/localhome/Diss/trunk/Resources/Pareidoscope/Studies/";
my $corpus = "OANC";
my $max_n  = 4;

&read_corpus( $outdir, $corpus, $max_n );

sub read_corpus {
    my ( $outdir, $corpus, $max_n ) = @_;
    my $cqp = new CWB::CQP;
    $cqp->set_error_handler('die');    # built-in, useful for one-off scripts
    $cqp->exec("set Registry '/localhome/Databases/CWB/registry'");
    $cqp->exec($corpus);
    $CWB::CL::Registry = '/localhome/Databases/CWB/registry';
    my $corpus_handle = new CWB::CL::Corpus $corpus;

    #$cqp->exec("A = <s> [] expand to s");
    #my ($size) = $cqp->exec("size A");
    #$cqp->exec("tabulate A match .. matchend indep, match .. matchend outdep, match .. matchend root, match .. matchend, match s_id > \"$outdir/tabulate.out\"");
    open( TAB, "<:encoding(utf8)", "$outdir/tabulate.out" ) or die("Cannot open $outdir/tabulate.out: $!");
OUTER: while ( defined( my $match = <TAB> ) ) {
        chomp($match);
        my ( $indeps, $outdeps, $roots, $cposs, $s_id ) = split( /\t/, $match );
        my @indeps  = split( / /, $indeps );
        my @outdeps = split( / /, $outdeps );
        my @roots   = split( / /, $roots );
        my @cposs   = split( / /, $cposs );
        my $root    = $cposs[0];
        my $raw_graph = Graph::Directed->new;
        my $graph     = Graph::Directed->new;
        my %relations;
        my ( %raw_to_graph, %graph_to_raw );

        for ( my $i = 0; $i <= $#cposs; $i++ ) {
            $root = $cposs[$i] if ( $roots[$i] eq "root" );
            my $indep  = $indeps[$i];
            my $outdep = $outdeps[$i];
            my $cpos   = $cposs[$i];
            $indep  =~ s/^\|//;
            $outdep =~ s/^\|//;
            $indep  =~ s/\|$//;
            $outdep =~ s/\|$//;

            # Skip sentences with nodes that have more than ten edges
            if ( scalar( split( /\|/, $indep ) ) + scalar( split( /\|/, $outdep ) ) > 10 ) {
                print STDERR sprintf( "Skipped %s (%d edges)\n", $s_id, scalar( split( /\|/, $indep ) ) + scalar( split( /\|/, $outdep ) ) );
                next OUTER;
            }
            foreach ( split( /\|/, $outdep ) ) {
                m/^(?<relation>[^(]+)\(0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/;
                my $offset = $+{"offset"};
                $offset = "+" . $offset unless ( substr( $offset, 0, 1 ) eq "-" );
                my $target = eval "$cpos$offset";
                $relations{$cpos}->{$target} = $+{relation};
                $raw_graph->add_edge( $cpos, $target );
            }
        }

        # BFS
        $raw_to_graph{$root} = 0;
        $graph_to_raw{0} = $root;
        my @agenda       = ($root);
        my $seen_nodes   = Set::Object->new();
        my $node_counter = 1;
        while (@agenda) {
            my $node = shift(@agenda);
            $seen_nodes->insert($node);
            foreach my $edge ( sort { $relations{$node}->{ $a->[1] } cmp $relations{$node}->{ $b->[1] } or $a->[1] <=> $b->[1] } $raw_graph->edges_from($node) ) {
                my $target = $edge->[1];
                unless ( $seen_nodes->contains($target) ) {
                    $raw_to_graph{$target}       = $node_counter;
                    $graph_to_raw{$node_counter} = $target;
                    push( @agenda, $target );
                    $node_counter++;
                }
                $graph->add_edge( $raw_to_graph{$node}, $raw_to_graph{$target} );
            }
        }

        # get all connected subgraphs
        &enumerate_connected_subgraphs( $graph, $max_n );
    }
    close(TAB) or die("Cannot open $outdir/tabulate.out: $!");
}

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

sub enumerate_connected_subgraphs {
    my ( $graph, $max_n ) = @_;
    foreach my $node ( sort { $b <=> $a } $graph->vertices ) {

        # emit node $i
        my $subgraph = Graph::Directed->new;
        $subgraph->add_vertex($node);
        print "$subgraph\n";
        my $prohibited_nodes = Set::Object->new();
        $prohibited_nodes->insert( 0 .. $node );
        &enumerate_connected_subgraphs_recursive( $graph, $subgraph, $prohibited_nodes, $max_n );
    }
}

sub enumerate_connected_subgraphs_recursive {
    my ( $graph, $subgraph, $prohibited_nodes, $max_n ) = @_;

    # determine all edges to neighbouring nodes that are not
    # prohibited
    my $edges      = Set::Object->new();
    my $neighbours = Set::Object->new();
    foreach my $node ( $subgraph->vertices ) {
        foreach my $edge ( $graph->edges_from($node) ) {
            next if ( $prohibited_nodes->contains( $edge->[1] ) );
            $edges->insert($edge);
            $neighbours->insert( $edge->[1] );
        }
        foreach my $edge ( $graph->edges_to($node) ) {
            next if ( $prohibited_nodes->contains( $edge->[0] ) );
            $edges->insert($edge);
            $neighbours->insert( $edge->[0] );
        }
    }
    foreach my $set ( ( &powerset( $edges, [ $subgraph->vertices ], $max_n ) )->elements ) {
        next if ( $set->size == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map( @$_, $set->elements ) ) );

        # all combinations of edges between the newly added nodes
        my $edges = Set::Object->new();
        foreach my $new_node ($new_nodes) {
            $edges->insert( grep( $new_nodes->contains( $_->[1] ), $subgraph->edges_from($new_node) ) );
        }
        foreach my $new_set ( ( &powerset( $edges, [ $subgraph->vertices ], $max_n ) )->elements ) {
            my $local_subgraph = $subgraph->copy_graph;
            $local_subgraph->add_edges( $set->elements );
            print "$local_subgraph\n";
            &enumerate_connected_subgraphs_recursive( $graph, $local_subgraph, Set::Object::union( $prohibited_nodes, $neighbours ), $max_n );
        }
    }
}

sub powerset {
    my ( $set, $nodes, $max_n ) = @_;
    my @elements           = $set->elements;
    my $powerset           = Set::Object->new();
    my $number_of_elements = scalar(@elements);
OUTER: for ( my $i = 0; $i < 2**$number_of_elements; $i++ ) {
        my @binary      = split( //, sprintf( "%0${number_of_elements}b", $i ) );
        my $subset      = Set::Object->new();
        my $local_nodes = Set::Object->new(@$nodes);
        for ( my $j = 0; $j <= $#binary; $j++ ) {
            if ( $binary[$j] ) {
                my $edge = $elements[$j];
                $subset->insert($edge);
                $local_nodes->insert(@$edge);
                next OUTER if ( $local_nodes->size > $max_n );
            }
        }
        $powerset->insert($subset);
    }
    return $powerset;
}
