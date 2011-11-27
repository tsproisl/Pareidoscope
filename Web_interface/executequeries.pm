package executequeries;

use warnings;
use strict;

#open(STDERR,">$0.debug");

#use lib "/srv/www/homepages/tsproisl/pareidoscope/local/lib/perl5/site_perl/5.10.0";
#use lib "/srv/www/homepages/tsproisl/pareidoscope/local/lib/perl5/site_perl/5.10.0/x86_64-linux-thread-multi";

use statistics;
use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;
use URI::Escape;
use Storable;
use kwic;
use Time::HiRes;

#use utf8;
use DBI;
use List::Util qw(max);

#-------------------
# SINGLE ITEM QUERY
#-------------------
sub single_item_query {
    my ( $cgi, $config, $localdata ) = @_;

    # variable declarations
    my ( $vars, $query, $id, $size, @matches, %wordclasses, %postags, $dthash, @wordforms );
    my %input = ( "wfq" => "Word form query", "lq" => "Lemma query" );
    $vars->{"query_type"} = $input{ $config->{"params"}->{"m"} };

    # sanity checks
    unless ( defined( $config->{"params"}->{"t"}->{"1"} ) and $config->{"params"}->{"t"}->{"1"} ne "" ) {
        $vars->{"error"} = "You did not specify a word form.";
        return $vars;
    }
    unless ( $input{ $config->{"params"}->{"m"} } ) {
        $vars->{"error"} = "Invalid request.";
        return $vars;
    }

    # build query
    ($query) = &build_query($config);
    $vars->{"query"} = $cgi->escapeHTML($query);

    # execute query
    $id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );

    # any results?
    ($size) = $config->{"cqp"}->exec("size $id");
    $vars->{"matches"} = $size;
    return $vars if ( $size == 0 );

    # tabulate
    @matches = $config->{"cqp"}->exec("tabulate $id match word, match pos, match wc, match lemma");
    foreach my $match (@matches) {
        my ( $word, $pos, $wc, $lemma ) = split( /\t/, $match );
        $word = lc($word) if ( $config->{'params'}->{'i'}->{1} );
        $postags{$word}->{$pos}++;
        if ( $config->{"params"}->{"tt"}->{"1"} eq "wf" ) {
            $wordclasses{$word}->{$wc}++;
        }
        elsif ( $config->{"params"}->{"tt"}->{"1"} eq "l" ) {
            $wordclasses{$lemma}->{$wc}++;
        }
    }

    # split or lump
    if ( $config->{"params"}->{"dt"} eq "split" ) {
        $dthash = \%postags;
    }
    elsif ( $config->{"params"}->{"dt"} eq "lump" ) {
        $dthash = \%wordclasses;
    }
    foreach my $token ( keys %{$dthash} ) {
        foreach my $annotation ( keys %{ $dthash->{$token} } ) {
            if ( $config->{"params"}->{"dt"} eq "split" ) {
                my $wc = $config->{'tags_to_word_classes'}->{ $config->{"active"}->{"tagset"} }->{$annotation};
                croak("Cannot find word class for tag: $annotation") unless ( defined($wc) );
                push( @wordforms, [ $token, $annotation, $dthash->{$token}->{$annotation}, $wc ] );
            }
            elsif ( $config->{"params"}->{"dt"} eq "lump" ) {
                push( @wordforms, [ $token, $annotation, $dthash->{$token}->{$annotation} ] );
            }
        }
    }
    @wordforms = sort { $b->[2] <=> $a->[2] } @wordforms;
    $vars->{"word_forms"} = \@wordforms;

    # anonyme Funktion zum weiterverarbeiten
    my $call_strucn = sub {
        my ($wfline) = @_;
        foreach my $p qw(t tt p w) {
            foreach my $nr ( 1 .. 9 ) {
                $config->{'params'}->{$p}->{$nr} = "";
            }
        }
        my $freq = $wfline->[2];
        $config->{'params'}->{'t'}->{'1'} = $wfline->[0];
        if ( $config->{"params"}->{"dt"} eq "split" ) {
            $config->{'params'}->{'p'}->{'1'}  = $wfline->[1];
            $config->{'params'}->{'tt'}->{'1'} = "wf";
        }
        elsif ( $config->{"params"}->{"dt"} eq "lump" ) {
            $config->{'params'}->{'w'}->{'1'} = $wfline->[1];
            if ( $config->{"params"}->{"m"} eq "wfq" ) {
                $config->{'params'}->{'tt'}->{'1'} = "wf";
            }
            elsif ( $config->{"params"}->{"m"} eq "lq" ) {
                $config->{'params'}->{'tt'}->{'1'} = "l";
            }
        }
        return &strucn( $cgi, $config, $localdata, $freq );
    };
    $vars->{"call_strucn"} = $call_strucn;
    return $vars;
}

#--------------
# N-GRAM QUERY
#--------------
sub ngram_query {
    my ( $cgi, $config, $localdata ) = @_;
    my $vars;
    my %specifics;
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        %specifics = ( "name" => "pos" );
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        %specifics = ( "name" => "chunk" );
    }
    foreach my $nr ( 1 .. 9 ) {
        $config->{"params"}->{"i"}->{$nr} = $config->{"params"}->{"i"}->{1};
    }
    my ( $query, $pos_only_query, $title, $anchor, $query_length, $ngramref ) = &build_query($config);
    my $id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );
    my ($size) = $config->{"cqp"}->exec("size $id");
    $vars->{"query_type"} = "Structural " . $specifics{"name"} . " n-gram query";
    $vars->{"query"}      = $cgi->escapeHTML($query);
    $vars->{"vars"}       = &strucn( $cgi, $config, $localdata, $size );
    return $vars;
}

