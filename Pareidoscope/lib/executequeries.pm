package executequeries;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use statistics;
use Carp;
use Data::Dumper;
use URI::Escape;
use Storable;
use kwic;
use Time::HiRes;
use DBI;
use List::Util qw(max min);
use List::MoreUtils;
use localdata_client;

#-------------------
# SINGLE ITEM QUERY
#-------------------
sub single_item_query {
    my ($data) = @_;

    # variable declarations
    my ( $return_vars, $query, $id, $size, @matches, %wordclasses, %postags, $dthash, @wordforms );

    # sanity checks
    unless ( defined( param("t1") and param("t1") ne "" ) ) {
        $return_vars->{"error"} = "You did not specify a word form.";
        return $return_vars;
    }

    # build query
    ($query) = &build_query($data);
    $return_vars->{"query"} = $query;
    $return_vars->{"query"} =~ s/&/&amp;/g;
    $return_vars->{"query"} =~ s/</&lt;/g;
    $return_vars->{"query"} =~ s/>/&gt;/g;
    $return_vars->{"query"} =~ s/'/&apos;/g;
    $return_vars->{"query"} =~ s/"/&quot;/g;
    debug("query: $query");

    # execute query
    $id = $data->{"cache"}->query( -corpus => $data->{"active"}->{"corpus"}, -query => $query );

    # any results?
    ($size) = $data->{"cqp"}->exec("size $id");
    $return_vars->{"matches"} = $size;
    return $return_vars if ( $size == 0 );

    # tabulate
    @matches = $data->{"cqp"}->exec("tabulate $id match word, match pos, match wc, match lemma");
    foreach my $match (@matches) {
        my ( $word, $pos, $wc, $lemma ) = split( /\t/, $match );
        $word = lc($word) if ( param('ignore_case') );
        $postags{$word}->{$pos}++;
        if ( param("tt1") eq "wordform" ) {
            $wordclasses{$word}->{$wc}++;
        }
        elsif ( param("tt1") eq "lemma" ) {
            $wordclasses{$lemma}->{$wc}++;
        }
    }

    # split or lump
    if ( param("display_type") eq "split" ) {
        $dthash = \%postags;
    }
    elsif ( param("display_type") eq "lump" ) {
        $dthash = \%wordclasses;
    }
    foreach my $token ( keys %{$dthash} ) {
        foreach my $annotation ( keys %{ $dthash->{$token} } ) {
            if ( param("display_type") eq "split" ) {
                my $wc = $data->{'tags_to_word_classes'}->{ $data->{"active"}->{"tagset"} }->{$annotation};
                croak("Cannot find word class for tag: $annotation") unless ( defined($wc) );
                push( @wordforms, [ $token, $annotation, $dthash->{$token}->{$annotation}, $wc ] );
            }
            elsif ( param("display_type") eq "lump" ) {
                push( @wordforms, [ $token, $annotation, $dthash->{$token}->{$annotation} ] );
            }
        }
    }

    @wordforms = sort { $b->[2] <=> $a->[2] } @wordforms;
    $return_vars->{"word_forms"} = \@wordforms;

    # anonyme Funktion zum weiterverarbeiten
    my $call_strucn = sub {
        my ($wfline) = @_;
        my $old_tt1 = param("tt1");
        foreach my $p qw(t tt p w) {
            foreach my $nr ( 1 .. 9 ) {
                params->{ $p . $nr } = "";
            }
        }
        my $freq = $wfline->[2];
        params->{'t1'} = $wfline->[0];
        if ( param("display_type") eq "split" ) {
            params->{'p1'}  = $wfline->[1];
            params->{'tt1'} = "wordform";
        }
        elsif ( param("display_type") eq "lump" ) {
            params->{'w1'}  = $wfline->[1];
            params->{'tt1'} = $old_tt1;
        }
        return &_strucn( $data, $freq );
    };
    $return_vars->{"call_strucn"} = $call_strucn;
    return $return_vars;
}

#--------------
# N-GRAM QUERY
#--------------
sub ngram_query {
    my ( $data ) = @_;
    my $vars;
    my %specifics;
    if ( param("return_type") eq "pos" ) {
        %specifics = ( "name" => "pos" );
    }
    elsif ( param("return_type") eq "chunk" ) {
        %specifics = ( "name" => "chunk" );
    }
    my ( $query, $pos_only_query, $title, $anchor, $query_length, $ngramref ) = &build_query($data);
    my $id = $data->{"cache"}->query( -corpus => $data->{"active"}->{"corpus"}, -query => $query );
    my ($size) = $data->{"cqp"}->exec("size $id");
    $vars->{"query_type"} = "Structural " . $specifics{"name"} . " n-gram query";
    $vars->{"query"} = $query;
    $vars->{"query"} =~ s/&/&amp;/g;
    $vars->{"query"} =~ s/</&lt;/g;
    $vars->{"query"} =~ s/>/&gt;/g;
    $vars->{"query"} =~ s/'/&apos;/g;
    $vars->{"query"} =~ s/"/&quot;/g;
    $vars->{"variables"}       = &_strucn( $data, $size );
    return $vars;
}

#---------------
# STRUCN QUERY
#---------------
sub strucn_query {
    my ($data) = @_;
    my ( $query, $pos_only_query, $title, $anchor, $query_length, $ngramref );
    my ( $id, $freq );
    my $return_vars;
    $return_vars->{"query_type"} = "Structural n-gram query";
    ( $query, $pos_only_query, $title, $anchor, $query_length, $ngramref ) = &build_query($data);
    $return_vars->{"query"} = $query;
    $return_vars->{"query"} =~ s/&/&amp;/g;
    $return_vars->{"query"} =~ s/</&lt;/g;
    $return_vars->{"query"} =~ s/>/&gt;/g;
    $return_vars->{"query"} =~ s/'/&apos;/g;
    $return_vars->{"query"} =~ s/"/&quot;/g;
    $id = $data->{"cache"}->query( -corpus => $data->{"active"}->{"corpus"}, -query => $query );
    ($freq) = $data->{'cqp'}->exec("size $id");
    $return_vars->{"variables"} = &_strucn( $data, $freq );
    return $return_vars;
}

