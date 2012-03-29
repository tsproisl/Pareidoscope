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
Readonly my $MAXIMUM_DEPTH               => 2;
Readonly my $UNLIMITED_NUMBER_OF_FIELDS  => -1;
Readonly my $GET_ATTRIBUTE_USAGE         => 'Usage: $att_handle = $self->_get_attribute($name);';
Readonly my $RELATION_IDS                => Storable::retrieve('dependency_relations.dump');
Readonly my $FREQUENCY_THRESHOLD         => 2;

use localdata_client;

# use Data::Dumper;    # Dumper

# use List::Util;              # first max maxstr min minstr reduce shuffle sum
# use List::MoreUtils;         # "the stuff missing in List::Util"
use Log::Log4perl qw(:easy);    # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
Log::Log4perl->easy_init($DEBUG);

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
    $self->{"localdata"} = localdata_client->init('oanc', ['127.0.0.1', 4878, 8487]);
    bless $self, $class;
    return $self;
}

sub get_subgraphs {
    my ( $self, $word ) = @_;
    my $result_ref    = [];
    my $s_handle      = $self->_get_attribute("s");
    my $s_id_handle   = $self->_get_attribute("s_id");
    my $indep_handle  = $self->_get_attribute("indep");
    my $outdep_handle = $self->_get_attribute("outdep");
    $self->{"cqp"}->exec( sprintf "A = [word = \"%s\" %%c]", $word );
    my @matches      = $self->{"cqp"}->exec("tabulate A match");
    my $loop_counter = 0;
SENTENCE:

    foreach my $match (@matches) {
        $loop_counter++;

        #last SENTENCE if($loop_counter > 200);
        DEBUG( sprintf "%d/%d", $loop_counter, scalar @matches );

        #my $s_id = $s_id_handle->cpos2str($match);
        #DEBUG( "$s_id\n");
        my ( $start, $end ) = $s_handle->cpos2struc2cpos($match);
        my @indeps  = $indep_handle->cpos2str( $start .. $end );
        my @outdeps = $outdep_handle->cpos2str( $start .. $end );
        my %relation;
        my %reverse_relation;
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
                $dep =~ m/^(?<relation>[^(]+)[(]0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/xms;
                my $target = $cpos + $LAST_PAREN_MATCH{"offset"};
		next if ($cpos == $target);
                $relation{$cpos}->{$target}         = $LAST_PAREN_MATCH{"relation"};
                $reverse_relation{$target}->{$cpos} = $LAST_PAREN_MATCH{"relation"};
                $graph->add_edge( $cpos, $target );
            }
        }
        my $subgraph = Graph::Directed->new();
        $subgraph->add_vertex($match);
        _emit( $match, $subgraph, \%relation, $result_ref );
        #my $prohibited_nodes = Set::Object->new($match);
        #_enumerate_connected_subgraphs_recursive( $match, $graph, $subgraph, $prohibited_nodes, \%relation, \%reverse_relation, 1, $result_ref );
	my $prohibited_edges = Set::Object->new();
        _enumerate_connected_subgraphs_recursive( $match, $graph, $subgraph, $prohibited_edges, \%relation, \%reverse_relation, 1, $result_ref );
    }

    Storable::nstore $result_ref, 'subgraphs.ref';
    return $result_ref;
}

sub _get_frequencies {
    my ($self, $result_ref, $word) = @_;
    my @queue;
    my $r1 = 0;
    my $n = 28746592400;
    foreach my $size ( 1 .. $MAXIMUM_SUBGRAPH_SIZE ) {
        foreach my $subgraph (sort keys %{$result_ref->[$size]}) {
	    foreach my $position (sort keys %{$result_ref->[$size]->{$subgraph}}) {
		my $frequency = $result_ref->[$size]->{$subgraph}->{$position};
		$r1 += $frequency;
		push(@queue, [$subgraph, $position, 1, $frequency]) if ($frequency >= $FREQUENCY_THRESHOLD);
	    }
	}
    }
    my $dbh = DBI->connect( "dbi:SQLite:${word}_subgraphs.sqlite" ) or die( "Cannot connect to ${word}_subgraphs.sqlite: $DBI::errstr" );
    $dbh->do("PRAGMA encoding = 'UTF-8'");
    $dbh->do("PRAGMA cache_size = 50000");
    $dbh->do(
        qq{CREATE TABLE results (
			 rid INTEGER PRIMARY KEY,
			 qid INTEGER NOT NULL,
			 result TEXT NOT NULL,
			 position INTEGER NOT NULL,
                         mlen INTEGER NOT NULL,
			 o11 INTEGER NOT NULL,
			 c1 INTEGER NOT NULL,
			 am REAL,
			 UNIQUE (qid, result, position)
		     )}
    );
    $dbh->disconnect();
    $self->{"localdata"}->add_freq_and_am(\@queue, $r1, $n, "${word}_subgraphs.sqlite");
}

