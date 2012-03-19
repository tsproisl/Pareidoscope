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
        my ( %raw_relations, %relations, %reverse_relations );
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
		next if ($cpos == $target);
		#$raw_relations{$cpos}->{$target} = $+{"relation"};
		$raw_relations{$cpos}->{$target} = $1;
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
            foreach my $edge ( sort { $raw_relations{$node}->{ $a->[1] } cmp $raw_relations{$node}->{ $b->[1] } or $a->[1] <=> $b->[1] } $raw_graph->edges_from($node) ) {
                my $target = $edge->[1];
                unless ( exists $raw_to_graph{$target} ) {
                    $raw_to_graph{$target}       = $node_counter;
                    $graph_to_raw{$node_counter} = $target;
                    push( @agenda, $target );
                    $node_counter++;
                }
                $relations{$raw_to_graph{$node}}->{$raw_to_graph{$target}} = $raw_relations{$node}->{$target};
		$reverse_relations{$raw_to_graph{$target}}->{$raw_to_graph{$node}} = $raw_relations{$node}->{$target};
                $graph->add_edge( $raw_to_graph{$node}, $raw_to_graph{$target} );
            }
        }

        # get all connected subgraphs
        &enumerate_connected_subgraphs( $graph, $max_n, \%relations, \%reverse_relations );
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
    my ( $graph, $max_n, $relations, $reverse_relations ) = @_;
    foreach my $node ( sort { $b <=> $a } $graph->vertices ) {

        # emit node $i
        my $subgraph = Graph::Directed->new;
        $subgraph->add_vertex($node);
        &emit( $subgraph, $relations );
        #my $prohibited_nodes = Set::Object->new();
        #$prohibited_nodes->insert( 0 .. $node );
        #&enumerate_connected_subgraphs_recursive( $graph, $subgraph, $prohibited_nodes, $max_n, $relations, $reverse_relations );
	my $prohibited_edges = Set::Object->new();
	$prohibited_edges->insert( map( $_->[0] . '-' . $_->[1], map {$graph->edges_at($_)} ( 0 .. $node - 1 )) );
        &enumerate_connected_subgraphs_recursive( $graph, $subgraph, $prohibited_edges, $max_n, $relations, $reverse_relations );
    }
}

sub enumerate_connected_subgraphs_recursive {
    #my ( $graph, $subgraph, $prohibited_nodes, $max_n, $relations, $reverse_relations ) = @_;
    my ( $graph, $subgraph, $prohibited_edges, $max_n, $relations, $reverse_relations ) = @_;

    # determine all edges to neighbouring nodes that are not
    # prohibited
    my $out_edges  = Set::Object->new();
    my $in_edges   = Set::Object->new();
    my $neighbours = Set::Object->new();
    my $neighbouring_edges = Set::Object->new();

    foreach my $node ( $subgraph->vertices ) {

        # outgoing edges
        foreach my $target ( keys %{ $relations->{$node} } ) {
            #next if ( $prohibited_nodes->contains($target) );
	    next if ( $prohibited_edges->contains( "$node-$target" ) );
            $out_edges->insert( [ $node, $target ] );
            $neighbours->insert($target);
	    $neighbouring_edges->insert( "$node-$target" );
        }

        # incoming edges
        foreach my $origin ( keys %{ $reverse_relations->{$node} } ) {
            #next if ( $prohibited_nodes->contains($origin) );
	    next if ( $prohibited_edges->contains( "$origin-$node" ) );
            $in_edges->insert( [ $origin, $node ] );
            $neighbours->insert($origin);
	    $neighbouring_edges->insert( "$origin-$node" );
        }
    }

    my $first_powerset = &cross_set( &powerset( $out_edges, 0, $max_n - $subgraph->vertices ), &powerset( $in_edges, 0, $max_n - $subgraph->vertices ), $max_n - $subgraph->vertices );

    foreach my $set ( $first_powerset->elements() ) {
        next if ( $set->size == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map( @$_, $set->elements ) ) );

        # all combinations of edges between the newly added nodes
        my $edges = Set::Object->new();
        foreach my $new_node ( $new_nodes->elements() ) {
            $edges->insert( grep( $new_nodes->contains( $_->[1] ), $graph->edges_from($new_node) ) );
        }

        my $second_powerset = &powerset( $edges, 0, $edges->size );
        foreach my $new_set ( $second_powerset->elements ) {
            my $local_subgraph = $subgraph->copy_graph;
            $local_subgraph->add_edges( $set->elements, $new_set->elements );
            &emit( $local_subgraph, $relations );
            if ( $local_subgraph->vertices < $max_n ) {
                #&enumerate_connected_subgraphs_recursive( $graph, $local_subgraph, Set::Object::union( $prohibited_nodes, $neighbours ), $max_n, $relations, $reverse_relations );
		&enumerate_connected_subgraphs_recursive( $graph, $local_subgraph, Set::Object::union( $prohibited_edges, $neighbouring_edges ), $max_n, $relations, $reverse_relations );
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
    my ( $subgraph, $relations ) = @_;
    my %edges;
    my %incoming_edge;
    my @list_representation;
    my %nodes;
    my @sorted_nodes;
    my @emit_structure;
    foreach my $edge ( $subgraph->edges() ) {
        my ( $start, $end ) = @$edge;
        my $relation = $relations->{$start}->{$end};
        $edges{$start}->{$end}         = $relation;
        $incoming_edge{$end}->{$start} = $relation;
        push( @list_representation, sprintf( "%s(%d, %d)", $relation, $start, $end ) );
    }
    foreach my $vertex ( $subgraph->vertices() ) {
        my ( @incoming, @outgoing );

        # incoming edges
        foreach my $local_vertex ( keys %{ $incoming_edge{$vertex} } ) {
            my $ins  = join( ",", sort map( $edges{$_}->{$local_vertex}, keys %{ $incoming_edge{$local_vertex} } ) );
            my $outs = join( ",", sort map( $edges{$local_vertex}->{$_}, keys %{ $edges{$local_vertex} } ) );
            $ins  = $ins  ne "" ? "<($ins)"  : "";
            $outs = $outs ne "" ? ">($outs)" : "";
            push( @incoming, sprintf( "%s(%s%s)", $edges{$local_vertex}->{$vertex}, $ins, $outs ) );
        }

        # outgoing edges
        foreach my $local_vertex ( keys %{ $edges{$vertex} } ) {
            my $ins  = join( ",", sort map( $edges{$_}->{$local_vertex}, keys %{ $incoming_edge{$local_vertex} } ) );
            my $outs = join( ",", sort map( $edges{$local_vertex}->{$_}, keys %{ $edges{$local_vertex} } ) );
            $ins  = $ins  ne "" ? "<($ins)"  : "";
            $outs = $outs ne "" ? ">($outs)" : "";
            push( @outgoing, sprintf( "%s(%s%s)", $edges{$vertex}->{$local_vertex}, $ins, $outs ) );
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