#---------------
# STRUCN QUERY
#---------------
sub strucn_query {
    my ( $cgi, $config, $localdata ) = @_;
    my ( $query, $pos_only_query, $title, $anchor, $query_length, $ngramref );
    my ( $id, $freq );
    my $vars;
    $vars->{"query_type"} = "Structural n-gram query";
    ( $query, $pos_only_query, $title, $anchor, $query_length, $ngramref ) = &build_query($config);
    $vars->{"query"} => $cgi->escapeHTML($query);
    $id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );
    ($freq) = $config->{'cqp'}->exec("size $id");
    $vars->{"vars"} = &strucn( $cgi, $config, $localdata, $freq );
    return $vars;
}

#--------------
# LEXN QUERY
#--------------
#
# rotate contingency table so that the invariable frequency of the n-gram can be stored as R1 in the database
#
#         | word | !word |
# --------+------+-------+----
#  n-gram | O11  | O12   | R1
# --------+------+-------+----
# !n-gram | O21  | O22   | R2
# --------+------+-------+----
#         |  C1  |  C2   | N
#
sub lexn_query {
    my ( $cgi, $config, $localdata ) = @_;
    my ( $query, $smallquery, $title, $anchor, $query_length, $id, $localn, $r1, @ranges, @frequencies, @cofreq, $cofreq, $ngramref );
    my ( $t0, $t1, $t2, $t01diff, $t12diff );
    my ( $qids, $qid );
    my $vars;
    my $check_cache      = $config->{"cache_dbh"}->prepare(qq{SELECT qid, r1, n FROM queries WHERE corpus=? AND class=? AND query=?});
    my $insert_query     = $config->{"cache_dbh"}->prepare(qq{INSERT INTO queries (corpus, class, query, qlen, time, r1, n) VALUES (?, ?, ?, ?, strftime('%s','now'), ?, ?)});
    my $update_timestamp = $config->{"cache_dbh"}->prepare(qq{UPDATE queries SET time=strftime('%s','now') WHERE qid=?});
    my %specifics;

    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        %specifics = (
            "name"  => "pos",
            "class" => "lexp"
        );
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        %specifics = (
            "name"  => "chunk",
            "class" => "lexc"
        );
    }
    $vars->{"query_type"} = "Lexical " . $specifics{"name"} . " n-gram query";
    ( $smallquery, $query, $title, $anchor, $query_length, $ngramref ) = &build_query($config);
    $vars->{"query"} = $cgi->escapeHTML($smallquery);

    # check cache database
    $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery );
    $qids = $check_cache->fetchall_arrayref;
    if ( scalar(@$qids) == 1 ) {
        $qid                       = $qids->[0]->[0];
        $vars->{"matches"}         = $qids->[0]->[1];
        $vars->{"analyze_matches"} = $qids->[0]->[2];
        $update_timestamp->execute($qid);
    }
    elsif ( scalar(@$qids) == 0 ) {
        my ( @cooccurrencematches, @matches );

        # execute 'large' query, expand to s, execute 'small' query
        $t0 = [ &Time::HiRes::gettimeofday() ];
        $id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );
        ($localn) = $config->{"cqp"}->exec("size $id");
        $config->{"cqp"}->exec("$id expand to s; A = $smallquery");
        ($r1) = $config->{"cqp"}->exec("size A");
        $vars->{"matches"}         = $r1;
        $vars->{"analyze_matches"} = $localn;
        return $vars if ( $localn == 0 or $r1 == 0 );

        # insert into cache.db
        if ( $query eq $smallquery ) {
            $insert_query->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery, $query_length, $r1, $config->{"active"}->{ $specifics{"name"} . "_ngrams" } );
        }
        else {
            $insert_query->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery, $query_length, $r1, $localn );
        }
        $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $smallquery );
        $qid = ( $check_cache->fetchrow_array )[0];
        $t1  = [ &Time::HiRes::gettimeofday() ];

        # get cooccurrence frequencies
        @cooccurrencematches = $config->{"cqp"}->exec("tabulate A match, matchend");

        # get overall frequencies in n-gram
        @matches = $config->{"cqp"}->exec("tabulate $id match, matchend") unless ( $query eq $smallquery );
        my $word = $config->get_attribute("word");
        my $head = $config->get_attribute("h") if ( $config->{"params"}->{"rt"} eq "chunk" );
        foreach my $ms ( [ \@cooccurrencematches, \@cofreq ], [ \@matches, \@frequencies ] ) {
            foreach my $m ( @{ $ms->[0] } ) {
                my ( $match, $matchend ) = split( /\t/, $m );

                # get cpos of sentence start and end
                my @words;
                my $core_query;
                if ( $config->{"params"}->{"rt"} eq "pos" ) {

                    # fetch word forms info via CWB::CL
                    @words = $word->cpos2str( $match .. $matchend );
                }
                elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {

                    # fetch heads info via CWB::CL
                    @words = $word->cpos2str( grep( defined( $head->cpos2struc($_) ), ( $match .. $matchend ) ) );
                }
                croak( scalar(@words) . " != $query_length\n" ) unless ( @words == $query_length );
                for ( my $i = 0; $i <= $#words; $i++ ) {
                    $ms->[1]->[$i]->{ $words[$i] }++;
                }
            }
        }
        $t2 = [ &Time::HiRes::gettimeofday() ];
        $vars->{"execution_times"} = [ map( sprintf( "%.2f", $_ ), ( &Time::HiRes::tv_interval( $t0, $t1 ), &Time::HiRes::tv_interval( $t1, $t2 ) ) ) ];

        # for all co-occurring word forms, calculate am and store in database
        my $dbh           = &create_new_db($qid);
        my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, mlen, o11, c1, am) VALUES (?, ?, ?, ?, ?, ?, ?)});
        $dbh->do(qq{BEGIN TRANSACTION});
        if ( $query eq $smallquery ) {
            my %wordfreqs;
            my $getc1 = $config->{"dbh"}->prepare( "SELECT sum(" . $specifics{"name"} . "seq) FROM types WHERE type=?" );
            for ( my $i = 0; $i <= $#cofreq; $i++ ) {
                foreach my $type ( keys %{ $cofreq[$i] } ) {
                    $wordfreqs{$type} = 0;
                }
            }
            foreach my $type ( keys %wordfreqs ) {
                $getc1->execute($type);
                $wordfreqs{$type} = ( $getc1->fetchrow_array )[0];
            }
            for ( my $i = 0; $i <= $#cofreq; $i++ ) {
                foreach my $type ( keys %{ $cofreq[$i] } ) {
                    my $g = &statistics::g( $cofreq[$i]->{$type}, $r1, $wordfreqs{$type}, $config->{"active"}->{ $specifics{"name"} . "_ngrams" } );
                    $insert_result->execute( $qid, $type, $i, $query_length, $cofreq[$i]->{$type}, $wordfreqs{$type}, $g );
                }
            }
        }
        else {
            for ( my $i = 0; $i <= $#cofreq; $i++ ) {
                foreach my $type ( keys %{ $cofreq[$i] } ) {
                    my $g = &statistics::g( $cofreq[$i]->{$type}, $r1, $frequencies[$i]->{$type}, $localn );
                    $insert_result->execute( $qid, $type, $i, $query_length, $cofreq[$i]->{$type}, $frequencies[$i]->{$type}, $g );
                }
            }
        }
        $dbh->do(qq{COMMIT});
    }
    else {
        croak("Feel proud: you witness an extremely unlikely behaviour of this website.");
    }
    %$vars = ( %$vars, %{ &print_ngram_overview_table( $cgi, $config, $qid, $ngramref ) } );
    $vars->{"slots"} = &print_ngram_query_tables( $cgi, $config, $qid, $ngramref, ( $query eq $smallquery ) );
    return $vars;
}

