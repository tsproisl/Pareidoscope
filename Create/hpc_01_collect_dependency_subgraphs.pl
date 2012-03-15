#!/usr/bin/perl

# this is time-consuming! preferebly use hpc facilities
# output: dependency subgraphs

use warnings;
use strict;

use Storable;

use lib "/home/hpc/slli/slli02/local/lib/perl5/site_perl/5.8.8";
use Graph::Directed;
use lib "/home/hpc/slli/slli02/local/lib/perl5/site_perl/5.8.8/x86_64-linux-thread-multi";
use Set::Object;

die("./hpc_01_collect_dependency_subgraphs.pl dependencies.out dependency_relations.dump output_file max_n") unless ( scalar(@ARGV) == 4 );
my $dependencies = shift(@ARGV);
my $relations    = shift(@ARGV);
my $outfile      = shift(@ARGV);
my $max_n        = shift(@ARGV);

my $relation_ids = Storable::retrieve($relations);

open( OUT, ">:encoding(utf8)", $outfile ) or die("Cannot open $outfile: $!");
&read_corpus( $outfile, $dependencies, $max_n );
close(OUT) or die("Cannot close $outfile: $!");

sub read_corpus {
    my ( $outfile, $dependencies, $max_n ) = @_;
    open( TAB, "<:encoding(utf8)", $dependencies ) or die("Cannot open $dependencies: $!");
OUTER: while ( my $match = <TAB> ) {

        #print STDERR "$.\n" if ( $. % 1000 == 0 );
        #last if ( $. == 5000 );
        #my $match = shift(@tablines);
        chomp($match);
        my ( $indeps, $outdeps, $roots, $cposs, $s_id ) = split( /\t/, $match );

        #next unless ( $s_id eq "4eca801b0572f4e02700021d" );
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
            if ( scalar( () = split( /\|/, $indep, -1 ) ) + scalar( () = split( /\|/, $outdep, -1 ) ) > 10 ) {
                print STDERR sprintf( "Skipped %s (%d edges)\n", $s_id, scalar( () = split( /\|/, $indep, -1 ) ) + scalar( () = split( /\|/, $outdep, -1 ) ) );
                next OUTER;
            }
            foreach ( split( /\|/, $outdep ) ) {

                #m/^(?<relation>[^(]+)\(0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/;
                m/^([^(]+)\(0(?:&apos;)*,(-?\d+)(?:&apos;)*/;

                #my $offset = $+{"offset"};
                my $offset = $2;
                my $target = $cpos + $offset;

                #$relations{$cpos}->{$target} = $+{"relation"};
                $relations{$cpos}->{$target} = $1;
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
            next if ( $seen_nodes->contains($node) );
            $seen_nodes->insert($node);
            foreach my $edge ( sort { $relations{$node}->{ $a->[1] } cmp $relations{$node}->{ $b->[1] } or $a->[1] <=> $b->[1] } $raw_graph->edges_from($node) ) {
                my $target = $edge->[1];
                unless ( exists $raw_to_graph{$target} ) {
                    $raw_to_graph{$target}       = $node_counter;
                    $graph_to_raw{$node_counter} = $target;
                    push( @agenda, $target );
                    $node_counter++;
                }
                $graph->add_edge( $raw_to_graph{$node}, $raw_to_graph{$target} );
            }
        }

        # get all connected subgraphs
        &enumerate_connected_subgraphs( $graph, $max_n, \%graph_to_raw, \%relations );
    }
    close(TAB) or die("Cannot close $dependencies: $!");
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
    my ( $graph, $max_n, $graph_to_raw, $relations ) = @_;
    foreach my $node ( sort { $b <=> $a } $graph->vertices ) {

        # emit node $i
        my $subgraph = Graph::Directed->new;
        $subgraph->add_vertex($node);
        &emit( $subgraph, $graph_to_raw, $relations );
        my $prohibited_nodes = Set::Object->new();
        $prohibited_nodes->insert( 0 .. $node );
        &enumerate_connected_subgraphs_recursive( $graph, $subgraph, $prohibited_nodes, $max_n, $graph_to_raw, $relations );
    }
}

sub enumerate_connected_subgraphs_recursive {
    my ( $graph, $subgraph, $prohibited_nodes, $max_n, $graph_to_raw, $relations ) = @_;

    # determine all edges to neighbouring nodes that are not
    # prohibited
    my $edges      = Set::Object->new();
    my $out_edges  = Set::Object->new();
    my $in_edges   = Set::Object->new();
    my $neighbours = Set::Object->new();
    foreach my $node ( $subgraph->vertices ) {

        #my $node_edges = Set::Object->new();
        foreach my $edge ( $graph->edges_from($node) ) {
            next if ( $prohibited_nodes->contains( $edge->[1] ) );
            $edges->insert($edge);
            $out_edges->insert($edge);

            #$node_edges->insert($edge);
            $neighbours->insert( $edge->[1] );
        }
        foreach my $edge ( $graph->edges_to($node) ) {
            next if ( $prohibited_nodes->contains( $edge->[0] ) );
            $edges->insert($edge);
            $in_edges->insert($edge);

            #$node_edges->insert($edge);
            $neighbours->insert( $edge->[0] );
        }

        #$edges->insert($node_edges) unless ($node_edges->is_null);
    }

    #my $first_powerset = &powerset_old( $edges, [$subgraph->vertices], $max_n);
    my $first_powerset = &cross_set( &powerset( $out_edges, 0, $max_n - $subgraph->vertices ), &powerset( $in_edges, 0, $max_n - $subgraph->vertices ), $max_n - $subgraph->vertices );

    #my $first_powerset = &powerset_of_sets_of_sets( $edges, 0, $max_n - $subgraph->vertices);
    foreach my $set ( $first_powerset->elements() ) {
        next if ( $set->size == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map( @$_, $set->elements ) ) );

        # all combinations of edges between the newly added nodes
        my $edges = Set::Object->new();
        foreach my $new_node ( $new_nodes->elements() ) {
            $edges->insert( grep( $new_nodes->contains( $_->[1] ), $graph->edges_from($new_node) ) );
        }

        #my $second_powerset = &powerset_old( $edges, [], $max_n );
        my $second_powerset = &powerset( $edges, 0, $edges->size );
        foreach my $new_set ( $second_powerset->elements ) {
            my $local_subgraph = $subgraph->copy_graph;
            $local_subgraph->add_edges( $set->elements, $new_set->elements );
            &emit( $local_subgraph, $graph_to_raw, $relations );
            if ( $local_subgraph->vertices < $max_n ) {
                &enumerate_connected_subgraphs_recursive( $graph, $local_subgraph, Set::Object::union( $prohibited_nodes, $neighbours ), $max_n, $graph_to_raw, $relations );
            }
        }
    }
}

sub cross_set {
    my ( $set1, $set2, $max ) = @_;
    my $cross_set = Set::Object->new();
    foreach my $e1 ( $set1->elements ) {
        foreach my $e2 ( $set2->elements ) {
            my $e3 = Set::Object::union( $e1, $e2 );
            if ( $e3->size <= $max ) {
                $cross_set->insert($e3);
            }
            else {
                my $nodes = Set::Object->new( map( $_->[1], $e1->elements ), map( $_->[0], $e2->elements ) );
                $cross_set->insert($e3) if ( $nodes->size <= $max );
            }

            #$e3->size > $max or ($cross_set->insert($e3) and next);
            #$cross_set->insert($e3) and next if($e3->size <= $max);
            #if ($e3->size > $max) {
            #}
            #else {
            #$cross_set->insert($e3);
            #}
        }
    }
    return $cross_set;
}

sub powerset {
    my ( $set, $min, $max ) = @_;
    my @elements           = $set->elements;
    my $powerset           = Set::Object->new();
    my $number_of_elements = $set->size;
OUTER: for ( my $i = 0; $i < 2**$number_of_elements; $i++ ) {
        my $binary = sprintf( "%0${number_of_elements}b", $i );
        my $ones = $binary =~ tr/1/1/;
        next if ( $ones < $min or $ones > $max );
        my @binary = split( //, $binary );
        $powerset->insert( Set::Object->new( map( $elements[$_], grep( $binary[$_], ( 0 .. $#binary ) ) ) ) );
    }
    return $powerset;
}

sub emit {
    my ( $subgraph, $graph_to_raw, $relations ) = @_;
    my %edges;
    my @list_representation;
    my %nodes;
    my @sorted_nodes;
    my @emit_structure;
    foreach my $edge ( $subgraph->edges() ) {
        $edges{ $edge->[0] }->{ $edge->[1] } = $relations->{ $graph_to_raw->{ $edge->[0] } }->{ $graph_to_raw->{ $edge->[1] } };
        push( @list_representation, sprintf( "%s(%d, %d)", $edges{ $edge->[0] }->{ $edge->[1] }, $edge->[0], $edge->[1] ) );
    }
    foreach my $vertex ( $subgraph->vertices() ) {
        my ( @incoming, @outgoing );
        foreach my $edge ( $subgraph->edges_to($vertex) ) {
            my $ins  = join( ",", sort map( $edges{ $_->[0] }->{ $_->[1] }, $subgraph->edges_to( $edge->[0] ) ) );
            my $outs = join( ",", sort map( $edges{ $_->[0] }->{ $_->[1] }, $subgraph->edges_from( $edge->[0] ) ) );
            $ins  = $ins  ne "" ? "<($ins)"  : "";
            $outs = $outs ne "" ? ">($outs)" : "";
            push( @incoming, sprintf( "%s(%s%s)", $edges{ $edge->[0] }->{ $edge->[1] }, $ins, $outs ) );
        }
        foreach my $edge ( $subgraph->edges_from($vertex) ) {
            my $ins  = join( ",", sort map( $edges{ $_->[0] }->{ $_->[1] }, $subgraph->edges_to( $edge->[1] ) ) );
            my $outs = join( ",", sort map( $edges{ $_->[0] }->{ $_->[1] }, $subgraph->edges_from( $edge->[1] ) ) );
            $ins  = $ins  ne "" ? "<($ins)"  : "";
            $outs = $outs ne "" ? ">($outs)" : "";
            push( @outgoing, sprintf( "%s(%s%s)", $edges{ $edge->[0] }->{ $edge->[1] }, $ins, $outs ) );
        }
        my $incoming = join( ",", @incoming );
        my $outgoing = join( ",", @outgoing );
        $incoming = $incoming ne "" ? "<($incoming)" : "";
        $outgoing = $outgoing ne "" ? ">($outgoing)" : "";
        $nodes{$vertex} = $incoming . $outgoing;
    }
    @sorted_nodes = sort { $nodes{$a} cmp $nodes{$b} } keys %nodes;
    for ( my $i = 0; $i <= $#sorted_nodes; $i++ ) {
        my $node_1 = $sorted_nodes[$i];
        for ( my $j = 0; $j <= $#sorted_nodes; $j++ ) {
            my $node_2 = $sorted_nodes[$j];
            if ( $edges{$node_1}->{$node_2} ) {
                $emit_structure[$i]->[$j] = $relation_ids->{ $edges{$node_1}->{$node_2} };
                die( "Self-loop: " . join( ", ", @list_representation ) ) if ( $i == $j );
            }
            else {
                $emit_structure[$i]->[$j] = 0;
            }
        }
    }
    printf OUT ( "%s\t%d\n", join( " ", map( join( " ", @$_ ), @emit_structure ) ), scalar(@emit_structure) );
}