# #--------------
# # LEXN QUERY
# #--------------
# #
# # rotate contingency table so that the invariable frequency of the n-gram can be stored as R1 in the database
# #
# #         | word | !word |
# # --------+------+-------+----
# #  n-gram | O11  | O12   | R1
# # --------+------+-------+----
# # !n-gram | O21  | O22   | R2
# # --------+------+-------+----
# #         |  C1  |  C2   | N
# #
# sub lexn_query {
#     my ( $cgi, $config, $localdata ) = @_;
#     my ( $query, $smallquery, $title, $anchor, $query_length, $id, $localn, $r1, @ranges, @frequencies, @cofreq, $cofreq, $ngramref );
#     my ( $t0, $t1, $t2, $t01diff, $t12diff );
#     my ( $qids, $qid );
#     my $vars;
#     my $check_cache      = $config->{"cache_dbh"}->prepare(qq{SELECT qid, r1, n FROM queries WHERE corpus=? AND class=? AND query=?});
#     my $insert_query     = $config->{"cache_dbh"}->prepare(qq{INSERT INTO queries (corpus, class, query, qlen, time, r1, n) VALUES (?, ?, ?, ?, strftime('%s','now'), ?, ?)});
#     my $update_timestamp = $config->{"cache_dbh"}->prepare(qq{UPDATE queries SET time=strftime('%s','now') WHERE qid=?});
#     my %specifics;

#     if ( $config->{"params"}->{"return_type"} eq "pos" ) {
#         %specifics = (
#             "name"  => "pos",
#             "class" => "lexp"
#         );
#     }
#     elsif ( $config->{"params"}->{"return_type"} eq "chunk" ) {
#         %specifics = (
#             "name"  => "chunk",
#             "class" => "lexc"
#         );
#     }
#     $vars->{"query_type"} = "Lexical " . $specifics{"name"} . " n-gram query";
#     ( $smallquery, $query, $title, $anchor, $query_length, $ngramref ) = &build_query($data);
#     $vars->{"query"} = $cgi->escapeHTML($smallquery);

#     # check cache database
#     $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery );
#     $qids = $check_cache->fetchall_arrayref;
#     if ( scalar(@$qids) == 1 ) {
#         $qid                       = $qids->[0]->[0];
#         $vars->{"matches"}         = $qids->[0]->[1];
#         $vars->{"analyze_matches"} = $qids->[0]->[2];
#         $update_timestamp->execute($qid);
#     }
#     elsif ( scalar(@$qids) == 0 ) {
#         my ( @cooccurrencematches, @matches );

#         # execute 'large' query, expand to s, execute 'small' query
#         $t0 = [ &Time::HiRes::gettimeofday() ];
#         $id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );
#         ($localn) = $config->{"cqp"}->exec("size $id");
#         $config->{"cqp"}->exec("$id expand to s; A = $smallquery");
#         ($r1) = $config->{"cqp"}->exec("size A");
#         $vars->{"matches"}         = $r1;
#         $vars->{"analyze_matches"} = $localn;
#         return $vars if ( $localn == 0 or $r1 == 0 );

#         # insert into cache.db
#         if ( $query eq $smallquery ) {
#             $insert_query->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery, $query_length, $r1, $config->{"active"}->{ $specifics{"name"} . "_ngrams" } );
#         }
#         else {
#             $insert_query->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery, $query_length, $r1, $localn );
#         }
#         $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery );
#         $qid = ( $check_cache->fetchrow_array )[0];
#         $t1  = [ &Time::HiRes::gettimeofday() ];

#         # get cooccurrence frequencies
#         @cooccurrencematches = $config->{"cqp"}->exec("tabulate A match, matchend");

#         # get overall frequencies in n-gram
#         @matches = $config->{"cqp"}->exec("tabulate $id match, matchend") unless ( $query eq $smallquery );
#         my $word = $config->get_attribute("word");
#         my $head = $config->get_attribute("h") if ( $config->{"params"}->{"return_type"} eq "chunk" );
#         foreach my $ms ( [ \@cooccurrencematches, \@cofreq ], [ \@matches, \@frequencies ] ) {
#             foreach my $m ( @{ $ms->[0] } ) {
#                 my ( $match, $matchend ) = split( /\t/, $m );

#                 # get cpos of sentence start and end
#                 my @words;
#                 my $core_query;
#                 if ( $config->{"params"}->{"return_type"} eq "pos" ) {

#                     # fetch word forms info via CWB::CL
#                     @words = $word->cpos2str( $match .. $matchend );
#                 }
#                 elsif ( $config->{"params"}->{"return_type"} eq "chunk" ) {

#                     # fetch heads info via CWB::CL
#                     @words = $word->cpos2str( grep( defined( $head->cpos2struc($_) ), ( $match .. $matchend ) ) );
#                 }
#                 croak( scalar(@words) . " != $query_length\n" ) unless ( @words == $query_length );
#                 for ( my $i = 0; $i <= $#words; $i++ ) {
#                     $ms->[1]->[$i]->{ $words[$i] }++;
#                 }
#             }
#         }
#         $t2 = [ &Time::HiRes::gettimeofday() ];
#         $vars->{"execution_times"} = [ map( sprintf( "%.2f", $_ ), ( &Time::HiRes::tv_interval( $t0, $t1 ), &Time::HiRes::tv_interval( $t1, $t2 ) ) ) ];

#         # for all co-occurring word forms, calculate am and store in database
#         my $dbh           = &create_new_db($qid);
#         my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, mlen, o11, c1, am) VALUES (?, ?, ?, ?, ?, ?, ?)});
#         $dbh->do(qq{BEGIN TRANSACTION});
#         if ( $query eq $smallquery ) {
#             my %wordfreqs;
#             my $getc1 = $config->{"dbh"}->prepare( "SELECT sum(" . $specifics{"name"} . "seq) FROM types WHERE type=?" );
#             for ( my $i = 0; $i <= $#cofreq; $i++ ) {
#                 foreach my $type ( keys %{ $cofreq[$i] } ) {
#                     $wordfreqs{$type} = 0;
#                 }
#             }
#             foreach my $type ( keys %wordfreqs ) {
#                 $getc1->execute($type);
#                 $wordfreqs{$type} = ( $getc1->fetchrow_array )[0];
#             }
#             for ( my $i = 0; $i <= $#cofreq; $i++ ) {
#                 foreach my $type ( keys %{ $cofreq[$i] } ) {
#                     my $g = &statistics::g( $cofreq[$i]->{$type}, $r1, $wordfreqs{$type}, $config->{"active"}->{ $specifics{"name"} . "_ngrams" } );
#                     $insert_result->execute( $qid, $type, $i, $query_length, $cofreq[$i]->{$type}, $wordfreqs{$type}, $g );
#                 }
#             }
#         }
#         else {
#             for ( my $i = 0; $i <= $#cofreq; $i++ ) {
#                 foreach my $type ( keys %{ $cofreq[$i] } ) {
#                     my $g = &statistics::g( $cofreq[$i]->{$type}, $r1, $frequencies[$i]->{$type}, $localn );
#                     $insert_result->execute( $qid, $type, $i, $query_length, $cofreq[$i]->{$type}, $frequencies[$i]->{$type}, $g );
#                 }
#             }
#         }
#         $dbh->do(qq{COMMIT});
#     }
#     else {
#         croak("Feel proud: you witness an extremely unlikely behaviour of this website.");
#     }
#     %$vars = ( %$vars, %{ &print_ngram_overview_table( $cgi, $config, $qid, $ngramref ) } );
#     $vars->{"slots"} = &print_ngram_query_tables( $cgi, $config, $qid, $ngramref, ( $query eq $smallquery ) );
#     return $vars;
# }