#-----------
# CQP QUERY
#-----------
sub cqp_query {
    my ( $cgi, $config ) = @_;
    my $vars = {};
    my ( $query, $id );
    if ( defined( $config->{"params"}->{"q"} ) and not $config->{"params"}->{"q"} =~ m/^\s*$/ ) {
        $query = $config->{"params"}->{"q"};
    }
    else {
        $vars->{"error"} = "Oh, you seem to have forgotten the query!";
        return $vars;
    }
    $query =~ s/\s+/ /g;
    $id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );
    $config->{"params"}->{"id"}    = $id;
    $config->{"params"}->{"start"} = 0;
    %$vars = (%$vars, %{&kwic::display( $cgi, $config )});
    return $vars;
}

#-------------
# BUILD QUERY
#-------------
sub build_query {
    my ($config) = @_;
    my ( @query, @unlex_query, $query, $unlex_query );
    my ( $anchor, @title, $title, $length, @ngram, $ngram );
    foreach my $nr ( 1 .. 9 ) {
        my ( $token, $head, $poswc, $query_elem, $unlex_elem, $title_elem, $token_title, $head_title, $ng_elem );
        my ( $ct,    $h,    $ht,    $i,          $p,          $t,          $tt,          $w,          $unlex );
        foreach my $pair ( [ \$t, "t" ], [ \$tt, "tt" ], [ \$p, "p" ], [ \$w, "w" ], [ \$ct, "ct" ], [ \$h, "h" ], [ \$ht, "ht" ], [ \$i, "i" ] ) {
            ${ $pair->[0] } = $config->{"params"}->{ $pair->[1] }->{$nr};
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
            $head .= "word="  if ( $ht eq "wf" );
            $head .= "lemma=" if ( $ht eq "l" );
            $head .= "'$h'";
        }
        if ( defined($t) ) {
            $token = "[";
            $token .= "word="  if ( $tt eq "wf" );
            $token .= "lemma=" if ( $tt eq "l" );
            $token .= "'$t'";
        }
        if ( defined($h) and defined($t) ) {
            $token .= ' %c' if ($i);
            $token .= " & $poswc" if ( defined($poswc) );
        }
        elsif ( defined($h) and ( not defined($t) ) ) {
            $head .= ' %c' if ($i);
            $head .= " & $poswc" if ( defined($poswc) );
        }
        elsif ( ( not defined($h) ) and defined($t) ) {
            $token .= ' %c' if ($i);
            $token .= " & $poswc" if ( defined($poswc) );
        }
        elsif ( ( not defined($h) ) and ( not defined($t) ) ) {
            if ( $config->{"params"}->{"rt"} eq "pos" ) {
                $token = "[";
                $token .= "$poswc" if ( defined($poswc) );
            }
            elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
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
                    $token{"i"}   = $+{i}   if ( defined( $+{i} ) );
                    $token{"pwt"} = $+{pwt} if ( defined( $+{pwt} ) );
                    $token{"pw"}  = $+{pw}  if ( defined( $+{pw} ) );
                }
                else {
                    croak("Unable to parse token: '$token'\n");
                }
                if ( $head =~ m/^\[(?:(?<tt>word|lemma)=(?<t>'\S+')(?<i> %c)?)?(?: & )?(?:(?<pwt>pos|wc)=(?<pw>'\S+'))?\]$/ ) {
                    $head{"tt"}  = $+{tt}  if ( defined( $+{tt} ) );
                    $head{"t"}   = $+{t}   if ( defined( $+{t} ) );
                    $head{"i"}   = $+{i}   if ( defined( $+{i} ) );
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

                    if ( $token{"i"} ) {
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
                                $combi .= " %c" if ( $_->{"i"} );
                                push( @combi, $combi );
                            }
                        }
                    }
                    elsif ( defined( $token{"tt"} ) xor defined( $head{"tt"} ) ) {
                        my $def = $return_def->( \%token, \%head, "tt" );
                        my $combi = $def->{"tt"} . "=" . $def->{"t"};
                        $combi .= " %c" if ( $def->{"i"} );
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

                #croak("neither head nor token defined: $i\n");
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
    foreach ( \$query, \$unlex_query ) {
        ${$_} =~ s/^(\[\] )*//;
        ${$_} =~ s/( \[\])*$//;
        ${$_} =~ s!^(<any> \[\]\* </any> )*!!;
        ${$_} =~ s!( <any> \[\]\* </any>)*$!!;
        ${$_} =~ s/<any>/(<adjp>|<advp>|<conjp>|<intj>|<lst>|<np>|<o>|<pp>|<prt>|<sbar>|<ucp>|<vp>)/g;
        ${$_} =~ s!</any>!(</adjp>|</advp>|</conjp>|</intj>|</lst>|</np>|</o>|</pp>|</prt>|</sbar>|</ucp>|</vp>)!g;
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
sub strucn {
    my ( $cgi, $config, $localdata, $freq ) = @_;
    my ($cached_query_id);
    my ( $qids, $ngtypes );
    my ( $t0, $t1, $t2, $t3, $t4 );
    my $skipped          = 0;
    my $check_cache      = $config->{"cache_dbh"}->prepare(qq{SELECT qid, r1, n FROM queries WHERE corpus=? AND class=? AND query=?});
    my $insert_query     = $config->{"cache_dbh"}->prepare(qq{INSERT INTO queries (corpus, class, query, qlen, time, r1, n) VALUES (?, ?, ?, ?, strftime('%s','now'), ?, ?)});
    my $update_timestamp = $config->{"cache_dbh"}->prepare(qq{UPDATE queries SET time=strftime('%s','now') WHERE qid=?});
    my $vars;
    my $frequency_threshold   = 200000;
    my $ngram_types_threshold = 750000;

    # build query
    my ( $query, $unlex_query, $title, $anchor, $query_length ) = &build_query($config);
    $vars->{"query_anchor"} = $anchor;
    $vars->{"query_title"}  = $title;
    my %specifics;
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        %specifics = (
            "name"  => "pos",
            "class" => "strucp"
        );
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        %specifics = (
            "name"  => "chunk",
            "class" => "strucc"
        );
    }
    $vars->{"return_type"}        = $specifics{"name"};
    $vars->{"frequency"}          = $freq;
    $vars->{"frequency_too_high"} = $freq >= $frequency_threshold;
    return $vars if ( $freq == 0 );
    return $vars if ( $freq >= $frequency_threshold );

    #print "query: $query", $cgi->br;
    # check cache database
    $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $query );
    $qids    = $check_cache->fetchall_arrayref;
    $ngtypes = 0;
    if ( scalar(@$qids) == 1 ) {
        my $qid = $qids->[0]->[0];
        $update_timestamp->execute($qid);
        my $dbh = DBI->connect("dbi:SQLite:user_data/$qid") or die("Cannot connect: $DBI::errstr");
        $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
        my $get_ngram_types = $dbh->prepare(qq{SELECT COUNT(*) FROM results WHERE qid=?});
        $get_ngram_types->execute($qid);
        $ngtypes                        = ( $get_ngram_types->fetchrow_array )[0];
        $vars->{"ngram_tokens"}         = $qids->[0]->[1];
        $vars->{"ngram_types"}          = $ngtypes;
        $vars->{"too_many_ngram_types"} = $ngtypes >= $ngram_types_threshold;
    }
    elsif ( scalar(@$qids) == 0 ) {
        my ( $qid, @matches, %ngrams );
        my $r1 = 0;
        $t0              = [ &Time::HiRes::gettimeofday() ];
        $cached_query_id = $config->{"cache"}->query( -corpus => $config->{"active"}->{"corpus"}, -query => $query );
        $t1              = [ &Time::HiRes::gettimeofday() ];
        my $sentence = $config->get_attribute("s");
        @matches = $config->{"cqp"}->exec("tabulate $cached_query_id match, matchend");
        $t2      = [ &Time::HiRes::gettimeofday() ];

        my $pos = $config->get_attribute("pos") if ( $config->{"params"}->{"rt"} eq "pos" );

        #my $head = $config->get_attribute("h") if($config->{"params"}->{"rt"} eq "pos");
        my $get_chunk_seq = $config->{"chunk_dbh"}->prepare(qq{SELECT chunkseq, cposseq FROM sentences WHERE cpos = ?}) if ( $config->{"params"}->{"rt"} eq "chunk" );
        foreach my $m (@matches) {
            my ( $match, $matchend ) = split( /\t/, $m );
            my $match_length;    # = ($matchend - $match) + 1;
                                 # get cpos of sentence start and end
            my ( $start, $end ) = $sentence->cpos2struc2cpos($match);
            my ( @cseq, @pseq, @rseq );
            my $core_query;
            if ( $config->{"params"}->{"rt"} eq "pos" ) {

                # fetch POS info via CWB::CL
                @cseq = map( $config->{"tag_to_number"}->{$_}, $pos->cpos2str( $start .. $end ) );
                @pseq = ( 0 .. $end - $start );

                #if($config->{"params"}->{"m"} eq "cqcl"){
                #    @hseq = $head->cpos2struc($start .. $end);
                #}
            }
            elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {

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

            # mark positions of elements (potentially) bearing restrictions
            #if($config->{"params"}->{"m"} eq "cqcl" and $config->{"params"}->{"rt"} eq "pos"){
            #@rseq = map($_ - $cstart, grep(defined($hseq[$_]), ($cstart .. $cend)));
            #}else{
            #@rseq = (0 .. $cend - $cstart);
            #}
            @rseq = ( 0 .. $cend - $cstart );
            my $max_start = $cstart - ( $config->{"active"}->{"ngram_length"} - $match_length ) > 0 ? $cstart - ( $config->{"active"}->{"ngram_length"} - $match_length ) : 0;
            my $max_end   = $cstart + ( $config->{"active"}->{"ngram_length"} - 1 ) < $#cseq        ? $cstart + ( $config->{"active"}->{"ngram_length"} - 1 )             : $#cseq;
            my $position  = $cstart - $max_start;
            my @max_ngram = @cseq[ $max_start .. $max_end ];
            $r1 += &retrieve_ngrams( \@max_ngram, \%ngrams, $config->{"active"}->{"ngram_length"}, $match_length, $position );
        }
        ## handle skipped matches
        #print "$skipped matches of length > 9 had to be discarded", $cgi->br if($skipped);
        $vars->{"ngram_tokens"} = $r1;
        return $vars if ( $r1 == 0 );

        # insert into cache database
        $insert_query->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $query, $query_length, $r1, $config->{"active"}->{ $specifics{"name"} . "_ngrams" } );
        $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $query );
        $qid = ( $check_cache->fetchrow_array )[0];
        $t3  = [ &Time::HiRes::gettimeofday() ];

        # foreach n-gram type retrieve c1 from ngrams.db and calculate association measure; store results in database
        my $dbh = &create_new_db($qid);
        $dbh->disconnect();
        undef($dbh);
        my $serialized_ngrams = $localdata->serialize( \%ngrams );
        $ngtypes                        = scalar(@$serialized_ngrams);
        $vars->{"ngram_types"}          = $ngtypes;
        $vars->{"too_many_ngram_types"} = $ngtypes >= $ngram_types_threshold;
        return $vars if ( $ngtypes >= $ngram_types_threshold );
        $localdata->add_freq_and_am( $config, $serialized_ngrams, $r1, $config->{"active"}->{ $specifics{"name"} . "_ngrams" }, $qid );
        $t4 = [ &Time::HiRes::gettimeofday() ];
        $vars->{"execution_times"} = [ map( sprintf( "%.2f", $_ ), ( &Time::HiRes::tv_interval( $t0, $t1 ), &Time::HiRes::tv_interval( $t1, $t2 ), &Time::HiRes::tv_interval( $t2, $t3 ), &Time::HiRes::tv_interval( $t3, $t4 ) ) ) ];
    }
    else {
        croak("Feel proud: you witness an extremely unlikely behaviour of this website.");
    }
    %$vars = ( %$vars, %{ &new_print_table( $cgi, $config, $query ) } );
    my $state = $config->keep_states_href( {}, qw(m c t tt p w ct id flen frel ftag fwc fpos i dt rt) );
    $vars->{"previous_href"} = "pareidoscope.cgi?start=" . max( $config->{"params"}->{"start"} - 40, 0 ) . "&s=Link&$state" if ( $config->{"params"}->{"start"} > 0 );
    $vars->{"next_href"} = "pareidoscope.cgi?start=" . ( $config->{"params"}->{"start"} + 40 ) . "&s=Link&$state" unless ( $config->{"params"}->{"start"} + 40 >= $ngtypes );
    return $vars;
}

