#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;

#use lib "/home/linguistik/tsproisl/local/lib/perl5/site_perl";
use Graph::Directed;

# use CWB::CQP;
# use CWB::CL;
use Set::Object;

# my $outdir = "/localhome/Diss/trunk/Resources/Pareidoscope/Studies";
my $outdir = ".";
my $corpus = "OANC";
my $max_n  = 5;

&read_corpus( $outdir, $corpus, $max_n );

sub read_corpus {
    my ( $outdir, $corpus, $max_n ) = @_;

    # my $cqp = new CWB::CQP;
    # $cqp->set_error_handler('die');    # built-in, useful for one-off scripts
    # $cqp->exec("set Registry '/localhome/Databases/CWB/registry'");
    # $cqp->exec($corpus);
    # $CWB::CL::Registry = '/localhome/Databases/CWB/registry';
    # my $corpus_handle = new CWB::CL::Corpus $corpus;

    #$cqp->exec("A = <s> [] expand to s");
    #my ($size) = $cqp->exec("size A");
    #$cqp->exec("tabulate A match .. matchend indep, match .. matchend outdep, match .. matchend root, match .. matchend, match s_id > \"$outdir/tabulate.out\"");
    open( TAB, "<:encoding(utf8)", "$outdir/tabulate.out" ) or die("Cannot open $outdir/tabulate.out: $!");
OUTER: while ( defined( my $match = <TAB> ) ) {
        print STDERR "$.\n" if ( $. % 1000 == 0 );
        last if ( $. == 5000 );
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
    foreach my $set ( $first_powerset->elements ) {
        next if ( $set->size == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map( @$_, $set->elements ) ) );

        # all combinations of edges between the newly added nodes
        my $edges = Set::Object->new();
        foreach my $new_node ($new_nodes) {
            $edges->insert( grep( $new_nodes->contains( $_->[1] ), $subgraph->edges_from($new_node) ) );
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

sub powerset_old {
    my ( $set, $nodes, $max_n ) = @_;
    my @elements           = $set->elements;
    my $powerset           = Set::Object->new();
    my $number_of_elements = scalar(@elements);

    # if (@$nodes > 0 and $max_n - @$nodes == 1) {
    # 	my $nodes_set = Set::Object->new(@$nodes);
    # 	foreach my $node (@$nodes) {
    # 	    my @local_edges;
    # 	    foreach my $edge ($set->elements) {
    # 		push(@local_edges, $edge) if(grep($nodes_set->contains($_), @$edge));
    # 	    }
    # 	    $powerset->insert((&powerset(Set::Object->new(@local_edges), 0, scalar(@local_edges)))->elements);
    # 	}
    # 	return $powerset;
    # }
OUTER: for ( my $i = 0; $i < 2**$number_of_elements; $i++ ) {
        my @binary      = split( //, sprintf( "%0${number_of_elements}b", $i ) );
        my $subset      = Set::Object->new();
        my $local_nodes = Set::Object->new(@$nodes);
        for ( my $j = 0; $j <= $#binary; $j++ ) {
            if ( $binary[$j] ) {
                my $edge = $elements[$j];
                if ( @$nodes > 0 ) {
                    $local_nodes->insert(@$edge);
                    next OUTER if ( $local_nodes->size > $max_n );
                }
                $subset->insert($edge);
            }
        }
        $powerset->insert($subset);
    }
    return $powerset;
}

sub powerset_of_sets_of_sets {
    my ( $set_of_sets, $min, $max ) = @_;
    my $foo = Set::Object->new();

    # $set_of_sets = ((edge, edge, ...), (edge, ...), ...)
    my $powerset = Set::Object->new();
    foreach my $set ( $set_of_sets->elements ) {

        # $set = (edge, edge, ...)
        $foo->insert( &powerset( $set, 1, $set->size ) );

        # $set = ((edge, edge, ...), (edge, ...), ...)
        # node = ((edge, edge, ...), (edge, ...), ...)
    }
    $set_of_sets = $foo;

    # $set_of_sets = (node, node, ...)
    my $raw_powerset = &powerset( $set_of_sets, $min, $max );

    # $raw_powerset = ((node, node, ...), (node, ...), ...)
    foreach my $set_of_nodes ( $raw_powerset->elements ) {
        if ( $set_of_nodes->is_null ) {
            $powerset->insert( Set::Object->new() );
            next;
        }

        # $set_of_nodes = (node, node, ...)
        my @nodes          = $set_of_nodes->elements;
        my $local_powerset = shift(@nodes);
        while (@nodes) {
            $local_powerset = &cross_set( $local_powerset, shift(@nodes) );
        }
        $powerset->insert( $local_powerset->elements );
    }
    return $powerset;
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
    foreach my $edge ($subgraph->edges()) {
	$edges{$edge->[0]}->{$edge->[1]} = $relations->{$graph_to_raw->{$edge->[0]}}->{$graph_to_raw->{$edge->[1]}};
	push(@list_representation, sprintf("%s(%d, %d)", $edges{$edge->[0]}->{$edge->[1]}, $edge->[0], $edge->[1]));
    }
    foreach my $vertex ($subgraph->vertices()) {
	my (@incoming, @outgoing);
	foreach my $edge ($subgraph->edges_to($vertex)) {
	    my $ins = join(",", sort map($edges{$_->[0]}->{$_->[1]}, $subgraph->edges_to($edge->[0])));
	    my $outs = join(",", sort map($edges{$_->[0]}->{$_->[1]}, $subgraph->edges_from($edge->[0])));
	    $ins = defined($ins) ? "<($ins)" : "";
	    $outs = defined($outs) ? "<($outs)" : "";
	    push(@incoming, sprintf("%s(%s%s)", $edges{$edge->[0]}->{$edge->[1]}, $ins, $outs));
	}
	foreach my $edge ($subgraph->edges_from($vertex)) {
	    my $ins = join(",", sort map($edges{$_->[0]}->{$_->[1]}, $subgraph->edges_to($edge->[1])));
	    my $outs = join(",", sort map($edges{$_->[0]}->{$_->[1]}, $subgraph->edges_from($edge->[1])));
	    $ins = defined($ins) ? "<($ins)" : "";
	    $outs = defined($outs) ? "<($outs)" : "";
	    push(@outgoing, sprintf("%s(%s%s)", $edges{$edge->[0]}->{$edge->[1]}, $ins, $outs));
	}
	my $incoming = join(",", @incoming);
	my $outgoing = join(",", @outgoing);
	$incoming = defined($incoming) ? "<($incoming)" : "";
	$outgoing = defined($outgoing) ? "<($outgoing)" : "";
	$nodes{$vertex} = $incoming . $outgoing;
    }
    sort {$nodes{$a} cmp $nodes{$b} or warn(join("\n", @list_representation))} keys %nodes;
}

sub build_matrix {

}