#-----------
# CQP QUERY
#-----------
sub cqp_query {
    my ( $data ) = @_;
    my $vars = {};
    my ( $query, $id );
    if ( defined( param("query") ) and not param("query") =~ m/^\s*$/ ) {
        $query = param("query");
    }
    else {
        $vars->{"error"} = "Oh, you seem to have forgotten the query!";
        return $vars;
    }
    $query =~ s/\s+/ /g;
    $id = $data->{"cache"}->query( -corpus => $data->{"active"}->{"corpus"}, -query => $query );
    params->{"id"}    = $id;
    params->{"start"} = 0;
    %$vars = (%$vars, %{&kwic::display( $data )});
    return $vars;
}

#-------------
# BUILD QUERY
#-------------
sub build_query {
    my ( $data, $parameter ) = @_;
    $parameter = defined $parameter ? $parameter : params;
    my ( @query, @unlex_query, $query, $unlex_query );
    my ( $anchor, @title, $title, $length, @ngram, $ngram );
    foreach my $nr ( 1 .. 9 ) {
        my ( $token, $head, $poswc, $query_elem, $unlex_elem, $title_elem, $token_title, $head_title, $ng_elem );
        my ( $ct, $h, $ht, $p, $t, $tt, $w, $unlex );
        foreach my $pair ( [ \$t, "t" ], [ \$tt, "tt" ], [ \$p, "p" ], [ \$w, "w" ], [ \$ct, "ct" ], [ \$h, "h" ], [ \$ht, "ht" ] ) {
            ${ $pair->[0] } = $parameter->{ $pair->[1] . $nr };
            ${ $pair->[0] } = undef if ( defined( ${ $pair->[0] } ) and ${ $pair->[0] } eq "" );
        }
        foreach ( \$h, \$p, \$t, \$w ) {
            ${$_} =~ s/([][.?*+|(){}^\$'])/\\$1/g if ( defined( ${$_} ) );
        }

        # token level
        $poswc = "wc='$w'"  if ( defined($w) );
        $poswc = "pos='$p'" if ( defined($p) );
        if ( defined($h) ) {
            $head = "[";
            $head .= "word="  if ( $ht eq "wordform" );
            $head .= "lemma=" if ( $ht eq "lemma" );
            $head .= "'$h'";
        }
        if ( defined($t) ) {
            $token = "[";
            $token .= "word="  if ( $tt eq "wordform" );
            $token .= "lemma=" if ( $tt eq "lemma" );
            $token .= "'$t'";
        }
        if ( defined($h) and defined($t) ) {
            $token .= ' %c' if ( $parameter->{"ignore_case"} );
            $token .= " & $poswc" if ( defined($poswc) );
        }
        elsif ( defined($h) and ( not defined($t) ) ) {
            $head .= ' %c' if ( $parameter->{"ignore_case"} );
            $head .= " & $poswc" if ( defined($poswc) );
        }
        elsif ( ( not defined($h) ) and defined($t) ) {
            $token .= ' %c' if ( $parameter->{"ignore_case"} );
            $token .= " & $poswc" if ( defined($poswc) );
        }
        elsif ( ( not defined($h) ) and ( not defined($t) ) ) {
            if ( $parameter->{"return_type"} eq "pos" ) {
                $token = "[";
                $token .= "$poswc" if ( defined($poswc) );
            }
            elsif ( $parameter->{"return_type"} eq "chunk" ) {
                $head = "[$poswc" if ( defined($poswc) );
            }
        }
        $token .= "]" if ( defined($token) );
        $head  .= "]" if ( defined($head) );
        if ( defined($token) and $token =~ m/^\[(?:(?:word|lemma)='(\S+)'(?: %c)?)?(?: & )?(?:(?:pos|wc)='(\S+)')?\]$/ ) {
            $token_title = "$1/$2" if ( defined($1)     and defined($2) );
            $token_title = "$1/x"  if ( defined($1)     and not defined($2) );
            $token_title = "x/$2"  if ( not defined($1) and defined($2) );
            $token_title = "x"     if ( not defined($1) and not defined($2) );
        }
        if ( defined($head) and $head =~ m/^\[(?:(?:word|lemma)='(\S+)'(?: %c)?)?(?: & )?(?:(?:pos|wc)='(\S+)')?\]$/ ) {
            $head_title = "$1/$2" if ( defined($1)     and defined($2) );
            $head_title = "$1/x"  if ( defined($1)     and not defined($2) );
            $head_title = "x/$2"  if ( not defined($1) and defined($2) );
            $head_title = "x"     if ( not defined($1) and not defined($2) );
        }

        # chunk level
        if ( defined($ct) ) {
            my $local_ct = $ct eq "any" ? "x" : $ct;
            if ( defined($head) and defined($token) ) {
                my ( %token, %head );
                if ( $token =~ m/^\[(?:(?<tt>word|lemma)=(?<t>'\S+')(?<i> %c)?)?(?: & )?(?:(?<pwt>pos|wc)=(?<pw>'\S+'))?\]$/ ) {
                    $token{"tt"}  = $+{tt}  if ( defined( $+{tt} ) );
                    $token{"t"}   = $+{t}   if ( defined( $+{t} ) );
                    $token{"ignore_case"}   = $+{i}   if ( defined( $+{i} ) );
                    $token{"pwt"} = $+{pwt} if ( defined( $+{pwt} ) );
                    $token{"pw"}  = $+{pw}  if ( defined( $+{pw} ) );
                }
                else {
                    croak("Unable to parse token: '$token'\n");
                }
                if ( $head =~ m/^\[(?:(?<tt>word|lemma)=(?<t>'\S+')(?<i> %c)?)?(?: & )?(?:(?<pwt>pos|wc)=(?<pw>'\S+'))?\]$/ ) {
                    $head{"tt"}  = $+{tt}  if ( defined( $+{tt} ) );
                    $head{"t"}   = $+{t}   if ( defined( $+{t} ) );
                    $head{"ignore_case"}   = $+{i}   if ( defined( $+{i} ) );
                    $head{"pwt"} = $+{pwt} if ( defined( $+{pwt} ) );
                    $head{"pw"}  = $+{pw}  if ( defined( $+{pw} ) );
                }
                else {
                    croak("Unable to parse head: '$head'\n");
                }

                # try to combine restrictions on token and head
                my $combine = sub {
                    my @combi;
                    my $return_def = sub {
                        my ( $a, $b, $c ) = @_;
                        return $a if ( defined( $a->{$c} ) );
                        return $b if ( defined( $b->{$c} ) );
                    };
                    my ( $token_t, $head_t );

                    if ( $token{"ignore_case"} ) {
                        $token_t = lc( $token{"t"} ) if ( defined( $token{"t"} ) );
                        $head_t  = lc( $head{"t"} )  if ( defined( $head{"t"} ) );
                    }
                    else {
                        $token_t = $token{"t"} if ( defined( $token{"t"} ) );
                        $head_t  = $head{"t"}  if ( defined( $head{"t"} ) );
                    }

                    if ( defined( $token{"tt"} ) and defined( $head{"tt"} ) ) {
                        my $combi;
                        if ( $token{"tt"} eq $head{"tt"} ) {
                            return if ( $token_t ne $head_t );

                            # can never be case-insensitive
                            push( @combi, $head{"tt"} . "=" . $head{"t"} );
                        }
                        else {
                            foreach ( \%token, \%head ) {
                                $combi = $_->{"tt"} . "=" . $_->{"t"};
                                $combi .= " %c" if ( $_->{"ignore_case"} );
                                push( @combi, $combi );
                            }
                        }
                    }
                    elsif ( defined( $token{"tt"} ) xor defined( $head{"tt"} ) ) {
                        my $def = $return_def->( \%token, \%head, "tt" );
                        my $combi = $def->{"tt"} . "=" . $def->{"t"};
                        $combi .= " %c" if ( $def->{"ignore_case"} );
                        push( @combi, $combi );
                    }

                    if ( defined( $token{"pwt"} ) and defined( $head{"pwt"} ) ) {
                        my $combi;
                        if ( $token{"pwt"} eq $head{"pwt"} ) {
                            return if ( $token{"pw"} ne $head{"pw"} );
                            push( @combi, $head{"pwt"} . "=" . $head{"pw"} );
                        }
                        else {
                            foreach ( \%token, \%head ) {
                                push( @combi, $_->{"pwt"} . "=" . $_->{"pw"} );
                            }
                        }
                    }
                    elsif ( defined( $token{"pwt"} ) xor defined( $head{"pwt"} ) ) {
                        my $def = $return_def->( \%token, \%head, "pwt" );
                        push( @combi, $def->{"pwt"} . "=" . $def->{"pw"} );
                    }

                    return "[" . join( " & ", @combi ) . "]" if (@combi);
                };
                my $combined = $combine->();
                if ( defined($combined) ) {
                    $query_elem = "<$ct> []* (($token []* <h> $head </h>)|(<h> $combined </h>)) </$ct>";
                }
                else {
                    $query_elem = "<$ct> []* $token []* <h> $head </h> </$ct>";
                }
                $title_elem = "${local_ct}[$token_title,h=$head_title]";
            }
            elsif ( defined($head) and ( not defined($token) ) ) {
                $query_elem = "<$ct> []* <h> $head </h> </$ct>";
                $title_elem = "${local_ct}[h=$head_title]";
            }
            elsif ( ( not defined($head) ) and defined($token) ) {
                $query_elem = "<$ct> []* $token []* </$ct>";
                $title_elem = "${local_ct}[$token_title]";
            }
            elsif ( ( not defined($head) ) and ( not defined($token) ) ) {
                $query_elem = "<$ct> []* </$ct>";
                $title_elem = "${local_ct}[]";
            }
            $unlex_elem = "<$ct> []* </$ct>";
            $ng_elem    = $local_ct;
        }
        else {
            if ( defined($head) and defined($token) ) {
                croak("head and token defined: '$head' and '$token'\n");
            }
            elsif ( defined($head) and ( not defined($token) ) ) {
                $query_elem = $head;
                $title_elem = $head_title;
            }
            elsif ( ( not defined($head) ) and defined($token) ) {
                $query_elem = $token;
                $title_elem = $token_title;
            }
            elsif ( ( not defined($head) ) and ( not defined($token) ) ) {
                $query_elem = "[]";
                $title_elem = "x";
            }
            $unlex_elem = "[";
            $unlex_elem .= $poswc if ( defined($poswc) );
            $unlex_elem .= "]";
            $ng_elem = defined($poswc) ? $poswc : "x";
        }
        push( @query,       $query_elem );
        push( @unlex_query, $unlex_elem );
        push( @title,       $title_elem );
        push( @ngram,       $ng_elem );
    }
    $query       = join( " ", @query );
    $unlex_query = join( " ", @unlex_query );
    my $opening_chunks = join( "|", map( "<$_>",  grep( defined($_), @{ $data->{"number_to_chunk"} } ) ) );
    my $closing_chunks = join( "|", map( "</$_>", grep( defined($_), @{ $data->{"number_to_chunk"} } ) ) );
    foreach ( \$query, \$unlex_query ) {
        ${$_} =~ s/^(\[\] )*//;
        ${$_} =~ s/( \[\])*$//;
        ${$_} =~ s!^(<any> \[\]\* </any> )*!!;
        ${$_} =~ s!( <any> \[\]\* </any>)*$!!;
        ${$_} =~ s/<any>/($opening_chunks)/g;
        ${$_} =~ s!</any>!($closing_chunks)!g;
        ${$_} .= " within s";
        ${$_} =~ s/\s+/ /;
    }
    $title = join( " ", @title );
    $ngram = join( " ", @ngram );
    $ngram =~ s/^(x )*//;
    $ngram =~ s/( x)*$//;
    $title =~ s/^((x )|(x\[\] ))*//;
    $title =~ s/(( x(?![\/[]))|( x\[\]))*$//;
    @ngram = split( " ", $ngram );
    $anchor = $title;
    $anchor =~ s/ /_/g;
    @title = split( / /, $title );
    $length = @title;
    return ( $query, $unlex_query, $title, $anchor, $length, \@ngram );
}

#---------
# STRUC N
#---------
sub _strucn {
    my ( $data, $freq ) = @_;
    my ($cached_query_id);
    my ( $qids, $ngtypes );
    my ( $t0, $t1, $t2, $t3, $t4 );
    my $skipped          = 0;
    my $check_cache      = database->prepare(qq{SELECT qid, r1, n FROM queries WHERE corpus=? AND class=? AND query=? AND threshold=?});
    my $insert_query     = database->prepare(qq{INSERT INTO queries (corpus, class, query, threshold, qlen, time, r1, n) VALUES (?, ?, ?, ?, ?, strftime('%s','now'), ?, ?)});
    my $update_timestamp = database->prepare(qq{UPDATE queries SET time=strftime('%s','now') WHERE qid=?});
    my $return_vars;
    my $frequency_threshold   = 200000;
    my $ngram_types_threshold = 750000;
    my $localdata             = localdata_client->init( $data->{"active"}->{"localdata"}, @{ $data->{"active"}->{"machines"} } );

    # build query
    my ( $query, $unlex_query, $title, $anchor, $query_length ) = &build_query($data);
    $return_vars->{"query_anchor"} = $anchor;
    $return_vars->{"query_title"}  = $title;
    my %specifics;
    if ( param("return_type") eq "pos" ) {
        %specifics = (
            "name"  => "pos",
            "class" => "strucp"
        );
    }
    elsif ( param("return_type") eq "chunk" ) {
        %specifics = (
            "name"  => "chunk",
            "class" => "strucc"
        );
    }
    $return_vars->{"return_type"}        = $specifics{"name"};
    $return_vars->{"frequency"}          = $freq;
    $return_vars->{"frequency_too_high"} = $freq >= $frequency_threshold;
    $return_vars->{"frequency_too_low"}  = $freq < param("threshold");
    return $return_vars if ( $freq == 0 );
    return $return_vars if ( $return_vars->{"frequency_too_high"} );
    return $return_vars if ( $return_vars->{"frequency_too_low"} );

    # check cache database
    $check_cache->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold") );
    $qids    = $check_cache->fetchall_arrayref;
    $ngtypes = 0;
    if ( scalar(@$qids) == 1 ) {
        my $qid = $qids->[0]->[0];
        $update_timestamp->execute($qid);
        my $dbh = DBI->connect( "dbi:SQLite:" . config->{"user_data"} . "/$qid" ) or die("Cannot connect: $DBI::errstr");
        $dbh->do("PRAGMA encoding = 'UTF-8'");
        my $get_ngram_types = $dbh->prepare(qq{SELECT COUNT(*) FROM results WHERE qid=?});
        $get_ngram_types->execute($qid);
        $ngtypes                               = ( $get_ngram_types->fetchrow_array )[0];
        $return_vars->{"ngram_tokens"}         = $qids->[0]->[1];
        $return_vars->{"ngram_types"}          = $ngtypes;
        $return_vars->{"too_many_ngram_types"} = $ngtypes >= $ngram_types_threshold;
    }
    elsif ( scalar(@$qids) == 0 ) {
        my ( $qid, @matches, %ngrams );
        my $r1 = 0;
        $t0              = [ &Time::HiRes::gettimeofday() ];
        $cached_query_id = $data->{"cache"}->query( -corpus => $data->{"active"}->{"corpus"}, -query => $query );
        $t1              = [ &Time::HiRes::gettimeofday() ];
        my $sentence = $data->get_attribute("s");
        @matches = $data->{"cqp"}->exec("tabulate $cached_query_id match, matchend");
        $t2      = [ &Time::HiRes::gettimeofday() ];
        my $pos = $data->get_attribute("pos") if ( param("return_type") eq "pos" );
        my $get_chunk_seq = $data->{"dbh"}->prepare(qq{SELECT chunkseq, cposseq FROM sentences WHERE cpos = ?}) if ( param("return_type") eq "chunk" );

        foreach my $m (@matches) {
            my ( $match, $matchend ) = split( /\t/, $m );
            my $match_length;    # = ($matchend - $match) + 1;
                                 # get cpos of sentence start and end
            my ( $start, $end ) = $sentence->cpos2struc2cpos($match);
            my ( @cseq, @pseq );
            my $core_query;
            if ( param("return_type") eq "pos" ) {

                # fetch POS info via CWB::CL
                @cseq = map( $data->{"tag_to_number"}->{$_}, $pos->cpos2str( $start .. $end ) );
                @pseq = ( 0 .. $end - $start );
            }
            elsif ( param("return_type") eq "chunk" ) {

                # get sequence of chunks and sequence of cpos from db
                $get_chunk_seq->execute($start);
                my $resref = $get_chunk_seq->fetchall_arrayref;
                croak( "Error while checking chunk sequences: " . scalar(@$resref) . "." ) if ( @$resref != 1 );
                my ( $chunkseq, $cposseq ) = @{ $resref->[0] };
                @cseq = split( / /, $chunkseq );
                @pseq = split( / /, $cposseq );
            }
            my ( $cstart, $cend );
            for ( my $i = $#cseq; $i >= 0; $i-- ) {
                $cend   = $i if ( ( $pseq[$i] + $start <= $matchend ) and not defined($cend) );
                $cstart = $i if ( ( $pseq[$i] + $start <= $match )    and not defined($cstart) );
            }
            $match_length = ( $cend - $cstart ) + 1;

            my $max_start = max( $cstart - ( $data->{"active"}->{"ngram_length"} - $match_length ), 0 );
            my $max_end   = min( $cstart + ( $data->{"active"}->{"ngram_length"} - 1 ), $#cseq );
            my $position  = $cstart - $max_start;
            my @max_ngram = @cseq[ $max_start .. $max_end ];

            #$r1 += &retrieve_ngrams( \@max_ngram, \%ngrams, $data->{"active"}->{"ngram_length"}, $match_length, $position );
            $r1 += &retrieve_ngrams( \@max_ngram, \%ngrams, $data->{"active"}->{"ngram_length"}, $match_length, $position, $pseq[$max_start] + $start );
        }
        ## handle skipped matches
        #print "$skipped matches of length > 9 had to be discarded", $cgi->br if($skipped);
        $return_vars->{"ngram_tokens"} = $r1;
        return $return_vars if ( $r1 == 0 );

        # insert into cache database
        $insert_query->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold"), $query_length, $r1, $data->{"active"}->{ $specifics{"name"} . "_ngrams" } );
        $check_cache->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold") );
        $qid = ( $check_cache->fetchrow_array )[0];
        $t3  = [ &Time::HiRes::gettimeofday() ];

        # foreach n-gram type retrieve c1 from ngrams.db and calculate association measure; store results in database
        my $dbh = &create_new_db($qid);
        $dbh->disconnect();
        undef($dbh);
        my $serialized_ngrams = $localdata->serialize( \%ngrams );
        $ngtypes                               = scalar(@$serialized_ngrams);
        $return_vars->{"ngram_types"}          = $ngtypes;
        $return_vars->{"too_many_ngram_types"} = $ngtypes >= $ngram_types_threshold;
        return $return_vars if ( $ngtypes >= $ngram_types_threshold );
        $localdata->add_freq_and_am( $serialized_ngrams, $r1, $data->{"active"}->{ $specifics{"name"} . "_ngrams" }, $qid );
        $t4 = [ &Time::HiRes::gettimeofday() ];
        $return_vars->{"execution_times"} = [ map( sprintf( "%.2f", $_ ), ( &Time::HiRes::tv_interval( $t0, $t1 ), &Time::HiRes::tv_interval( $t1, $t2 ), &Time::HiRes::tv_interval( $t2, $t3 ), &Time::HiRes::tv_interval( $t3, $t4 ) ) ) ];
    }
    else {
        croak("Feel proud: you witness an extremely unlikely behaviour of this website.");
    }
    %$return_vars = ( %$return_vars, %{ &new_print_table( $data, $query ) } );

    foreach my $param ( keys %{ params() } ) {
        next if ( param($param) eq q{} );
        $return_vars->{"previous_href"}->{$param} = $return_vars->{"next_href"}->{$param} = param($param);
    }
    $return_vars->{"previous_href"}->{"start"} = param("start") - 40;
    $return_vars->{"next_href"}->{"start"}     = param("start") + 40;
    return $return_vars;
}

#---------------
# CREATE NEW DB
#---------------
sub create_new_db {
    my ($qid) = @_;
    my $dbh = DBI->connect( "dbi:SQLite:" . config->{"user_data"} . "/$qid" ) or die("Cannot connect to " . config->{"user_data"} . "/$qid: $DBI::errstr");
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
    return $dbh;
}

#---------------------
# CREATE N LINK STRUC
#---------------------
sub create_n_link_struc {
    my ( $ngramref, $position ) = @_;
    my %argument;
    $argument{"corpus"} = param("corpus");
    $argument{"threshold"} = param("threshold");
    $argument{"return_type"} = param("return_type");
    my @params   = qw(t tt);
    if ( param("return_type") eq "chunk" ) {
        push @params, qw(p w h ht);
    }
    for ( my $i = 0; $i <= $#$ngramref; $i++ ) {
        foreach my $param (@params) {
            $argument{ $param . ( $i + $position + 1 ) } = param( $param . ( $i + 1 ) ) if ( defined( param( $param . ( $i + 1 ) ) ) and param( $param . ( $i + 1 ) ) ne "" );
        }
        if ( param("return_type") eq "pos" ) {
            $argument{ "p" . ( $i + 1 ) } = $ngramref->[$i];
        }
        elsif ( param("return_type") eq "chunk" ) {
            $argument{ "ct" . ( $i + 1 ) } = $ngramref->[$i];
        }
    }
    $argument{"s"} = "Link";
    return \%argument;
}

# #-------------------
# # CREATE N LINK LEX
# #-------------------
# sub create_n_link_lex {
#     my ( $cgi, $config, $mode, $ngramref, $position, $head ) = @_;
#     my %mode2text = ( "ln" => "lex", "sn" => "struc" );
#     my $state;
#     if ( $config->{"params"}->{"return_type"} eq "pos" ) {
#         $state = $config->keep_states_href( { "t" . ( $position + 1 ) => $head, "tt" . ( $position + 1 ) => "wf", "ignore_case" . ( $position + 1 ) => 0 }, qw(c rt p w i t tt) );
#     }
#     elsif ( $config->{"params"}->{"return_type"} eq "chunk" ) {
#         $state = $config->keep_states_href( { "h" . ( $position + 1 ) => $head, "ht" . ( $position + 1 ) => "wf", "ignore_case" . ( $position + 1 ) => 0 }, qw(c rt t tt p w i ct h ht) );
#     }
#     my $href = "pareidoscope.cgi?m=$mode&s=link&$state";

#     #return $cgi->a( { "href" => $href }, $mode2text{$mode} );
#     return $cgi->escapeHTML($href);
# }

# #----------------------
# # CREATE FREQ LINK LEX
# #----------------------
# sub create_freq_link_lex {
#     my ( $cgi, $config, $freq, $ngramref, $position, $head ) = @_;
#     my $state       = $config->keep_states_href( {}, qw(c) );
#     my $href        = "pareidoscope.cgi?m=c&q=";
#     my $localparams = Storable::dclone( $config->{"params"} );
#     if ( $config->{"params"}->{"return_type"} eq "pos" ) {
#         $localparams->{"t"}->{ $position + 1 }  = $head;
#         $localparams->{"tt"}->{ $position + 1 } = "wf";
#     }
#     elsif ( $config->{"params"}->{"return_type"} eq "chunk" ) {
#         $localparams->{"h"}->{ $position + 1 }  = $head;
#         $localparams->{"ht"}->{ $position + 1 } = "wf";
#     }
#     $localparams->{"ignore_case"}->{ $position + 1 } = 0;
#     my ($query) = &build_query( { "params" => $localparams } );
#     $href .= URI::Escape::uri_escape($query) . "&s=Link";
#     $href .= "&$state";

#     #return $cgi->a( { 'href' => $href }, $freq );
#     return $cgi->escapeHTML($href);
# }

# #------------------------
# # CREATE NGFREQ LINK LEX
# #------------------------
# sub create_ngfreq_link_lex {
#     my ( $cgi, $config, $freq, $ngramref, $position, $head ) = @_;
#     my $state       = $config->keep_states_href( {}, qw(c) );
#     my $href        = "pareidoscope.cgi?m=c&q=";
#     my $localparams = Storable::dclone( $config->{"params"} );
#     my @deletions   = qw(t tt w ht h i);
#     push( @deletions, "p" ) if ( $config->{"params"}->{"return_type"} eq "chunk" );
#     foreach my $param (@deletions) {
#         foreach my $i ( 1 .. 9 ) {
#             undef( $localparams->{$param}->{$i} );
#         }
#     }
#     if ( $config->{"params"}->{"return_type"} eq "pos" ) {
#         $localparams->{"t"}->{ $position + 1 }  = $head;
#         $localparams->{"tt"}->{ $position + 1 } = "wf";
#     }
#     elsif ( $config->{"params"}->{"return_type"} eq "chunk" ) {
#         $localparams->{"h"}->{ $position + 1 }  = $head;
#         $localparams->{"ht"}->{ $position + 1 } = "wf";
#     }
#     my ($query) = &build_query( { "params" => $localparams } );
#     $href .= URI::Escape::uri_escape($query) . "&s=Link";
#     $href .= "&$state";

#     #return $cgi->a( { 'href' => $href }, $freq );
#     return $cgi->escapeHTML($href);
# }

#------------------------
# CREATE FREQ LINK STRUC
#------------------------
sub create_freq_link_struc {
    my ( $data, $freq, $position, @ngram ) = @_;
    my %argument;
    $argument{"corpus"} = param("corpus");
    $argument{"threshold"} = param("threshold");
    my $localparams = Storable::dclone(params);
    my @deletions   = qw(ct t tt w ht h p);
    foreach my $param (@deletions) {
        foreach my $i ( 1 .. 9 ) {
            undef( $localparams->{ $param . $i } );
        }
    }
    for ( my $i = 0; $i <= $#ngram; $i++ ) {
        my $j = $i + 1 - $position;
        if ( $j > 0 ) {
            foreach my $param qw(t tt h ht) {
                $localparams->{ $param . ( $i + 1 ) } = param( $param . $j );
            }
        }
        if ( param("return_type") eq "pos" ) {
            $localparams->{ "p" . ( $i + 1 ) } = $ngram[$i];
        }
        elsif ( param("return_type") eq "chunk" ) {
            $localparams->{ "ct" . ( $i + 1 ) } = $ngram[$i];
            $localparams->{ "p" .  ( $i + 1 ) } = param( "p" . $j );
            $localparams->{ "w" .  ( $i + 1 ) } = param( "w" . $j );
        }
    }
    my ($query) = &build_query( $data, $localparams );
    $argument{"query"} = URI::Escape::uri_escape($query);
    $argument{"s"}     = "Link";
    return \%argument;
}

#--------------------------
# CREATE NGFREQ LINK STRUC
#--------------------------
sub create_ngfreq_link_struc {
    my ( $data, $ngfreq, @ngram ) = @_;
    my %argument;
    $argument{"corpus"} = param("corpus");
    $argument{"threshold"} = param("threshold");
    my $localparams = Storable::dclone(params);
    my @deletions   = qw(ct t tt w ht h p);
    foreach my $param (@deletions) {
        foreach my $i ( 1 .. 9 ) {
            undef( $localparams->{ $param . $i } );
        }
    }
    for ( my $i = 0; $i <= $#ngram; $i++ ) {
        if ( param("return_type") eq "pos" ) {
            $localparams->{ "p" . ( $i + 1 ) } = $ngram[$i];
        }
        elsif ( param("return_type") eq "chunk" ) {
            $localparams->{ "ct" . ( $i + 1 ) } = $ngram[$i];
        }
    }
    my ($query) = &build_query( $data, $localparams );
    $argument{"query"} = URI::Escape::uri_escape($query);
    $argument{"s"}     = "Link";
    return \%argument;
}

#-----------------
# NEW PRINT TABLE
#-----------------
sub new_print_table {
    my ( $data, $query ) = @_;
    my ( $qids, $qid, $query_length );
    my ( $filter_length, $filter_pos ) = ( "", "" );
    my $vars;
    my %filter_relations = ( 1 => ">=", 2 => "<=", 3 => "=" );
    my %specifics;
    if ( param("return_type") eq "pos" ) {
        %specifics = (
            "map"   => "number_to_tag",
            "class" => "strucp"
        );
    }
    elsif ( param("return_type") eq "chunk" ) {
        %specifics = (
            "map"   => "number_to_chunk",
            "class" => "strucc"
        );
    }
    my $check_cache = database->prepare(qq{SELECT qid, qlen, r1, n FROM queries WHERE corpus=? AND class=? AND query=? AND threshold=?});
    $check_cache->execute( $data->{"active"}->{"corpus"}, $specifics{"class"}, $query, param("threshold") );
    $qids = $check_cache->fetchall_arrayref;
    croak("Error while processing cache database.") unless ( scalar(@$qids) == 1 );
    $qid          = $qids->[0]->[0];
    $query_length = $qids->[0]->[1];
    my $dbh = DBI->connect( "dbi:SQLite:" . config->{"user_data"} . "/$qid" ) or die("Cannot connect: $DBI::errstr");
    $dbh->do("PRAGMA encoding = 'UTF-8'");
    $dbh->do("PRAGMA cache_size = 50000");
    $filter_length = 'AND length(result) ' . $filter_relations{ param("frel") } . ' ' . ( param("flen") * 2 + 2 ) if ( defined( param("flen") ) and defined( param("frel") ) );

    if ( ( ( defined( param("ftag") ) and param("ftag") ne "" ) or ( defined( param("fwc") ) and param("fwc") ne "" ) or ( defined( param("fch") ) and param("fch") ne "" ) ) and ( defined( param("fpos") ) and param("fpos") ne "" ) ) {
        my $ftaghex;
        if ( defined( param("ftag") ) and param("ftag") ne "" ) {
            $ftaghex = sprintf( "%02x", $data->{"tag_to_number"}->{ param("ftag") } );
        }
        elsif ( defined( param("fwc") ) and param("fwc") ne "" ) {
            $ftaghex = '(' . join( '|', map( sprintf( "%02x", $data->{"tag_to_number"}->{$_} ), @{ config->{"tagsets"}->{ $data->{"active"}->{"tagset"} }->{ param("fwc") } } ) ) . ')';
        }
        elsif ( defined( param("fch") ) and param("fch") ne "" ) {
            $ftaghex = sprintf( "%02x", $data->{"chunk_to_number"}->{ param("fch") } );
        }
        else {
            croak("How comes?");
        }
        $filter_pos = 'AND result REGEXP \'';

        # on the right side
        if ( param("fpos") == 1 ) {
            $filter_pos .= ">([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*\$";
        }

        # on the left side
        elsif ( param("fpos") == 2 ) {
            $filter_pos .= "^([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*<";
        }

        # on either side
        elsif ( param("fpos") == 3 ) {
            $filter_pos .= "(^([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*<)|(>([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*\$)";
        }
        $filter_pos .= '\'';
    }
    my $get_top_50 = $dbh->prepare( qq{SELECT result, position, mlen, o11, c1, am FROM results WHERE qid=? $filter_length $filter_pos ORDER BY am DESC, o11 DESC LIMIT } . param("start") . qq{, 40} );
    $get_top_50->execute($qid);
    my $rows = $get_top_50->fetchall_arrayref;

    ###$vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( $cgi, {}, qw(m c rt dt start t tt p w i ht h ct) );
    # id fch flen frel ftag fwc fpos q rt
    foreach my $param ( keys %{ params() } ) {
        next if ( param($param) eq q{} );
        next if List::MoreUtils::any { $_ eq $param } qw(fch flen frel ftag fwc fpos);
        $vars->{"hidden_states"}->{$param} = param($param);
    }

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
        @ngram                    = map( $data->{ $specifics{"map"} }->[$_], map( hex($_), unpack( "(a2)*", $result ) ) );
        @display_ngram            = @ngram;
        $display_ngram[$position] = "<em>$display_ngram[$position]";
        $display_ngram[ $position + $mlen - 1 ] .= "</em>";
        $display_ngram = join( " ", @display_ngram );
        $row->{"display_ngram"} = $display_ngram;

        # CREATE LEX AND STRUC LINKS
        $row->{"struc_href"} = &create_n_link_struc( \@ngram, $position );
        $row->{"lex_href"}   = &create_n_link_struc( \@ngram, $position );
        $row->{"cofreq_href"} = &create_freq_link_struc( $data, $o11, $position, @ngram );
        $row->{"ngfreq_href"} = &create_ngfreq_link_struc( $data, $c1, @ngram );
        $counter++;
        $row->{"number"} = $counter;
    }
    $vars->{"rows"} = $rows;
    return $vars;
}

#------------------
# RETRIEVE N-GRAMS
#------------------
sub retrieve_ngrams {

    #my ( $tagsref, $nghashref, $maxlength, $match_length, $position ) = @_;
    my ( $tagsref, $nghashref, $maxlength, $match_length, $position, $absolute_pos ) = @_;
    my $localr1     = 0;
    my $endposition = $position + $match_length - 1;
    for ( my $start = 0; $start <= $position; $start++ ) {

        #my $minlength = $endposition - $start + 1 < $match_length + 1 ? $match_length + 1 : $endposition - $start + 1;
        my $minlength = $endposition - $start + 1 < $match_length ? $match_length : $endposition - $start + 1;
        my $maxlength = $#$tagsref - $start + 1 > $maxlength      ? $maxlength    : $#$tagsref - $start + 1;
        my $localposition = $position - $start;
        for ( my $length = $minlength; $length <= $maxlength; $length++ ) {
            my ( @ngram, $ngram );
            @ngram = @$tagsref[ $start .. $start + $length - 1 ];
            $ngram = pack( "C*", @ngram );

            #$nghashref->{$ngram}->{$localposition}->{$match_length}++;
            $nghashref->{$ngram}->{$localposition}->{$match_length}->{$absolute_pos}++;
            $localr1++;
        }
    }
    return $localr1;
}

# #--------------------------
# # PRINT NGRAM QUERY TABLES
# #--------------------------
# sub print_ngram_query_tables {
#     my ( $cgi, $config, $qid, $ngramref, $general ) = @_;
#     my $dbh = DBI->connect("dbi:SQLite:" . config->{"user_data"} . "/$qid") or die("Cannot connect: $DBI::errstr");
#     print $cgi->end_table, $cgi->end_p;
#     $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
#     my $get_top_50    = $dbh->prepare(qq{SELECT result, position, o11, c1, am FROM results WHERE position=? ORDER BY am DESC, o11 DESC LIMIT 0, 40});
#     my $get_positions = $dbh->prepare(qq{SELECT DISTINCT position FROM results ORDER BY position ASC});
#     $get_positions->execute();
#     my $positionsref = $get_positions->fetchall_arrayref;
#     my $slots;
#     foreach my $position (@$positionsref) {
#         my $slot;
#         $position = $position->[0];
#         $get_top_50->execute($position);
#         my $rows = $get_top_50->fetchall_arrayref;
#         $slot->{"name"} = $ngramref->[$position];
#         my $counter = 0;
#         foreach my $row (@$rows) {
#             my $slotrow;
#             my ( $result, $posit, $o11, $c1, $g2 ) = @$row;
#             $g2 = sprintf( "%.5f", $g2 );
#             my ( $freqlink, $ngfreqlink, $lexnlink, $strucnlink );
#             my %words;
#             foreach my $nr ( keys %{ $config->{'params'}->{'q'} } ) {
#                 $words{$nr} = $config->{'params'}->{'q'}->{$nr} if ( defined( $config->{'params'}->{'q'}->{$nr} ) and $config->{'params'}->{'q'}->{$nr} ne "" );
#             }
#             $words{ $position + 1 } = $result;
#             $slotrow->{"word"} = $result;
#             $slotrow->{"cofreq_href"} = &create_freq_link_lex( $cgi, $config, $o11, $ngramref, $position, $result );
#             $slotrow->{"ngfreq_href"} = &create_ngfreq_link_lex( $cgi, $config, $c1, $ngramref, $position, $result ) unless ($general);
#             $slotrow->{"lex_href"}   = &create_n_link_lex( $cgi, $config, "ln", $ngramref, $position, $result );
#             $slotrow->{"struc_href"} = &create_n_link_lex( $cgi, $config, "sn", $ngramref, $position, $result );
#             $counter++;
#             $slotrow->{"number"} = $counter;
#             $slotrow->{"cofreq"} = $o11;
#             $slotrow->{"ngfreq"} = $c1;
#             $slotrow->{"g"}      = $g2;
# 	    push( @{ $slot->{"rows"} }, $slotrow );
#         }
# 	push(@$slots, $slot);
#     }
#     return $slots;
# }

# #----------------------------
# # PRINT NGRAM OVERVIEW TABLE
# #----------------------------
# sub print_ngram_overview_table {
#     my ( $cgi, $config, $qid, $ngramref ) = @_;
#     my $vars;
#     my $dbh = DBI->connect("dbi:SQLite:" . config->{"user_data"} . "/$qid") or die("Cannot connect: $DBI::errstr");
#     $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
#     my $get_top_10    = $dbh->prepare(qq{SELECT result, position, o11, c1, am FROM results WHERE position=? ORDER BY am DESC, o11 DESC LIMIT 0, 10});
#     my $get_positions = $dbh->prepare(qq{SELECT DISTINCT position FROM results ORDER BY position ASC});
#     $get_positions->execute();
#     my $positionsref = $get_positions->fetchall_arrayref;
#     my @columns;

#     foreach my $position (@$positionsref) {
#         $position = $position->[0];
#         $get_top_10->execute($position);
#         my $rows = $get_top_10->fetchall_arrayref;
#         push( @{ $columns[$position] }, $ngramref->[$position] );
#         my $counter = 0;
#         foreach my $row (@$rows) {
#             my ( $result, $posit, $o11, $c1, $g2 ) = @$row;
#             push( @{ $columns[$position] }, $result );
#         }
#         push( @{ $columns[$position] }, ( "", "", "", "", "", "", "", "", "", "" ) );
#     }
#         $vars->{"row_numbers"}    = [ 0 ];
#     foreach my $i (1 .. 10) {
# 	last if ( join( "", map( $_->[$i], @columns ) ) eq "" );
# 	push(@{$vars->{"row_numbers"}}, $i);
#     }
#     $vars->{"column_numbers"} = [ 0 .. $#columns ];
#     $vars->{"overview_table"} = \@columns;
#     return $vars;
# }

# #---------------
# # OLD FUNCTIONS
# #---------------

1;
