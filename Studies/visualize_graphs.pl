#!/usr/bin/perl
package Graph::Visualize;

use 5.010;

use strict;
use warnings;
use open qw(:utf8 :std);
use utf8;

use Storable;
use version; our $VERSION = qv('0.0.1');

# use Carp;                    # carp croak
use Data::Dumper;    # Dumper

# use List::Util;              # first max maxstr min minstr reduce shuffle sum
# use List::MoreUtils;         # "the stuff missing in List::Util"
use Log::Log4perl qw(:easy);    # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
Log::Log4perl->easy_init($DEBUG);
use GraphViz;

use Readonly;
Readonly my $RELATION_IDS => { reverse %{ Storable::retrieve('dependency_relations.dump') } };

sub visualize_graph {
    my ( $graph, $position, $number ) = @_;

    # unpack graph
    my @linear_matrix = map { $RELATION_IDS->{$_} or undef } unpack( "(S*)>", pack( "H*", $graph ) );
    DEBUG join( ', ', @linear_matrix ) . "\n";
    my $number_of_nodes = sqrt $#linear_matrix + 1;
    my @matrix = map { [ @linear_matrix[ $_ * $number_of_nodes .. $_ * $number_of_nodes + $number_of_nodes - 1 ] ] } ( 0 .. $number_of_nodes - 1 );
    DEBUG Dumper \@matrix;

    # create GraphViz object
    my $gv = GraphViz->new(
        node => {
            shape    => 'plaintext',
            fontname => 'sans',
            fontsize => 10
        },
        edge => {
            fontname => 'sans',
            fontsize => 10
        }
    );

    # add nodes
    foreach my $i ( 0 .. $#matrix ) {
        if ( $i == $position ) {
            $gv->add_node( $i, label => 'node', shape => 'ellipse' );
        }
        else {
            $gv->add_node( $i, label => q{}, shape => 'ellipse', height => 0.1, width => 0.1 );
        }
    }

    # add edges
    foreach my $i ( 0 .. $#matrix ) {
        foreach my $j ( 0 .. $#matrix ) {
            next if ( !defined $matrix[$i]->[$j] );
            $gv->add_edge( $i => $j, label => $matrix[$i]->[$j] );
        }
    }

    # create PNG
    $gv->as_png("$number.png");

    return;
}

__PACKAGE__->run(@ARGV) unless caller;

sub run {
    my ( $class, @args ) = @_;
    my $subgraphs = Storable::retrieve('subgraphs.ref');
    my $number    = 1;
    foreach my $size ( 1 .. $#{$subgraphs} ) {
        my $i = 0;
    SUBGRAPH:
        foreach my $subgraph ( sort keys %{ $subgraphs->[$size] } ) {
            foreach my $position ( sort keys %{ $subgraphs->[$size]->{$subgraph} } ) {
                visualize_graph( $subgraph, $position, $number );
                $number++;
                $i++;
                last SUBGRAPH if ( $i >= 3 );
            }
        }
    }
    return;
}

1;
