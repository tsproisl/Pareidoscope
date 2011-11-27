#!/usr/bin/perl

# Collect dependencies
# input: encoded corpus
# output: full database, chunks.out

package edge;

use warnings;
use strict;

sub new {
    my $class = shift;
    my ( $label, $x, $y ) = @_;
    my $self = {
        "label" => $label,                                    #sprintf( "%02d,%02d", $x, $y ),
        "x"     => $x,
        "y"     => $y,
        "id"    => sprintf( "%s%03d,%03d", $label, $x, $y )
    };
    return bless( $self, $class );
}

1;

package main;

use warnings;
use strict;
use open qw(:std :utf8);

use Data::Dumper;

use lib "/home/hpc/slli/slli02/localbin/lib/perl/5.10.0";
use DBI;

my $sentence_db = shift(@ARGV);
my $directory = shift(@ARGV);
my $database = shift(@ARGV);
my @sids = @ARGV;

my $maxloglevel = 3;
my $skipped = 0;

my $dbh = DBI->connect("dbi:SQLite:$database") or die("Cannot connect: $DBI::errstr");
my $sentence_dbh = DBI->connect("dbi:SQLite:$sentence_db") or die("Cannot connect: $DBI::errstr");

&create_indexes();

$dbh->disconnect();
$sentence_dbh->disconnect();

