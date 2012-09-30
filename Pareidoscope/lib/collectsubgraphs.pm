package collectsubgraphs;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use English qw( -no_match_vars );

use Graph::Directed;
use Set::Object;
use DBI;
use Time::HiRes;
use List::MoreUtils qw(first_index);
use Carp;    # carp croak
use IO::Socket;
use JSON qw();

use Readonly;
Readonly my $UNLIMITED_NUMBER_OF_FIELDS => -1;
Readonly my $GET_ATTRIBUTE_USAGE        => 'Usage: $att_handle = $self->_get_attribute($name);';

use executequeries;
use localdata_client;

sub get_subgraphs {
    my ( $data, $freq ) = @_;
    my $return_vars;
    my ( $qids, $qid );
    my $frequency_threshold      = 200000;
    my $subgraph_types_threshold = 750000;
    my $s_handle                 = $data->get_attribute("s");
    my $s_id_handle              = $data->get_attribute("s_id");
    my $indep_handle             = $data->get_attribute("indep");
    my $outdep_handle            = $data->get_attribute("outdep");
    my $root_handle              = $data->get_attribute("root");
    my $get_relation_ids         = $data->{"dbh"}->prepare(qq{SELECT relation, depid FROM dependencies});
    my $check_cache              = database->prepare(qq{SELECT qid, r1, n FROM queries WHERE corpus=? AND class=? AND query=? AND threshold=?});
    my $insert_query             = database->prepare(qq{INSERT INTO queries (corpus, class, query, threshold, qlen, time, r1, n) VALUES (?, ?, ?, ?, ?, strftime('%s','now'), ?, ?)});
    my $update_timestamp         = database->prepare(qq{UPDATE queries SET time=strftime('%s','now') WHERE qid=?});
    $get_relation_ids->execute();
    my %relation_id = map { @{$_} } @{ $get_relation_ids->fetchall_arrayref() };
    my %specifics = (
        "name"  => "dep",
        "class" => "strucd"
    );
    my $localdata = localdata_client->init( $data->{"active"}->{"localdata"}, @{ $data->{"active"}->{"machines"} } );
    my ( $query, $unlex_query, $title, $anchor, $query_length, $ngram_ref ) = executequeries::build_query($data);

    # # TODO
    # # "word"/"lemma" und Wortform/Lemma aus $query extrahieren
    # my %node_restriction;
    # if ($query =~ m/^[[](?<type>word|lemma)='(?<type_value>[^']+)' .*? (?:(?<gram>pos|wc)='(?<gram_value>[^']+)')?/xms) {
    # 	$node_restriction{$LAST_PAREN_MATCH{'type'}} = $LAST_PAREN_MATCH{'type_value'};
    # 	$node_restriction{$LAST_PAREN_MATCH{'gram'}} = $LAST_PAREN_MATCH{'gram_value'} if (defined $LAST_PAREN_MATCH{'gram'});
    # }
    # else {
    #    croak "Unexpected query: '$query'";
    # }
    $return_vars->{"query_anchor"}       = $anchor;
    $return_vars->{"query_title"}        = $title;
    $return_vars->{"threshold"}          = param("threshold");
    $return_vars->{"return_type"}        = param("return_type");
    $return_vars->{"frequency"}          = $freq;
    $return_vars->{"frequency_too_high"} = $freq >= $frequency_threshold;
    $return_vars->{"frequency_too_low"}  = $freq < param("threshold");
    return $return_vars if ( $freq == 0 );
    return $return_vars if ( $return_vars->{"frequency_too_high"} );
    return $return_vars if ( $return_vars->{"frequency_too_low"} );

    # check cache database
    $check_cache->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold") );
    $qids = $check_cache->fetchall_arrayref;
    if ( scalar(@$qids) == 1 ) {
        $qid = $qids->[0]->[0];
        $update_timestamp->execute($qid);
        my $dbh = DBI->connect( "dbi:SQLite:" . config->{"user_data"} . "/$qid" ) or croak("Cannot connect: $DBI::errstr");
        $dbh->do("PRAGMA encoding = 'UTF-8'");
        my $get_subgraph_types = $dbh->prepare(qq{SELECT COUNT(*) FROM results WHERE qid=?});
        $get_subgraph_types->execute($qid);
        my $subgraph_types = ( $get_subgraph_types->fetchrow_array )[0];
        $return_vars->{"ngram_tokens"}         = $qids->[0]->[1];
        $return_vars->{"ngram_types"}          = $subgraph_types;
        $return_vars->{"too_many_ngram_types"} = $subgraph_types >= $subgraph_types_threshold;
    }
    elsif ( scalar(@$qids) == 0 ) {
        my $result_ref      = [];
        my $r1              = 0;
        my $t0              = [ &Time::HiRes::gettimeofday() ];
        my $cached_query_id = $data->{"cache"}->query( -corpus => $data->{"active"}->{"corpus"}, -query => $query );
        my $t1              = [ &Time::HiRes::gettimeofday() ];
        my $sentence        = $data->get_attribute("s");
        my @matches         = $data->{"cqp"}->exec("tabulate $cached_query_id match, matchend");
        my $t2              = [ &Time::HiRes::gettimeofday() ];

    SENTENCE:
        foreach my $m (@matches) {
            my ( $match, $matchend ) = split( /\t/, $m );
            my $match_length = ( $matchend - $match ) + 1;
            croak("Match length: $match_length != 1") if ( $match_length != 1 );
            my ( $start, $end ) = $s_handle->cpos2struc2cpos($match);
            my @indeps  = $indep_handle->cpos2str( $start .. $end );
            my @outdeps = $outdep_handle->cpos2str( $start .. $end );
            my $root    = first_index { $_ eq 'root' } $root_handle->cpos2str( $start .. $end );

            # Skip rootless sentences
            next SENTENCE if ( !defined $root );

            $root += $start;
            my %relation;
            my %reverse_relation;
            my $graph = Graph::Directed->new();

            foreach my $i ( 0 .. $#outdeps ) {
                $indeps[$i]  =~ s/^[|]//xms;
                $indeps[$i]  =~ s/[|]$//xms;
                $outdeps[$i] =~ s/^[|]//xms;
                $outdeps[$i] =~ s/[|]$//xms;
                my @out = split /[|]/xms, $outdeps[$i];
                next SENTENCE if ( scalar( () = split /[|]/xms, $indeps[$i], $UNLIMITED_NUMBER_OF_FIELDS ) + scalar @out > $data->{"active"}->{"subgraph_edges"} );
                my $cpos = $start + $i;
                foreach my $dep (@out) {
                    $dep =~ m/^(?<relation>[^(]+)[(]0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/xms;
                    my $target = $cpos + $LAST_PAREN_MATCH{"offset"};
                    next if ( $cpos == $target );
                    $relation{$cpos}->{$target}         = $LAST_PAREN_MATCH{"relation"};
                    $reverse_relation{$target}->{$cpos} = $LAST_PAREN_MATCH{"relation"};
                    $graph->add_edge( $cpos, $target );
                }
            }

            # Skip unconnected graphs (necessary because of a bug in the current version of the Stanford Dependencies converter)
            next SENTENCE if ( ( $graph->vertices() > 1 ) && ( !$graph->is_weakly_connected() ) );

            # check if all vertices are reachable from the root
            my $graph_successors = Set::Object->new( $root, $graph->all_successors($root) );
            my $graph_vertices = Set::Object->new( $graph->vertices() );
            next SENTENCE if ( $graph_successors->not_equal($graph_vertices) );

            my $subgraph = Graph::Directed->new();
            $subgraph->add_vertex($match);
            _emit( $match, $subgraph, \%relation, $result_ref, \%relation_id );
            my $prohibited_edges = Set::Object->new();
            _enumerate_connected_subgraphs_recursive( $data, $match, $graph, $subgraph, $prohibited_edges, \%relation, \%reverse_relation, 1, $result_ref, \%relation_id );
        }
        my @queue;
        foreach my $size ( 1 .. $data->{"active"}->{"subgraph_size"} ) {
            foreach my $subgraph ( sort keys %{ $result_ref->[$size] } ) {
                foreach my $position ( sort keys %{ $result_ref->[$size]->{$subgraph} } ) {
                    my $frequency = $result_ref->[$size]->{$subgraph}->{$position};
                    $r1 += $frequency;
                    push @queue, [ $subgraph, $position, 1, $frequency ] if ( $frequency >= param("threshold") );
                }
            }
        }
        $return_vars->{"ngram_tokens"} = $r1;
        return $return_vars if ( $r1 == 0 );
        $return_vars->{"ngram_types"}          = scalar @queue;
        $return_vars->{"too_many_ngram_types"} = $return_vars->{"ngram_types"} >= $subgraph_types_threshold;
        return $return_vars if ( $return_vars->{"too_many_ngram_types"} );

        # insert into cache database
        $insert_query->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold"), $query_length, $r1, $data->{"active"}->{'subgraphs'} ) or croak( $insert_query->errstr );
        $check_cache->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold") );
        $qid = ( $check_cache->fetchrow_array )[0];
        croak('qid is undef!') if ( !defined $qid );
        my $t3 = [ &Time::HiRes::gettimeofday() ];

        my $dbh = executequeries::create_new_db($qid);
        $dbh->disconnect();
        $localdata->add_freq_and_am( \@queue, $r1, $data->{"active"}->{"subgraphs"}, $qid );
        my $t4 = [ &Time::HiRes::gettimeofday() ];
        $return_vars->{"execution_times"} = [ map( sprintf( "%.2f", $_ ), ( Time::HiRes::tv_interval( $t0, $t1 ), Time::HiRes::tv_interval( $t1, $t2 ), Time::HiRes::tv_interval( $t2, $t3 ), Time::HiRes::tv_interval( $t3, $t4 ) ) ) ];
    }
    else {
        croak("Feel proud: you witness an extremely unlikely behaviour of this website.");
    }

    %$return_vars = ( %$return_vars, %{ _create_table( $data, $query, $qid ) } );

    foreach my $param ( keys %{ params() } ) {
        next if ( param($param) eq q{} );
        $return_vars->{"previous_href"}->{$param} = $return_vars->{"next_href"}->{$param} = param($param);
    }
    $return_vars->{"previous_href"}->{"start"} = param("start") - 40;
    $return_vars->{"next_href"}->{"start"}     = param("start") + 40;
    return $return_vars;
}

sub lexical_subgraph_query {
    my ($data) = @_;

    # gibt es Lexikalisierung?
    # unlexikalisierte Struktur abfragen
    # lexikalisierte Struktur abgfragen
    # Kookkurrenzen aggregieren
    # Assoziationsmaß berechnen
    # Im Cache ablegen
    # Visualisierung: wie die Beziehung zwischen einer Spalte und einem bestimmten Knoten deutlich machen? Farben?
    ...;
}

sub _create_table {
    my ( $data, $query, $qid ) = @_;
    my $vars;
    my %specifics = (
        "map"   => "number_to_relation",
        "class" => "strucd"
    );
    my $dbh = DBI->connect( "dbi:SQLite:" . config->{"user_data"} . "/$qid" ) or croak("Cannot connect: $DBI::errstr");
    $dbh->do("PRAGMA encoding = 'UTF-8'");
    $dbh->do("PRAGMA cache_size = 50000");
    my $filter_length = q{};
    my $filter_pos    = q{};
    my $get_top_40    = $dbh->prepare( qq{SELECT result, position, mlen, o11, c1, am FROM results WHERE qid=? $filter_length $filter_pos ORDER BY am DESC, o11 DESC LIMIT } . param("start") . qq{, 40} );
    $get_top_40->execute($qid);
    my $rows = $get_top_40->fetchall_arrayref;

    ###$vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( $cgi, {}, qw(m c rt dt start t tt p w i ht h ct) );
    # id fch flen frel ftag fwc fpos q rt
    foreach my $param ( keys %{ params() } ) {
        next if ( param($param) eq q{} );
        if ( List::MoreUtils::any { $_ eq $param } qw(fch flen frel ftag fwc fpos) ) {
            $vars->{$param} = param($param);
        }
        else {
            $vars->{"hidden_states"}->{$param} = param($param);
        }
    }
    $vars->{"hidden_states"}->{"start"} = 0;

    ### NOTWENDIG?
    $vars->{"pos_tags"} = $data->{"number_to_tag"};
    $vars->{"word_classes"} = [ "", sort keys %{ config->{"tagsets"}->{ $data->{"active"}->{"tagset"} } } ];
    my $counter = param("start");

    foreach my $row (@$rows) {
        my ( $result, $position, $mlen, $o11, $c1, $g2 ) = @$row;
        $row             = {};
        $g2              = sprintf( "%.5f", $g2 );
        $row->{"g"}      = $g2;
        $row->{"cofreq"} = $o11;
        $row->{"ngfreq"} = $c1;
        my ( $strucnlink, $lexnlink, $freqlink, $ngfreqlink, $g2span );
        my ( @result, @ngram, @display_ngram, $display_ngram, );
        $result =~ s/[<>]//g;
        @ngram = map( $data->{ $specifics{"map"} }->[$_], map( hex($_), unpack( "(a4)*", $result ) ) );
        @display_ngram = @ngram;

        #$display_ngram = join ' ', grep {defined} @display_ngram;
        $display_ngram = "graph=$result&position=$position";

        #$display_ngram[$position] = "<em>$display_ngram[$position]";
        #$display_ngram[ $position + $mlen - 1 ] .= "</em>";
        #$display_ngram = join( " ", @display_ngram );
        $row->{"display_ngram"} = $display_ngram;

        # CREATE LEX AND STRUC LINKS
        my $query_copy = $query;
        $query_copy =~ s/^\[//xms;
        $query_copy =~ s/\] within s$//xms;
        $query_copy =~ s/%c//xmsg;
        $query_copy =~ s/\s+/ /xmsg;
        my %node_restriction;
        while ( $query_copy =~ m/(?<key>\S+)='(?<value>[^']+)'/xmsg ) {
            $node_restriction{ $LAST_PAREN_MATCH{'key'} } = $LAST_PAREN_MATCH{'value'};
        }
        $row->{"struc_href"}  = { 'return_type' => param('return_type'), 'threshold' => param('threshold'), 's' => 'Link', corpus => param('corpus'), 'graph' => $result, 'position' => $position, 'ignore_case' => params->{'ignore_case'}, %node_restriction };
        $row->{"lex_href"}    = { 'return_type' => param('return_type'), 'threshold' => param('threshold'), 's' => 'Link', corpus => param('corpus'), 'graph' => $result, 'position' => $position, 'ignore_case' => params->{'ignore_case'}, %node_restriction };
        $row->{"cofreq_href"} = { 'return_type' => param('return_type'), 'threshold' => param('threshold'), 's' => 'Link', corpus => param('corpus'), 'graph' => $result, 'position' => $position, 'ignore_case' => params->{'ignore_case'}, %node_restriction };
        $row->{"ngfreq_href"} = { 'return_type' => param('return_type'), 'threshold' => param('threshold'), 's' => 'Link', corpus => param('corpus'), 'graph' => $result, 'ignore_case' => params->{'ignore_case'} };
        $counter++;
        $row->{"number"} = $counter;
    }
    $vars->{"rows"} = $rows;
    return $vars;
}

