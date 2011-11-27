#!/usr/bin/perl

use strict;
use warnings;

# redirect errors:
#open(STDERR,">$0.debug");

# Template Toolkit
use Template;

# CGI stuff
use CGI;    #qw/:standard *table *div *p/;
use CGI::Pretty;
use CGI::Carp qw(fatalsToBrowser);

use config;
use localdata_client;
use executequeries;
use kwic;

use Data::Dumper;

$CGI::POST_MAX        = 50 * 1024;    # avoid denial-of-service attacks
$CGI::DISABLE_UPLOADS = 1;            # (no file uploads, accept max. 50k of POST data)

&main();

#------
# MAIN
#------
sub main {
    my $cgi    = new CGI;
    my $config = config->new($cgi);
    $config->init_corpus( $config->{"params"}->{"c"} );
    my $localdata = localdata_client->init( $config->{"active"}->{"localdata"}, @{ $config->{"active"}->{"machines"} } );

    # Output:
    print $cgi->header( -type => 'text/html', -charset => 'utf-8' );
    my $state    = $config->keep_states_href( {}, qw(c) );
    my $template = Template->new();
    my $vars     = {
        "state"       => $state,
        "version"     => $config->{"version"},
        "corpus_name" => $config->{"active"}->{"display_name"},
        "menu"        => $config->{"params"}->{"m"}
    };
    if ( defined( $config->{"params"}->{"s"} ) ) {
        &print_results( $cgi, $config, $localdata, $template, $vars );
    }
    else {
        &print_info_or_forms( $cgi, $config, $template, $vars );
    }
}

