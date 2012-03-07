#!/usr/bin/perl
package Collector::Subgraph;
use 5.010;

use strict;
use warnings;
use open qw(:utf8 :std);
use utf8;
use English qw( -no_match_vars );

use CWB;
use CWB::CL;
use CWB::CQP;
use Graph::Directed;
use Set::Object;
use DBI;
use Storable;

use version; our $VERSION = qv('0.0.1');
use Carp;    # carp croak

use Readonly;
Readonly my $MAXIMUM_NUMBER_OF_RELATIONS => 10;
Readonly my $MAXIMUM_SUBGRAPH_SIZE       => 5;
Readonly my $UNLIMITED_NUMBER_OF_FIELDS  => -1;
Readonly my $GET_ATTRIBUTE_USAGE         => 'Usage: $att_handle = $self->_get_attribute($name);';
Readonly my $RELATION_IDS                => Storable::retrieve('dependency_relations.dump');

# use Data::Dumper;            # Dumper
# use List::Util;              # first max maxstr min minstr reduce shuffle sum
# use List::MoreUtils;         # "the stuff missing in List::Util"
use Log::Log4perl qw(:easy); # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
Log::Log4perl->easy_init( $DEBUG );

sub connect_to_corpus {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = {};
    $self->{"cqp"} = CWB::CQP->new();
    croak("Can't start CQP backend.") unless ( defined $self->{"cqp"} );
    $self->{"cqp"}->exec("set Registry '../Pareidoscope/corpora/registry'");
    $self->{"cqp"}->exec("OANC");
    $CWB::CL::Registry = '../Pareidoscope/corpora/registry';
    $self->{"corpus_handle"} = CWB::CL::Corpus->new("OANC");
    croak "Error: can't open corpus OANC, aborted." unless ( defined $self->{"corpus_handle"} );
    bless $self, $class;
    return $self;
}

sub get_subgraphs {
    my ( $self, $word ) = @_;
    my $s_handle      = $self->_get_attribute("s");
    my $indep_handle  = $self->_get_attribute("indep");
    my $outdep_handle = $self->_get_attribute("outdep");
    $self->{"cqp"}->exec( sprintf "A = [word = \"%s\" %%c]", $word );
    my @matches = $self->{"cqp"}->exec("tabulate A match");
    my $loop_counter = 0;
SENTENCE:
    foreach my $match (@matches) {
	DEBUG(sprintf "%d/%d", $loop_counter, scalar @matches);
	$loop_counter++;
	last SENTENCE if($loop_counter > 100);
        my ( $start, $end ) = $s_handle->cpos2struc2cpos($match);
        my @indeps  = $indep_handle->cpos2str( $start .. $end );
        my @outdeps = $outdep_handle->cpos2str( $start .. $end );
        my %relation;
        my $graph = Graph::Directed->new();
        foreach my $i ( 0 .. $#outdeps ) {
            $indeps[$i]  =~ s/^[|]//xms;
            $indeps[$i]  =~ s/[|]$//xms;
            $outdeps[$i] =~ s/^[|]//xms;
            $outdeps[$i] =~ s/[|]$//xms;
            my @out = split /[|]/xms, $outdeps[$i];
            next SENTENCE if ( scalar( () = split /[|]/xms, $indeps[$i], $UNLIMITED_NUMBER_OF_FIELDS ) + scalar @out > $MAXIMUM_NUMBER_OF_RELATIONS );
            my $cpos = $start + $i;
            foreach my $dep (@out) {
                $dep =~ m/^ (?<relation>[^(]+)[(]0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/xms;
                my $target = $cpos + $LAST_PAREN_MATCH{"offset"};
                $relation{$cpos}->{$target} = $LAST_PAREN_MATCH{"relation"};
                $graph->add_edge( $cpos, $target );
            }
        }
        my $subgraph = Graph::Directed->new();
        $subgraph->add_vertex($match);
        _emit( $subgraph, \%relation );
        my $prohibited_nodes = Set::Object->new();
        _enumerate_connected_subgraphs_recursive( $graph, $subgraph, $prohibited_nodes, \%relation );
    }
    return;
}

sub _enumerate_connected_subgraphs_recursive {
    my ( $graph, $subgraph, $prohibited_nodes, $relation_ref ) = @_;

    # determine all edges to neighbouring nodes that are not
    # prohibited
    my $edges      = Set::Object->new();
    my $out_edges  = Set::Object->new();
    my $in_edges   = Set::Object->new();
    my $neighbours = Set::Object->new();
    foreach my $node ( $subgraph->vertices ) {
        foreach my $edge ( $graph->edges_from($node) ) {
            next if ( $prohibited_nodes->contains( $edge->[1] ) );
            $edges->insert($edge);
            $out_edges->insert($edge);
            $neighbours->insert( $edge->[1] );
        }
        foreach my $edge ( $graph->edges_to($node) ) {
            next if ( $prohibited_nodes->contains( $edge->[0] ) );
            $edges->insert($edge);
            $in_edges->insert($edge);
            $neighbours->insert( $edge->[0] );
        }
    }

    my $first_powerset = _cross_set( _powerset( $out_edges, 0, $MAXIMUM_SUBGRAPH_SIZE - $subgraph->vertices ), _powerset( $in_edges, 0, $MAXIMUM_SUBGRAPH_SIZE - $subgraph->vertices ), $MAXIMUM_SUBGRAPH_SIZE - $subgraph->vertices );

    foreach my $set ( $first_powerset->elements ) {
        next if ( $set->size == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map( @$_, $set->elements ) ) );

        # all combinations of edges between the newly added nodes
        my $edges = Set::Object->new();
        foreach my $new_node ($new_nodes) {
            $edges->insert( grep( $new_nodes->contains( $_->[1] ), $subgraph->edges_from($new_node) ) );
        }
        my $second_powerset = _powerset( $edges, 0, $edges->size );
        foreach my $new_set ( $second_powerset->elements ) {
            my $local_subgraph = $subgraph->copy_graph;
            $local_subgraph->add_edges( $set->elements, $new_set->elements );
            _emit( $local_subgraph, $relation_ref );
            if ( $local_subgraph->vertices < $MAXIMUM_SUBGRAPH_SIZE ) {
                _enumerate_connected_subgraphs_recursive( $graph, $local_subgraph, Set::Object::union( $prohibited_nodes, $neighbours ), $relation_ref );
            }
        }
    }
}

sub _cross_set {
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
        }
    }
    return $cross_set;
}