#---------------
# CREATE NEW DB
#---------------
sub create_new_db {
    my ($qid) = @_;
    my $dbh = DBI->connect("dbi:SQLite:user_data/$qid") or die("Cannot connect: $DBI::errstr");
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
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
    my ( $cgi, $config, $mode, $ngramref, $position ) = @_;
    my %mode2text = ( "ln" => "lex", "sn" => "struc" );
    my $href      = "pareidoscope.cgi?m=$mode";
    my $params    = {};
    my @keep      = qw(c rt);
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        push( @keep, qw(p) );
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        push( @keep, qw(ct) );
    }
    my @params = qw(t tt i);
    push( @params, qw(p w h ht) ) if ( $config->{"params"}->{"rt"} eq "chunk" );
    foreach my $nr ( 0 .. $#$ngramref ) {
        foreach my $param (@params) {
            $params->{ $param . ( $nr + 1 ) } = "";
        }
    }
    foreach my $nr ( 0 .. $#$ngramref ) {
        foreach my $param (@params) {
            $params->{ $param . ( $nr + $position + 1 ) } = $config->{"params"}->{$param}->{ $nr + 1 } if ( defined( $config->{"params"}->{$param}->{ $nr + 1 } ) and $config->{"params"}->{$param}->{ $nr + 1 } ne "" );
        }
        if ( $config->{"params"}->{"rt"} eq "pos" ) {
            $params->{ "p" . ( $nr + 1 ) } = $ngramref->[$nr];
        }
        elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
            $params->{ "ct" . ( $nr + 1 ) } = $ngramref->[$nr];
        }
    }
    my $state = $config->keep_states_href( $params, ( @keep, @params ) );
    $href .= "&s=Link&$state";

    #return $cgi->a( { 'href' => $href }, $mode2text{$mode} );
    return $cgi->escapeHTML($href);
}

