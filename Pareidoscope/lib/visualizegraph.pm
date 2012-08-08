package visualizegraph;

use Dancer ':syntax';
use open qw(:utf8 :std);
use utf8;

use Data::Dumper;
use List::MoreUtils qw(any);
use GraphViz;

sub visualize_graph {
    my ($data) = @_;

    content_type 'image/png';

    my $graph    = param('graph');
    my $position = param('position');
    my $label    = param('label');
    my $bgcolor  = 'transparent';
    if ( any { ( !defined $_ ) || ( $_ eq q{} ) } ( $graph, $position, $label ) ) {
        my $gv = GraphViz->new(
            node => {
                shape    => 'plaintext',
                fontname => 'sans',
                fontsize => 10
            },
            bgcolor => $bgcolor
        );
        $gv->add_node( 'na', label => 'N/A' );
        return $gv->as_png();
    }

    # unpack graph
    my @linear_matrix = map { $data->{"number_to_relation"}->[$_] or undef } unpack( "(S*)>", pack( "H*", $graph ) );

    # debug join ', ', unpack( "(S*)>", pack( "H*", $graph ));
    # debug Dumper(\@linear_matrix);
    my $number_of_nodes = sqrt $#linear_matrix + 1;
    my @matrix = map { [ @linear_matrix[ $_ * $number_of_nodes .. $_ * $number_of_nodes + $number_of_nodes - 1 ] ] } ( 0 .. $number_of_nodes - 1 );

    # debug Dumper(\@matrix);

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
        },
        bgcolor => $bgcolor
    );

    # add nodes
    foreach my $i ( 0 .. $#matrix ) {
        if ( $i == $position ) {
            $gv->add_node( $i, label => $label, shape => 'ellipse' );
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
    return $gv->as_png();
}

1;