sub _enumerate_connected_subgraphs_recursive {
    #my ( $match, $graph, $subgraph, $prohibited_nodes, $relation_ref, $reverse_relation_ref, $depth, $result_ref ) = @_;
    my ( $match, $graph, $subgraph, $prohibited_edges, $relation_ref, $reverse_relation_ref, $depth, $result_ref ) = @_;

    # determine all edges to neighbouring nodes that are not
    # prohibited
    my $out_edges  = Set::Object->new();
    my $in_edges   = Set::Object->new();
    my $neighbours = Set::Object->new();
    my $neighbouring_edges = Set::Object->new();
    foreach my $node ( $subgraph->vertices ) {

        # outgoing edges
        foreach my $target ( keys %{ $relation_ref->{$node} } ) {
            #next if ( $prohibited_nodes->contains($target) );
	    next if ( $prohibited_edges->contains( "$node-$target" ) );
            $out_edges->insert( [ $node, $target ] );
            $neighbours->insert($target);
	    $neighbouring_edges->insert( "$node-$target" );
        }

        # incoming edges
        foreach my $origin ( keys %{ $reverse_relation_ref->{$node} } ) {
            #next if ( $prohibited_nodes->contains($origin) );
	    next if ( $prohibited_edges->contains( "$origin-$node" ) );
            $in_edges->insert( [ $origin, $node ] );
            $neighbours->insert($origin);
	    $neighbouring_edges->insert( "$origin-$node" );
        }
    }

    my $first_powerset = _cross_set( _powerset( $out_edges, 0, $MAXIMUM_SUBGRAPH_SIZE - $subgraph->vertices ), _powerset( $in_edges, 0, $MAXIMUM_SUBGRAPH_SIZE - $subgraph->vertices ), $MAXIMUM_SUBGRAPH_SIZE - $subgraph->vertices );

    foreach my $set ( $first_powerset->elements ) {
        next if ( $set->size == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map( @$_, $set->elements ) ) );

        # all combinations of edges between the newly added nodes
        my $edges = Set::Object->new();
	my $string_edges = Set::Object->new();
        foreach my $new_node ( $new_nodes->elements() ) {
            $edges->insert( grep( $new_nodes->contains( $_->[1] ), $graph->edges_from($new_node) ) );
        }
	$string_edges->insert( map { $_->[0] . '-' . $_->[1] } $edges->elements() );

        my $second_powerset = _powerset( $edges, 0, $edges->size );
        foreach my $new_set ( $second_powerset->elements ) {
            my $local_subgraph = $subgraph->copy_graph;
            $local_subgraph->add_edges( $set->elements, $new_set->elements );
            _emit( $match, $local_subgraph, $relation_ref, $result_ref );

            #if ( $local_subgraph->vertices < $MAXIMUM_SUBGRAPH_SIZE ) {
            if ( $local_subgraph->vertices < $MAXIMUM_SUBGRAPH_SIZE && $depth < $MAXIMUM_DEPTH ) {
                #_enumerate_connected_subgraphs_recursive( $match, $graph, $local_subgraph, Set::Object::union( $prohibited_nodes, $neighbours ), $relation_ref, $reverse_relation_ref, $depth + 1, $result_ref );
                _enumerate_connected_subgraphs_recursive( $match, $graph, $local_subgraph, Set::Object::union( $prohibited_edges, $neighbouring_edges, $string_edges ), $relation_ref, $reverse_relation_ref, $depth + 1, $result_ref );
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
    my ( $match, $subgraph, $relation_ref, $result_ref ) = @_;
    my %edges;
    my %incoming_edge;
    my @list_representation;
    my %nodes;
    my @sorted_nodes;
    my @emit_structure;
    foreach my $edge ( $subgraph->edges() ) {
        my ( $start, $end ) = @$edge;
        my $relation = $relation_ref->{$start}->{$end};
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
    my $node_index;
    for ( my $i = 0; $i <= $#sorted_nodes; $i++ ) {
        my $node_1 = $sorted_nodes[$i];
        if ( $node_1 == $match ) {
            $node_index = $i;
        }
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
    #$result_ref->[ scalar @emit_structure ]->{ join " ", map { join " ", @$_ } @emit_structure }->{$node_index}++;
    #my @bins = pack "(S*)>", map {@$_} @emit_structure;
    #my @strings = join " ", map { join " ", @$_ } @emit_structure;
    #DEBUG join( " ", map { join " ", @$_ } @emit_structure) . ": " . pack( "(S*)>", map {@$_} @emit_structure) . "\n";
    $result_ref->[ scalar @emit_structure ]->{ unpack("H*", pack("(S*)>", map {@$_} @emit_structure)) }->{$node_index}++;
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
    my $subgraphs = $get_subgraphs->get_subgraphs("give");
    #my $subgraphs = Storable::retrieve('subgraphs.ref');
    $get_subgraphs->_get_frequencies($subgraphs, "give");
    return;
}

1;