#-------------------
# CREATE N LINK LEX
#-------------------
sub create_n_link_lex {
    my ( $cgi, $config, $mode, $ngramref, $position, $head ) = @_;
    my %mode2text = ( "ln" => "lex", "sn" => "struc" );
    my $state;
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        $state = $config->keep_states_href( { "t" . ( $position + 1 ) => $head, "tt" . ( $position + 1 ) => "wf", "i" . ( $position + 1 ) => 0 }, qw(c rt p w i t tt) );
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        $state = $config->keep_states_href( { "h" . ( $position + 1 ) => $head, "ht" . ( $position + 1 ) => "wf", "i" . ( $position + 1 ) => 0 }, qw(c rt t tt p w i ct h ht) );
    }
    my $href = "pareidoscope.cgi?m=$mode&s=link&$state";

    #return $cgi->a( { "href" => $href }, $mode2text{$mode} );
    return $cgi->escapeHTML($href);
}

#----------------------
# CREATE FREQ LINK LEX
#----------------------
sub create_freq_link_lex {
    my ( $cgi, $config, $freq, $ngramref, $position, $head ) = @_;
    my $state       = $config->keep_states_href( {}, qw(c) );
    my $href        = "pareidoscope.cgi?m=c&q=";
    my $localparams = Storable::dclone( $config->{"params"} );
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        $localparams->{"t"}->{ $position + 1 }  = $head;
        $localparams->{"tt"}->{ $position + 1 } = "wf";
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        $localparams->{"h"}->{ $position + 1 }  = $head;
        $localparams->{"ht"}->{ $position + 1 } = "wf";
    }
    $localparams->{"i"}->{ $position + 1 } = 0;
    my ($query) = &build_query( { "params" => $localparams } );
    $href .= URI::Escape::uri_escape($query) . "&s=Link";
    $href .= "&$state";

    #return $cgi->a( { 'href' => $href }, $freq );
    return $cgi->escapeHTML($href);
}