sub _enumerate_connected_subgraphs_recursive {
    my ( $data, $match, $graph, $subgraph, $prohibited_edges, $relation_ref, $reverse_relation_ref, $depth, $result_ref, $relation_id_ref ) = @_;

    # determine all edges to neighbouring nodes that are not
    # prohibited
    my $out_edges          = Set::Object->new();
    my $in_edges           = Set::Object->new();
    my $neighbours         = Set::Object->new();
    my $neighbouring_edges = Set::Object->new();
    foreach my $node ( $subgraph->vertices ) {

        # outgoing edges
        foreach my $target ( keys %{ $relation_ref->{$node} } ) {
            next if ( $prohibited_edges->contains("$node-$target") );
            $out_edges->insert( [ $node, $target ] );
            $neighbours->insert($target);
            $neighbouring_edges->insert("$node-$target");
        }

        # incoming edges
        foreach my $origin ( keys %{ $reverse_relation_ref->{$node} } ) {
            next if ( $prohibited_edges->contains("$origin-$node") );
            $in_edges->insert( [ $origin, $node ] );
            $neighbours->insert($origin);
            $neighbouring_edges->insert("$origin-$node");
        }
    }

    my $first_powerset = _cross_set( _powerset_node_based( $out_edges, 0, $data->{"active"}->{"subgraph_size"} - $subgraph->vertices, 1 ), _powerset_node_based( $in_edges, 0, $data->{"active"}->{"subgraph_size"} - $subgraph->vertices, 0 ), $data->{"active"}->{"subgraph_size"} - $subgraph->vertices );

    foreach my $set ( $first_powerset->elements() ) {
        next if ( $set->size() == 0 );
        my $new_nodes = Set::Object::intersection( $neighbours, Set::Object->new( map { @{$_} } $set->elements() ) );

        # all combinations of edges between the newly added nodes
        my $edges        = Set::Object->new();
        my $string_edges = Set::Object->new();
        foreach my $new_node ( $new_nodes->elements() ) {
            $edges->insert( grep { $new_nodes->contains( $_->[1] ) } $graph->edges_from($new_node) );
        }
        $string_edges->insert( map { $_->[0] . q{-} . $_->[1] } $edges->elements() );

        my $second_powerset = _powerset_edges( $edges, 0, $edges->size() );
        foreach my $new_set ( $second_powerset->elements() ) {
            my $local_subgraph = $subgraph->copy_graph;
            $local_subgraph->add_edges( $set->elements(), $new_set->elements() );
            _emit( $match, $local_subgraph, $relation_ref, $result_ref, $relation_id_ref );
            if ( $local_subgraph->vertices < $data->{"active"}->{"subgraph_size"} && $depth < $data->{"active"}->{"subgraph_depth"} ) {
                _enumerate_connected_subgraphs_recursive( $data, $match, $graph, $local_subgraph, Set::Object::union( $prohibited_edges, $neighbouring_edges, $string_edges ), $relation_ref, $reverse_relation_ref, $depth + 1, $result_ref, $relation_id_ref );
            }
        }
    }
    return;
}