sub _powerset {
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

sub _emit {
    my ( $subgraph, $relation_ref ) = @_;
    my %edges;
    my @list_representation;
    my %nodes;
    my @sorted_nodes;
    my @emit_structure;
    foreach my $edge ( $subgraph->edges() ) {
        $edges{ $edge->[0] }->{ $edge->[1] } = $relation_ref->{ $edge->[0] }->{ $edge->[1] };
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
                $emit_structure[$i]->[$j] = $RELATION_IDS->{ $edges{$node_1}->{$node_2} };
                die( "Self-loop: " . join( ", ", @list_representation ) ) if ( $i == $j );
            }
            else {
                $emit_structure[$i]->[$j] = 0;
            }
        }
    }
    #printf OUT ( "%s\t%d\n", join( " ", map( join( " ", @$_ ), @emit_structure ) ), scalar(@emit_structure) );
    #printf ( "%s\t%d\n", join( " ", map( join( " ", @$_ ), @emit_structure ) ), scalar(@emit_structure) );
}

sub _get_attribute {
    my ( $self, $name ) = @_;
    croak($GET_ATTRIBUTE_USAGE) if ( @_ != 2 );

    # retrieve attribute handle from cache
    return $self->{"attributes"}->{$name} if ( exists( $self->{"attributes"}->{$name} ) );

    # try p-attribute first ...
    my $att = $self->{"corpus_handle"}->attribute( $name, "p" );

    # ... then try s-attribute
    $att = $self->{"corpus_handle"}->attribute( $name, "s" ) unless ( defined $att );

    # ... finally try a-attribute
    $att = $self->{"corpus_handle"}->attribute( $name, "a" ) unless ( defined $att );
    croak "Can't open attribute " . $self->{"corpus"} . ".$name, sorry." unless ( defined $att );

    # store attribute handle in cache
    $self->{"attributes"}->{$name} = $att;
    return $att;
}

sub DESTROY {
    my ($self) = @_;
    undef $self->{"cqp"};
    undef $self->{"corpus_handle"};
    return;
}

__PACKAGE__->run(@ARGV) unless caller;

sub run {
    my ( $class, @args ) = @_;
    my $get_subgraphs = connect_to_corpus($class);
    $get_subgraphs->get_subgraphs("test");
    return;
}

1;