#------------------------
# CREATE NGFREQ LINK LEX
#------------------------
sub create_ngfreq_link_lex {
    my ( $cgi, $config, $freq, $ngramref, $position, $head ) = @_;
    my $state       = $config->keep_states_href( {}, qw(c) );
    my $href        = "pareidoscope.cgi?m=c&q=";
    my $localparams = Storable::dclone( $config->{"params"} );
    my @deletions   = qw(t tt w ht h i);
    push( @deletions, "p" ) if ( $config->{"params"}->{"rt"} eq "chunk" );
    foreach my $param (@deletions) {
        foreach my $i ( 1 .. 9 ) {
            undef( $localparams->{$param}->{$i} );
        }
    }
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        $localparams->{"t"}->{ $position + 1 }  = $head;
        $localparams->{"tt"}->{ $position + 1 } = "wf";
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        $localparams->{"h"}->{ $position + 1 }  = $head;
        $localparams->{"ht"}->{ $position + 1 } = "wf";
    }
    my ($query) = &build_query( { "params" => $localparams } );
    $href .= URI::Escape::uri_escape($query) . "&s=Link";
    $href .= "&$state";

    #return $cgi->a( { 'href' => $href }, $freq );
    return $cgi->escapeHTML($href);
}

#------------------------
# CREATE FREQ LINK STRUC
#------------------------
sub create_freq_link_struc {
    my ( $cgi, $config, $freq, $position, @ngram ) = @_;
    my $state       = $config->keep_states_href( {}, qw(c) );
    my $href        = "pareidoscope.cgi?m=c&q=";
    my $localparams = Storable::dclone( $config->{"params"} );
    my @deletions   = qw(ct t tt w ht h p);
    foreach my $param (@deletions) {
        foreach my $i ( 1 .. 9 ) {
            undef( $localparams->{$param}->{$i} );
        }
    }
    for ( my $i = 0; $i <= $#ngram; $i++ ) {
        my $j = $i + 1 - $position;
        if ( $j > 0 ) {
            foreach my $param qw(t tt h ht) {
                $localparams->{$param}->{ $i + 1 } = $config->{"params"}->{$param}->{$j};
            }
        }
        if ( $config->{"params"}->{"rt"} eq "pos" ) {
            $localparams->{"p"}->{ $i + 1 } = $ngram[$i];
        }
        elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
            $localparams->{"ct"}->{ $i + 1 } = $ngram[$i];
            $localparams->{"p"}->{ $i + 1 }  = $config->{"params"}->{"p"}->{$j};
            $localparams->{"w"}->{ $i + 1 }  = $config->{"params"}->{"w"}->{$j};
        }
    }
    my ($query) = &build_query( { "params" => $localparams } );
    $href .= URI::Escape::uri_escape($query) . "&s=Link";
    $href .= "&$state";

    #return $cgi->a( { 'href' => $href }, $freq );
    return $cgi->escapeHTML($href);
}

#--------------------------
# CREATE NGFREQ LINK STRUC
#--------------------------
sub create_ngfreq_link_struc {
    my ( $cgi, $config, $ngfreq, @ngram ) = @_;
    my $state       = $config->keep_states_href( {}, qw(c) );
    my $href        = "pareidoscope.cgi?m=c&q=";
    my $localparams = Storable::dclone( $config->{"params"} );
    my @deletions   = qw(ct t tt w ht h p);
    foreach my $param (@deletions) {
        foreach my $i ( 1 .. 9 ) {
            undef( $localparams->{$param}->{$i} );
        }
    }
    for ( my $i = 0; $i <= $#ngram; $i++ ) {
        if ( $config->{"params"}->{"rt"} eq "pos" ) {
            $localparams->{"p"}->{ $i + 1 } = $ngram[$i];
        }
        elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
            $localparams->{"ct"}->{ $i + 1 } = $ngram[$i];
        }
    }
    my ($query) = &build_query( { "params" => $localparams } );
    $href .= URI::Escape::uri_escape($query) . "&s=Link";
    $href .= "&$state";

    #return $cgi->a( { 'href' => $href }, $ngfreq );
    return $cgi->escapeHTML($href);
}