sub create_indexes {
    $dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
    my $gettypid = $dbh->prepare(qq{SELECT types.typid FROM types, gramis, lemmata WHERE types.type=? AND gramis.grami=? AND lemmata.lemma=? AND lemmata.wc=? AND types.gramid=gramis.gramid AND types.lemid=lemmata.lemid});
    my $getlemid = $dbh->prepare(qq{SELECT lemmata.lemid FROM lemmata WHERE lemmata.lemma=? AND lemmata.wc=?});
    $dbh->do(qq{COMMIT});

    $sentence_dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
    my $get_sentence_stuff = $sentence_dbh->prepare(qq{SELECT words, poses, lemmata, wcs, indeps, outdeps, positions FROM sentences WHERE sid=?});
    my $set_status = $sentence_dbh->prepare(qq{UPDATE sentences SET status = ? WHERE sid = ?});
    $sentence_dbh->do(qq{COMMIT});

    $sentence_dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
    foreach my $sid (@sids) {
	$set_status->execute(2, $sid);
    }
    $sentence_dbh->do(qq{COMMIT});

    my %typids;
    my @typids;

    my $ergcounter = 0;

    foreach my $sid (@sids) {
	$sentence_dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
	$set_status->execute(3, $sid);
	$get_sentence_stuff->execute($sid);
	my ( $words, $poses, $lemmata, $wcs, $indeps, $outdeps, $positions ) = $get_sentence_stuff->fetchrow_array();
	$sentence_dbh->do(qq{COMMIT});

        my ( @words, @poses, @lemmata, @wcs, @indeps, @outdeps, @positions );
        @words   = split( / /, $words );
        @poses   = split( / /, $poses );
        @lemmata = split( / /, $lemmata );
        @wcs     = split( / /, $wcs );
        @indeps  = map { s/^\|//; s/\|$//; $_ } split( / /, $indeps );
        @outdeps = map { s/^\|//; s/\|$//; $_ } split( / /, $outdeps );
        @positions = split( / /, $positions );

        $ergcounter++;

        # if (grep {$a = () = /\|/g; $a > 9} @outdeps) {
	#     &common_functions::log("Skipped sentence $ergcounter: " . join(" ", @words), 1, $maxloglevel);
	#     $skipped++;
	#     next;
        # }

        die("Damn, tabulate does not seem to work as expected!") unless ( scalar(@words) == scalar(@poses) and scalar(@words) == scalar(@lemmata) and scalar(@words) == scalar(@wcs) and scalar(@words) == scalar(@indeps) and scalar(@words) == scalar(@outdeps) and scalar(@words) == scalar(@positions) );

        #+--------> x
        #| a - - -
        #| - b - -
        #| - - c -
        #| - - - d
        #v
        #y
        my $matrix         = [];
        my $matrix_counter = 0;
        my %matrix_map;
        my %subgraphs;

        # Enter nodes
        foreach my $i ( 0 .. $#words ) {
            next unless ( $indeps[$i] or $outdeps[$i] );
            $matrix->[$matrix_counter]->[$matrix_counter] = [ $matrix_counter, $i ];

            #$matrix->[$matrix_counter]->[$matrix_counter] = $positions[$i];
            $matrix_map{$i} = $matrix_counter;
            $matrix_counter++;
        }

        # Enter edges
        foreach my $i ( 0 .. $#words ) {
            next unless ( $indeps[$i] or $outdeps[$i] );
            if ( $indeps[$i] ) {
                foreach my $dep ( split( /\|/, $indeps[$i] ) ) {
                    die("Doesn't match: $dep\n") unless ( $dep =~ m/^([^(]+)\((-?\d+)'*,0'*\)/ );
                    my $rel    = $1;
                    my $offset = $2;
                    $offset = "+" . $offset unless ( substr( $offset, 0, 1 ) eq "-" );
                    my $j = eval "$i$offset";
                    next if ( $matrix_map{$i} == $matrix_map{$j} );
                    $matrix->[ $matrix_map{$i} ]->[ $matrix_map{$j} ] = edge->new( $rel, $matrix_map{$i}, $matrix_map{$j} );
                }
            }
            if ( $outdeps[$i] ) {
                foreach my $dep ( split( /\|/, $outdeps[$i] ) ) {
                    die("Doesn't match: $dep\n") unless ( $dep =~ m/^([^(]+)\(0'*,(-?\d+)'*\)/ );
                    my $rel    = $1;
                    my $offset = $2;
                    $offset = "+" . $offset unless ( substr( $offset, 0, 1 ) eq "-" );
                    my $j = eval "$i$offset";
                    next if ( $matrix_map{$i} == $matrix_map{$j} );
                    $matrix->[ $matrix_map{$j} ]->[ $matrix_map{$i} ] = edge->new( $rel, $matrix_map{$j}, $matrix_map{$i} );
                }
            }
        }

        # Iterate over nodes
        foreach my $i ( 0 .. $#$matrix ) {

            # do two hops in every direction
            my %edges;
            my @nodes = ($i);

            foreach my $j ( 1 .. 2 ) {
            #foreach my $j (1) {
                my %nodes;
                while ( defined( my $node = shift(@nodes) ) ) {

                    # incoming edges
                    foreach my $edge ( grep( ( ref($_) and ( ref($_) eq "edge" ) ), map( $matrix->[$node]->[$_], ( 0 .. $#$matrix ) ) ) ) {
                        $edges{ $edge->{"id"} } = $edge;
                        $nodes{ $edge->{"y"} }++;
                    }

                    # outgoing edges
                    foreach my $edge ( grep( ( ref($_) and ( ref($_) eq "edge" ) ), map( $matrix->[$_]->[$node], ( 0 .. $#$matrix ) ) ) ) {
                        $edges{ $edge->{"id"} } = $edge;
                        $nodes{ $edge->{"x"} }++;
                    }
                }
                @nodes = keys(%nodes);
            }

            # find connected subgraphs
            my $gcp_iterator = get_connected_powerset( $i, values %edges );
            while ( my $subgraph_edges = $gcp_iterator->() ) {

                # build local matrix
                my $local_matrix = [];
                foreach my $edge (@$subgraph_edges) {
                    $local_matrix->[ $edge->{"x"} ]->[ $edge->{"y"} ] = $edge;
                    $local_matrix->[ $edge->{"x"} ]->[ $edge->{"x"} ] = $matrix->[ $edge->{"x"} ]->[ $edge->{"x"} ];
                    $local_matrix->[ $edge->{"y"} ]->[ $edge->{"y"} ] = $matrix->[ $edge->{"y"} ]->[ $edge->{"y"} ];
                }

                #print "local matrix:\n";
                #print Dumper($local_matrix);

                # n-th order characterizations of nodes
                my $norm_counter = 0;
                my $norm_matrix  = [];

                my @ordered_nodes = sort { &get_nth_order( $a, $local_matrix, 0 ) cmp &get_nth_order( $b, $local_matrix, 0 ) or &get_nth_order( $a, $local_matrix, 1 ) cmp &get_nth_order( $b, $local_matrix, 1 ) or &get_nth_order( $a, $local_matrix, 2 ) cmp &get_nth_order( $b, $local_matrix, 2 ) } grep(defined($local_matrix->[$_]->[$_]), (0 .. $#$local_matrix));
                #my @ordered_nodes = sort { &get_nth_order( $a, $local_matrix, 0 ) cmp &get_nth_order( $b, $local_matrix, 0 ) or &get_nth_order( $a, $local_matrix, 1 ) cmp &get_nth_order( $b, $local_matrix, 1 ) } grep( defined( $local_matrix->[$_]->[$_] ), ( 0 .. $#$local_matrix ) );

                #print Dumper($local_matrix);
                my %access_ordered_nodes = map( ( $local_matrix->[ $ordered_nodes[$_] ]->[ $ordered_nodes[$_] ]->[0], $_ ), ( 0 .. $#ordered_nodes ) );
                foreach my $i (@ordered_nodes) {
                    $norm_matrix->[$norm_counter]->[$norm_counter] = $i;

                    # incoming edges
                    foreach my $edge ( grep( ( defined($_) and ( ref($_) eq "edge" ) ), map( $local_matrix->[$i]->[$_], ( 0 .. $#$local_matrix ) ) ) ) {
                        $norm_matrix->[$norm_counter]->[ $access_ordered_nodes{ $edge->{"y"} } ] = edge->new( $edge->{"label"}, $norm_counter, $access_ordered_nodes{ $edge->{"y"} } ) unless ( defined( $norm_matrix->[$norm_counter]->[ $access_ordered_nodes{ $edge->{"y"} } ] ) );
                    }

                    # outgoing edges
                    foreach my $edge ( grep( ( defined($_) and ( ref($_) eq "edge" ) ), map( $local_matrix->[$_]->[$i], ( 0 .. $#$local_matrix ) ) ) ) {
                        $norm_matrix->[ $access_ordered_nodes{ $edge->{"x"} } ]->[$norm_counter] = edge->new( $edge->{"label"}, $access_ordered_nodes{ $edge->{"x"} }, $norm_counter ) unless ( defined( $norm_matrix->[ $access_ordered_nodes{ $edge->{"x"} } ]->[$norm_counter] ) );
                    }
                    $norm_counter++;
                }
                my $relative_subgraph = join(
                    " ",
                    map { $_->{"label"} . "(" . $_->{"y"} . "," . $_->{"x"} . ")" } grep { defined($_) and ( ref($_) eq "edge" ) } map {
                        my $n = $_;
                        map { $norm_matrix->[$_]->[$n] } ( 0 .. $#$norm_matrix )
                        } ( 0 .. $#$norm_matrix )
                );
                my $absolute_subgraph = join(
                    " ",
                    map { $_->{"label"} . "(" . $matrix->[ $ordered_nodes[ $_->{"y"} ] ]->[ $ordered_nodes[ $_->{"y"} ] ]->[1] . "," . $matrix->[ $ordered_nodes[ $_->{"x"} ] ]->[ $ordered_nodes[ $_->{"x"} ] ]->[1] . ")" } grep { defined($_) and ( ref($_) eq "edge" ) } map {
                        my $n = $_;
                        map { $norm_matrix->[$_]->[$n] } ( 0 .. $#$norm_matrix )
                        } ( 0 .. $#$norm_matrix )
                );

                #print "$matrix->[$i]->[$i]->[1] ($access_ordered_nodes{$i}): ", $relative_subgraph, "\n";
                $gettypid->execute( $words[ $matrix->[$i]->[$i]->[1] ], $poses[ $matrix->[$i]->[$i]->[1] ], $lemmata[ $matrix->[$i]->[$i]->[1] ], $wcs[ $matrix->[$i]->[$i]->[1] ] );
                my $typid = ( $gettypid->fetchrow_array )[0];
                $getlemid->execute( $lemmata[ $matrix->[$i]->[$i]->[1] ], $wcs[ $matrix->[$i]->[$i]->[1] ] );
                my $lemid = ( $getlemid->fetchrow_array )[0];
                $subgraphs{ ($absolute_subgraph) } = [ $typid, $lemid, $access_ordered_nodes{$i}, $relative_subgraph ];
            }
        }
	my $outfile = sprintf("%s/out/%06d", $directory, $sid);
	open(my $do, ">", $outfile) or die("Cannot open $outfile: $!");
        print $do join( "\n", map( join( "\t", @$_ ), sort { $a->[2] cmp $b->[2] } values %subgraphs ) ), "\n";
	close($do) or die("Cannot close $outfile: $!");
	$sentence_dbh->do(qq{BEGIN IMMEDIATE TRANSACTION});
	$set_status->execute(4, $sid);
	$sentence_dbh->do(qq{COMMIT});
    }
}

sub get_nth_order {
    my ( $node, $matrix, $depth ) = @_;
    my @local_result;

    # incoming edges
    foreach my $edge ( grep( ( defined($_) and ( ref($_) eq "edge" ) ), map( $matrix->[$node]->[$_], ( 0 .. $#$matrix ) ) ) ) {
        if ( $depth == 0 ) {
            push( @local_result, "<" . $edge->{"label"} );
        }
        else {
            push( @local_result, "<" . $edge->{"label"} . "(" . &get_nth_order( $edge->{"y"}, $matrix, $depth - 1 ) . ")" );
        }
    }

    # outgoing edges
    foreach my $edge ( grep( ( defined($_) and ( ref($_) eq "edge" ) ), map( $matrix->[$_]->[$node], ( 0 .. $#$matrix ) ) ) ) {
        if ( $depth == 0 ) {
            push( @local_result, ">" . $edge->{"label"} );
        }
        else {
            push( @local_result, ">" . $edge->{"label"} . "(" . &get_nth_order( $edge->{"x"}, $matrix, $depth - 1 ) . ")" );
        }
    }

    return join( "", sort @local_result );
}

sub insertandreturnid {
    my ( $insert, $get, $argsref ) = @_;
    $insert->execute(@$argsref);
    $get->execute(@$argsref);
    my $all  = $get->fetchall_arrayref;
    my $rows = scalar(@$all);
    die("Query returns more than one ID") if ( $rows > 1 );
    die("Query returns no ID") if ( $rows < 1 );
    my ($id) = @{ $all->[0] };
    return $id;
}

# my $gcp_iterator = get_connected_powerset($node, @set);
# while (my $subgraph = $gcp_iterator->()) {
#   # do something
# }
sub get_connected_powerset {
    my ( $node, @set ) = @_;
    my $ps_iterator = &powerset_lazy(@set);
    return sub {
        while ( my $aref = $ps_iterator->() ) {
            next if ( @$aref > 15 );

            #print Dumper($aref);
            if ( &connected( [@$aref], $node ) ) {
                return $aref;
            }
        }
    };
}

sub powerset_lazy {
    my @set      = @_;
    my @odometer = (1) x @set;
    my $FINISHED;
    return sub {
        return if $FINISHED;
        my @result;
        my $adjust = 1;
        for ( 0 .. $#odometer ) {
            push @result, $set[$_] if $odometer[$_];
            $adjust = $odometer[$_] = 1 - $odometer[$_] if $adjust;
        }
        $FINISHED = ( @result == 0 );
        \@result;
    };
}

sub connected {
    my ( $aref, $node ) = @_;
    return 0 unless (@$aref);
OUTER: while ( my $edge = shift(@$aref) ) {

        #return 0 and print "foo\n" unless (ref($edge) eq "edge");
        # connects directly to node
        next OUTER if ( $edge->{"x"} == $node or $edge->{"y"} == $node );

        # connects to other edge
    INNER: foreach my $elem (@$aref) {
            next INNER unless ( ref($elem) eq "edge" );
            next OUTER if ( $edge->{"x"} == $elem->{"x"}
                or $edge->{"x"} == $elem->{"y"}
                or $edge->{"y"} == $elem->{"x"}
                or $edge->{"y"} == $elem->{"y"} );
        }
        return 0;
    }
    return 1;
}

1;