sub _cross_set {
    my ( $set1, $set2, $max ) = @_;
    my $cross_set = Set::Object->new();
    foreach my $e1 ( $set1->elements() ) {
        foreach my $e2 ( $set2->elements() ) {
            my $e3 = Set::Object::union( $e1, $e2 );
            if ( $e3->size() <= $max ) {
                $cross_set->insert($e3);
            }
            else {
                my $nodes = Set::Object->new( map( $_->[1], $e1->elements() ), map( $_->[0], $e2->elements() ) );
                $cross_set->insert($e3) if ( $nodes->size() <= $max );
            }
        }
    }
    return $cross_set;
}

sub _powerset_edges {
    my ( $set, $min, $max ) = @_;
    my @elements           = $set->elements();
    my $powerset           = Set::Object->new();
    my $number_of_elements = $set->size();
OUTER: for ( my $i = 0; $i < 2**$number_of_elements; $i++ ) {
        my $binary = sprintf "%0${number_of_elements}b", $i;
        my $ones = $binary =~ tr/1/1/;
        next if ( $ones < $min or $ones > $max );
        my @binary = split //xms, $binary;
        $powerset->insert( Set::Object->new( map { $elements[$_] } grep { $binary[$_] } ( 0 .. $#binary ) ) );
    }
    return $powerset;
}

sub _powerset_node_based {
    my ( $set, $min, $max, $index ) = @_;
    my @elements           = $set->elements();
    my $powerset           = Set::Object->new();
    my $number_of_elements = $set->size();
OUTER: for ( my $i = 0; $i < 2**$number_of_elements; $i++ ) {
        my $binary = sprintf "%0${number_of_elements}b", $i;
        my $ones = $binary =~ tr/1/1/;

        #next if ( $ones < $min or $ones > $max );
        next if ( $ones < $min );
        my @binary = split //xms, $binary;
        my $new_set = Set::Object->new( map { $elements[$_] } grep { $binary[$_] } ( 0 .. $#binary ) );
        my $nodes = Set::Object->new( map { $_->[$index] } $new_set->elements() );
        $powerset->insert($new_set) if ( $nodes->size() <= $max );
    }
    return $powerset;
}

sub _emit {
    my ( $match, $subgraph, $relation_ref, $result_ref, $relation_id_ref ) = @_;
    my %edges;
    my %incoming_edge;
    my @list_representation;
    my %nodes;
    my @sorted_nodes;
    my @emit_structure;
    foreach my $edge ( $subgraph->edges() ) {
        my ( $start, $end ) = @{$edge};
        my $relation = $relation_ref->{$start}->{$end};
        $edges{$start}->{$end}         = $relation;
        $incoming_edge{$end}->{$start} = $relation;
        push @list_representation, sprintf( "%s(%d, %d)", $relation, $start, $end );
    }
    foreach my $vertex ( $subgraph->vertices() ) {
        my ( @incoming, @outgoing );

        # incoming edges
        foreach my $local_vertex ( keys %{ $incoming_edge{$vertex} } ) {
            my $ins  = join q{,}, sort map { $edges{$_}->{$local_vertex} } keys %{ $incoming_edge{$local_vertex} };
            my $outs = join q{,}, sort map { $edges{$local_vertex}->{$_} } keys %{ $edges{$local_vertex} };
            $ins  = $ins  ne q{} ? "<($ins)"  : q{};
            $outs = $outs ne q{} ? ">($outs)" : q{};
            push @incoming, sprintf( "%s(%s%s)", $edges{$local_vertex}->{$vertex}, $ins, $outs );
        }

        # outgoing edges
        foreach my $local_vertex ( keys %{ $edges{$vertex} } ) {
            my $ins  = join q{,}, sort map { $edges{$_}->{$local_vertex} } keys %{ $incoming_edge{$local_vertex} };
            my $outs = join q{,}, sort map { $edges{$local_vertex}->{$_} } keys %{ $edges{$local_vertex} };
            $ins  = $ins  ne q{} ? "<($ins)"  : q{};
            $outs = $outs ne q{} ? ">($outs)" : q{};
            push @outgoing, sprintf( "%s(%s%s)", $edges{$vertex}->{$local_vertex}, $ins, $outs );
        }
        my $incoming = join q{,}, sort @incoming;
        my $outgoing = join q{,}, sort @outgoing;
        $incoming = $incoming ne q{} ? "<($incoming)" : q{};
        $outgoing = $outgoing ne q{} ? ">($outgoing)" : q{};
        $nodes{$vertex} = $incoming . $outgoing;
    }
    @sorted_nodes = sort { $nodes{$a} cmp $nodes{$b} || $a <=> $b } keys %nodes;
    my $node_index;
    for ( my $i = 0; $i <= $#sorted_nodes; $i++ ) {
        my $node_1 = $sorted_nodes[$i];
        if ( $node_1 == $match ) {
            $node_index = $i;
        }
        for ( my $j = 0; $j <= $#sorted_nodes; $j++ ) {
            my $node_2 = $sorted_nodes[$j];
            if ( $edges{$node_1}->{$node_2} ) {
                $emit_structure[$i]->[$j] = $relation_id_ref->{ $edges{$node_1}->{$node_2} };
                croak "Self-loop: " . join( ", ", @list_representation ) if ( $i == $j );
            }
            else {
                $emit_structure[$i]->[$j] = 0;
            }
        }
    }
    $result_ref->[ scalar @emit_structure ]->{ unpack "H*", pack( "(S*)>", map { @{$_} } @emit_structure ) }->{$node_index}++;
    return;
}

sub _get_json_graph {
    my ($data) = @_;
    my @linear_matrix = map { defined $_ ? { 'relation' => $_ } : {} } map { $data->{'number_to_relation'}->[$_] or undef } unpack( "(S*)>", pack( "H*", param('graph') ) );
    my $number_of_nodes = sqrt $#linear_matrix + 1;
    my @matrix          = map { [ @linear_matrix[ $_ * $number_of_nodes .. $_ * $number_of_nodes + $number_of_nodes - 1 ] ] } ( 0 .. $number_of_nodes - 1 );
    foreach my $param qw(word lemma pos wc) {
        if ( param($param) ) {
            $matrix[ param('position') ]->[ param('position') ]->{$param} = param($param);
        }
    }
    my $json_graph      = JSON::encode_json( \@matrix );
    debug $json_graph;
    return $json_graph, $number_of_nodes;
}

sub concordance {
    my ( $data, $mode ) = @_;

    my $check_cache      = database->prepare(qq{SELECT qid, r1, n FROM queries WHERE corpus=? AND class=? AND query=? AND threshold=?});
    my $insert_query     = database->prepare(qq{INSERT INTO queries (corpus, class, query, threshold, qlen, time, r1, n) VALUES (?, ?, ?, ?, ?, strftime('%s','now'), ?, ?)});
    my $update_timestamp = database->prepare(qq{UPDATE queries SET time=strftime('%s','now') WHERE qid=?});
    my $update_n = database->prepare(qq{UPDATE queries SET n=? WHERE qid=?});

    my $class = "cwb-treebank-$mode-" . ( param('ignore_case') ? "ci" : "cs" );

    # unpack graph
    my ($json_graph, $query_length) = _get_json_graph($data);

    my ($qids, $qid);
    $check_cache->execute( $data->{"active"}->{"corpus"}, $class, $json_graph, 0 );
    $qids = $check_cache->fetchall_arrayref;
    if ( scalar(@$qids) == 1 ) {
        $qid = $qids->[0]->[0];
        $update_timestamp->execute($qid);
    }
    elsif ( scalar(@$qids) == 0 ) {
        $insert_query->execute( $data->{"active"}->{"corpus"}, $class, $json_graph, 0, $query_length, 0, 0 ) or croak $insert_query->errstr;
	$check_cache->execute( $data->{"active"}->{"corpus"}, $class, $json_graph, 0 );
        $qid = ( $check_cache->fetchrow_array )[0];
        croak 'qid is undef!' if ( !defined $qid );
        my $dbh = executequeries::create_new_db($qid);
	my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, mlen, o11, c1, am) VALUES (?, ?, 0, 0, 0, 0, 0)});

        my $socket = IO::Socket::INET->new(
            PeerAddr  => config->{"cwb-treebank_host"},
            PeerPort  => config->{"cwb-treebank_port"},
            Proto     => "tcp",
            ReuseAddr => 1,
            Timeout   => 5,
            Type      => SOCK_STREAM
        ) or croak "Couldn't connect to " . config->{"cwb-treebank_host"} . ":" . config->{"cwb-treebank_port"} . ": $@";
        binmode( $socket, ":utf8" );

        print $socket "corpus " . $data->{"active"}->{"corpus"} . "\n";
        print $socket "mode $mode\n";
        print $socket "case-sensitivity " . ( param('ignore_case') ? "yes" : "no" ) . "\n";
        print $socket $json_graph, "\n";

	$dbh->do(qq{BEGIN TRANSACTION});
	my $n = 0;
        while ( my $out_json = <$socket> ) {
            last if ( $out_json eq "finito\n" );
	    chomp $out_json;
	    my $out = JSON::decode_json($out_json);
	    my $tmp = JSON::decode_json($out_json);
	    foreach my $tokens_ref (@{$out->{'tokens'}}) {
		$tmp->{'tokens'} = $tokens_ref;
		my $tmp_json = JSON::encode_json($tmp);
		$insert_result->execute($qid, $tmp_json);
		$n++;
	    }
        }
	$dbh->do(qq{COMMIT});

        close $socket;
        $dbh->disconnect();

	$update_n->execute($n, $qid);
    }

    params->{"id"} = $qid;
    params->{"start"} = 0 unless ( param("start") );
    my $vars = {};
    %$vars = ( %$vars, %{ kwic::display_dep($data) } );
    return $vars;
}

1;