#---------------------
# PRINT INFO OR FORMS
#---------------------
sub print_info_or_forms {
    my ( $cgi, $config, $template, $vars ) = @_;
    my @wcs = sort keys %{ $config->{"word_classes_to_tags"}->{ $config->{"active"}->{"tagset"} } };

    # HOME
    if ( $config->{"params"}->{"m"} eq "o" ) {
        $template->process( "home", $vars ) or die( $template->error() );
    }

    # HELP
    elsif ( $config->{"params"}->{"m"} eq "h" ) {
        $template->process( "help", $vars ) or die( $template->error() );
    }

    # ABOUT
    elsif ( $config->{"params"}->{"m"} eq "a" ) {
        $template->process( "about", $vars ) or die( $template->error() );
    }

    # WORD FORM QUERY
    elsif ( $config->{"params"}->{"m"} eq "wfq" ) {
        $vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( { "tt1" => "wf" }, qw(c m) );
        $vars->{"pos_tags"}      = $config->{"number_to_tag"};
        $vars->{"word_classes"}  = [ "", @wcs ];
        $vars->{"chunks"}        = $config->{"active"}->{"chunk_db"};
        $template->process( "word_form_query", $vars ) or die( $template->error() );
    }

    # LEMMA QUERY
    elsif ( $config->{"params"}->{"m"} eq "lq" ) {
        $vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( { "tt1" => "l" }, qw(c m) );
        $vars->{"word_classes"}  = [@wcs];
        $vars->{"chunks"}        = $config->{"active"}->{"chunk_db"};
        $template->process( "lemma_query", $vars ) or die( $template->error() );
    }

    # COMPLEX QUERY (TOKEN LEVEL)
    elsif ( $config->{"params"}->{"m"} eq "cqtl" ) {
        $vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( { "m" => "snq" }, qw(c) );
        $vars->{"pos_tags"}      = $config->{"number_to_tag"};
        $vars->{"word_classes"}  = [ "", @wcs ];
        $template->process( "complex_query_token", $vars ) or die( $template->error() );
    }

    # COMPLEX QUERY (CHUNK LEVEL)
    elsif ( $config->{"params"}->{"m"} eq "cqcl" ) {
        $vars->{"hidden_states"} = $config->keep_states_listref_of_hashrefs( { "m" => "snq" }, qw(c) );
        $vars->{"pos_tags"}      = $config->{"number_to_tag"};
        $vars->{"word_classes"}  = [ "", @wcs ];
        $vars->{"chunk_types"}   = [ "any", @{ $config->{"number_to_chunk"} }[ 1 .. $#{ $config->{"number_to_chunk"} } ] ];
        $vars->{"chunks"}        = $config->{"active"}->{"chunk_db"};
        $template->process( "complex_query_chunk", $vars ) or die( $template->error() );
    }

    # CHANGE CORPUS
    elsif ( $config->{"params"}->{"m"} eq "cc" ) {
        my $beautify = sub { $_[0] = reverse $_[0]; $_[0] =~ s/(\d{3})(?=\d)/$1,/g; return scalar reverse $_[0]; };
        my $yesno = sub { return $_[0] ? "yes" : "no" };
        my $corpus_name = sub { return $_[0] == $config->{"active"} ? $_[0]->{"display_name"} . " (active)" : $cgi->a( { "href" => "pareidoscope.cgi?m=cc&c=" . $_[0]->{"corpus"} }, $_[0]->{"display_name"} ) };
        my @corpora = map( {
                "name"      => $corpus_name->($_),
                "tokens"    => $beautify->( $_->{"tokens"} ),
                "sentences" => $beautify->( $_->{"sentences"} ),
                "tagset"    => $_->{"tagset"},
                "chunks"    => $yesno->( $_->{"chunk_db"} )
            },
            grep( $_->{"available"}, @{ $config->{"corpora"} } ) );
        $vars->{"corpora"} = \@corpora;
        $template->process( "change_corpus", $vars ) or die( $template->error() );
    }

    # ELSE
    else {
        $vars->{"error"} = "I am sorry, but I do not know what I can do for you (unknown or missing parameter).";
        $vars->{"dump"}  = Dumper($config);
        $template->process( "unknown", $vars ) or die( $template->error() );
    }
}

#---------------
# PRINT RESULTS
#---------------
sub print_results {
    my ( $cgi, $config, $localdata, $template, $vars ) = @_;

    # WORD FORM QUERY or
    # LEMMA QUERY
    if (   ( $config->{"params"}->{"m"} eq "wfq" )
        or ( $config->{"params"}->{"m"} eq "lq" ) )
    {
        $vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        %$vars = ( %$vars, %{ &executequeries::single_item_query( $cgi, $config, $localdata ) } );
        $template->process( "single_item_query_results", $vars ) or die( $template->error() );
    }

    # LEXICAL N-GRAM QUERY
    elsif ( $config->{"params"}->{"m"} eq "ln" ) {
	$vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        %$vars = ( %$vars, %{ &executequeries::lexn_query( $cgi, $config, $localdata ) } );
        $template->process( "lexical_query_results", $vars ) or die( $template->error() );
    }

    # STRUCTURAL N-GRAM QUERY
    elsif ( $config->{"params"}->{"m"} eq "sn" ) {
	$vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        %$vars = ( %$vars, %{ &executequeries::strucn_query( $cgi, $config, $localdata ) } );
        $template->process( "ngram_query_results", $vars ) or die( $template->error() );
    }

    # STRUCTURAL N-GRAM QUERY (USER INPUT; TOKEN LEVEL AND CHUNK LEVEL)
    elsif ( $config->{"params"}->{"m"} eq "snq" ) {
        $vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        %$vars = ( %$vars, %{ &executequeries::ngram_query( $cgi, $config, $localdata ) } );
        $template->process( "ngram_query_results", $vars ) or die( $template->error() );
    }

    # CQP QUERY
    elsif ( $config->{"params"}->{"m"} eq "c" ) {
        $vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        %$vars = ( %$vars, %{ &executequeries::cqp_query( $cgi, $config ) } );
        $template->process( "kwic", $vars ) or die( $template->error() );
    }

    # DISPLAY KWIC
    elsif ( $config->{"params"}->{"m"} eq "d" ) {
        $vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        %$vars = ( %$vars, %{ &kwic::display( $cgi, $config ) } );
        $template->process( "kwic", $vars ) or die( $template->error() );
    }

    # DISPLAY CONTEXT
    elsif ( $config->{"params"}->{"m"} eq "dc" ) {
        $vars->{"display_loading"} = 1;
	&print_header($template, $vars);
        $vars->{"ps"} = &kwic::display_context( $cgi, $config );
        $template->process( "context_display", $vars ) or die( $template->error() );
    }

    # ELSE
    else {
        $vars->{"error"} = "I am sorry, but I do not know what I can do for you (unknown or missing parameter).";
        $vars->{"dump"}  = Dumper($config);
        $template->process( "unknown", $vars ) or die( $template->error() );
    }
}

sub print_header {
    my ($template, $vars) = @_;
    my $out = "";
    my $ofh = select STDOUT;
    $| = 1;
    $template->process( "header", $vars, \$out ) or die( $template->error() );
    print $out;
    print " " x 1024 . "\n";
    $| = 0;
    select $ofh;
}