#-----------------
# NEW PRINT TABLE
#-----------------
sub new_print_table {
    my ( $cgi, $config, $query ) = @_;
    my ( $qids, $qid, $query_length );
    my ( $filter_length, $filter_pos ) = ( "", "" );
    my $vars;
    my %filter_relations = ( 1 => ">=", 2 => "<=", 3 => "=" );
    my %specifics;
    if ( $config->{"params"}->{"rt"} eq "pos" ) {
        %specifics = (
            "map"   => "number_to_tag",
            "class" => "strucp"
        );
    }
    elsif ( $config->{"params"}->{"rt"} eq "chunk" ) {
        %specifics = (
            "map"   => "number_to_chunk",
            "class" => "strucc"
        );
    }
    my $check_cache = $config->{"cache_dbh"}->prepare(qq{SELECT qid, qlen, r1, n FROM queries WHERE corpus=? AND class=? AND query=?});
    $check_cache->execute( $config->{"active"}->{"corpus"}, $specifics{"class"}, $query );
    $qids = $check_cache->fetchall_arrayref;
    croak("Error while processing cache database.") unless ( scalar(@$qids) == 1 );
    $qid          = $qids->[0]->[0];
    $query_length = $qids->[0]->[1];
    my $dbh = DBI->connect("dbi:SQLite:user_data/$qid") or die("Cannot connect: $DBI::errstr");
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
    $dbh->do("PRAGMA cache_size = 50000");
    $filter_length = 'AND length(result) ' . $filter_relations{ $config->{"params"}->{"frel"} } . ' ' . ( $config->{"params"}->{"flen"} * 2 + 2 ) if ( defined( $config->{"params"}->{"flen"} ) and defined( $config->{"params"}->{"frel"} ) );

    if ( ( ( defined( $config->{"params"}->{"ftag"} ) and $config->{"params"}->{"ftag"} ne "" ) or ( defined( $config->{"params"}->{"fwc"} ) and $config->{"params"}->{"fwc"} ne "" ) or ( defined( $config->{"params"}->{"fch"} ) and $config->{"params"}->{"fch"} ne "" ) ) and ( defined( $config->{"params"}->{"fpos"} ) and $config->{"params"}->{"fpos"} ne "" ) ) {
        my $ftaghex;
        if ( defined( $config->{"params"}->{"ftag"} ) and $config->{"params"}->{"ftag"} ne "" ) {
            $ftaghex = sprintf( "%02x", $config->{"tag_to_number"}->{ $config->{"params"}->{"ftag"} } );
        }
        elsif ( defined( $config->{"params"}->{"fwc"} ) and $config->{"params"}->{"fwc"} ne "" ) {
            $ftaghex = '(' . join( '|', map( sprintf( "%02x", $config->{"tag_to_number"}->{$_} ), @{ $config->{"word_classes_to_tags"}->{ $config->{"active"}->{"tagset"} }->{ $config->{"params"}->{"fwc"} } } ) ) . ')';
        }
        elsif ( defined( $config->{"params"}->{"fch"} ) and $config->{"params"}->{"fch"} ne "" ) {
            $ftaghex = sprintf( "%02x", $config->{"chunk_to_number"}->{ $config->{"params"}->{"fch"} } );
        }
        else {
            croak("How comes?");
        }
        $filter_pos = 'AND result REGEXP \'';

        # on the right side
        if ( $config->{"params"}->{"fpos"} == 1 ) {
            $filter_pos .= ">([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*\$";
        }

        # on the left side
        elsif ( $config->{"params"}->{"fpos"} == 2 ) {
            $filter_pos .= "^([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*<";
        }

        # on either side
        elsif ( $config->{"params"}->{"fpos"} == 3 ) {
            $filter_pos .= "(^([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*<)|(>([0-9a-f]{2})*$ftaghex([0-9a-f]{2})*\$)";
        }
        $filter_pos .= '\'';
    }
    my $get_top_50 = $dbh->prepare(qq{SELECT result, position, mlen, o11, c1, am FROM results WHERE qid=? $filter_length $filter_pos ORDER BY am DESC, o11 DESC LIMIT $config->{"params"}->{"start"}, 40});
    $get_top_50->execute($qid);
    my $rows = $get_top_50->fetchall_arrayref;
    $vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( $cgi, {}, qw(m c rt dt start t tt p w i ht h ct) );
    $vars->{"pos_tags"}      = $config->{"number_to_tag"};
    $vars->{"word_classes"}  = [ "", sort keys %{ $config->{"word_classes_to_tags"}->{ $config->{"active"}->{"tagset"} } } ];
    my $counter = $config->{"params"}->{"start"};

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
        @ngram                    = map( $config->{ $specifics{"map"} }->[$_], map( hex($_), unpack( "(a2)*", $result ) ) );
        @display_ngram            = @ngram;
        $display_ngram[$position] = "<em>$display_ngram[$position]";
        $display_ngram[ $position + $mlen - 1 ] .= "</em>";
        $display_ngram = join( " ", @display_ngram );
        $row->{"display_ngram"} = $display_ngram;

        # CREATE LEX AND STRUC LINKS
        $row->{"struc_href"} = &create_n_link_struc( $cgi, $config, "sn", \@ngram, $position );
        $row->{"lex_href"}   = &create_n_link_struc( $cgi, $config, "ln", \@ngram, $position );
        $row->{"cofreq_href"} = &create_freq_link_struc( $cgi, $config, $o11, $position, @ngram );
        $row->{"ngfreq_href"} = &create_ngfreq_link_struc( $cgi, $config, $c1, @ngram );
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
    my ( $tagsref, $nghashref, $maxlength, $match_length, $position ) = @_;
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
            $nghashref->{$ngram}->{$localposition}->{$match_length}++;
            $localr1++;
        }
    }
    return $localr1;
}

#--------------------------
# PRINT NGRAM QUERY TABLES
#--------------------------
sub print_ngram_query_tables {
    my ( $cgi, $config, $qid, $ngramref, $general ) = @_;
    my $dbh = DBI->connect("dbi:SQLite:user_data/$qid") or die("Cannot connect: $DBI::errstr");
    print $cgi->end_table, $cgi->end_p;
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
    my $get_top_50    = $dbh->prepare(qq{SELECT result, position, o11, c1, am FROM results WHERE position=? ORDER BY am DESC, o11 DESC LIMIT 0, 40});
    my $get_positions = $dbh->prepare(qq{SELECT DISTINCT position FROM results ORDER BY position ASC});
    $get_positions->execute();
    my $positionsref = $get_positions->fetchall_arrayref;
    my $slots;
    foreach my $position (@$positionsref) {
        my $slot;
        $position = $position->[0];
        $get_top_50->execute($position);
        my $rows = $get_top_50->fetchall_arrayref;
        $slot->{"name"} = $ngramref->[$position];
        my $counter = 0;
        foreach my $row (@$rows) {
            my $slotrow;
            my ( $result, $posit, $o11, $c1, $g2 ) = @$row;
            $g2 = sprintf( "%.5f", $g2 );
            my ( $freqlink, $ngfreqlink, $lexnlink, $strucnlink );
            my %words;
            foreach my $nr ( keys %{ $config->{'params'}->{'q'} } ) {
                $words{$nr} = $config->{'params'}->{'q'}->{$nr} if ( defined( $config->{'params'}->{'q'}->{$nr} ) and $config->{'params'}->{'q'}->{$nr} ne "" );
            }
            $words{ $position + 1 } = $result;
            $slotrow->{"word"} = $result;
            $slotrow->{"cofreq_href"} = &create_freq_link_lex( $cgi, $config, $o11, $ngramref, $position, $result );
            $slotrow->{"ngfreq_href"} = &create_ngfreq_link_lex( $cgi, $config, $c1, $ngramref, $position, $result ) unless ($general);
            $slotrow->{"lex_href"}   = &create_n_link_lex( $cgi, $config, "ln", $ngramref, $position, $result );
            $slotrow->{"struc_href"} = &create_n_link_lex( $cgi, $config, "sn", $ngramref, $position, $result );
            $counter++;
            $slotrow->{"number"} = $counter;
            $slotrow->{"cofreq"} = $o11;
            $slotrow->{"ngfreq"} = $c1;
            $slotrow->{"g"}      = $g2;
	    push( @{ $slot->{"rows"} }, $slotrow );
        }
	push(@$slots, $slot);
    }
    return $slots;
}

#----------------------------
# PRINT NGRAM OVERVIEW TABLE
#----------------------------
sub print_ngram_overview_table {
    my ( $cgi, $config, $qid, $ngramref ) = @_;
    my $vars;
    my $dbh = DBI->connect("dbi:SQLite:user_data/$qid") or die("Cannot connect: $DBI::errstr");
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
    my $get_top_10    = $dbh->prepare(qq{SELECT result, position, o11, c1, am FROM results WHERE position=? ORDER BY am DESC, o11 DESC LIMIT 0, 10});
    my $get_positions = $dbh->prepare(qq{SELECT DISTINCT position FROM results ORDER BY position ASC});
    $get_positions->execute();
    my $positionsref = $get_positions->fetchall_arrayref;
    my @columns;

    foreach my $position (@$positionsref) {
        $position = $position->[0];
        $get_top_10->execute($position);
        my $rows = $get_top_10->fetchall_arrayref;
        push( @{ $columns[$position] }, $ngramref->[$position] );
        my $counter = 0;
        foreach my $row (@$rows) {
            my ( $result, $posit, $o11, $c1, $g2 ) = @$row;
            push( @{ $columns[$position] }, $result );
        }
        push( @{ $columns[$position] }, ( "", "", "", "", "", "", "", "", "", "" ) );
    }
        $vars->{"row_numbers"}    = [ 0 ];
    foreach my $i (1 .. 10) {
	last if ( join( "", map( $_->[$i], @columns ) ) eq "" );
	push(@{$vars->{"row_numbers"}}, $i);
    }
    $vars->{"column_numbers"} = [ 0 .. $#columns ];
    $vars->{"overview_table"} = \@columns;
    return $vars;
}

#---------------
# OLD FUNCTIONS
#---------------

#-------------
# BUILD QUERY
#-------------
sub old_build_query {
    my ($config) = @_;
    my ( @query, @pos_only_query, $query, $pos_only_query );
    my ( $anchor, @title, $title, @length, $length, @ngram, $ngram );
    foreach my $i ( 1 .. 9 ) {
        my ( $q_alt, $t_elem, $q_elem, $poq_elem, $ng_elem );
        my $t = $config->{"params"}->{"t"}->{$i};
        my $q = $config->{"params"}->{"q"}->{$i};
        $t = undef if ( defined($t) and $t eq "" );
        $q = undef if ( defined($q) and $q eq "" );
        $q_alt = $q;
        $q_alt =~ s/([][.?*+|(){}^\$'])/\\$1/g if ( defined($q) );
        croak("Invalid query.") if ( defined($q) and not defined($t) );
        $poq_elem = defined($t) ? "[pos='$t']" : "[]";
        $ng_elem  = defined($t) ? $t           : "x";
        $q_elem   = "[";
        $q_elem .= defined($q) ? "word='$q_alt'" : "";
        $q_elem .= ( defined($q) and defined( $config->{'params'}->{'i'} ) and $config->{'params'}->{'i'} == 1 ) ? ' %c' : '';
        $q_elem .= " & " if ( defined($q) and defined($t) );

        if ( defined($t) ) {
            $q_elem .= "pos='$t'";
            $t_elem = defined($q) ? "$q_alt/$t" : "x/$t";
        }
        else {
            $t_elem = defined($q) ? "$q_alt" : "x";
        }
        $q_elem .= "]";

        #my $t_elem = defined($q) or defined($t) ? "$q_alt/$t" : "x";
        push( @query,          $q_elem );
        push( @pos_only_query, $poq_elem );
        push( @title,          $t_elem );
        push( @ngram,          $ng_elem );
    }
    $query          = join( " ", @query );
    $pos_only_query = join( " ", @pos_only_query );
    $title          = join( " ", @title );
    $query =~ s/^(\[\] )*//;
    $query =~ s/( \[\])*$//;
    $query .= " within s";
    $query          =~ s/\s+/ /;
    $pos_only_query =~ s/^(\[\] )*//;
    $pos_only_query =~ s/( \[\])*$//;
    $pos_only_query .= " within s";
    $pos_only_query =~ s/\s+/ /;
    $title          =~ s/^(x )*//;
    $title          =~ s/( x(?!\/))*$//;
    $anchor = $title;
    $anchor =~ s/ /_/g;
    @length = split( / /, $title );
    $length = scalar(@length);
    $ngram  = join( " ", @ngram );
    $ngram =~ s/^(x )*//;
    $ngram =~ s/( x)*$//;
    @ngram = split( " ", $ngram );
    return ( $query, $pos_only_query, $title, $anchor, $length, \@ngram );
}

1;
