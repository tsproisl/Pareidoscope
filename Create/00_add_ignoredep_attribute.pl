#!/usr/bin/perl
package Attribute::Ignoredep;

use 5.010;

use strict;
use warnings;
use open qw(:utf8 :std);
use utf8;
use English qw(-no_match_vars);

# use version; our $VERSION = qv('0.0.1');
use Carp;                    # carp croak
# use Data::Dumper;            # Dumper
# use List::Util;              # first max maxstr min minstr reduce shuffle sum
# use List::MoreUtils;         # "the stuff missing in List::Util"
# use Log::Log4perl qw(:easy); # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
# Log::Log4perl->easy_init( $DEBUG );

use Readonly;
Readonly my $UNLIMITED_NUMBER_OF_FIELDS       => -1;
Readonly my $MAXIMUM_NUMBER_OF_SUBGRAPH_EDGES => 10;

use XML::Twig;
use Graph::Directed;
use Set::Object;

sub add_ignoredep {
    my ($corpus_file) = @_;
    #open STDOUT, ">", $corpus_file . '.ignoredep' or croak "Cannot reopen STDOUT: $OS_ERROR";
    open STDOUT, "| perl -pe 's/(<[^>]+>)(?!\$)/\$1\n/g' > ${corpus_file}.ignoredep" or croak "Cannot reopen STDOUT: $OS_ERROR";
    my $twig = XML::Twig->new( twig_handlers => { s => \&_s_handler } );
    $twig->parsefile($corpus_file);
    $twig->flush;
}

sub _s_handler {
    my ( $twig, $s, $corpus_file ) = @_;
    my $text = $s->text;
    $text =~ s/^\n//xms;
    my @text = split /\n+/xms, $text;
    my ( @word_forms, @indeps, @outdeps, @roots );
    my $root;
    foreach my $token (@text) {
        my ( $word, $pos, $lemma, $wc, $indep, $outdep, $root ) = split /\t/xms, $token;
        push @word_forms, $word;
        push @indeps,     $indep;
        push @outdeps,    $outdep;
        push @roots,      $root;
    }
    my $graph = Graph::Directed->new;

    for ( my $i = 0; $i <= $#word_forms; $i++ ) {
        $root = $i if ( $roots[$i] eq "root" );
        my $indep  = $indeps[$i];
        my $outdep = $outdeps[$i];
        $indep  =~ s/^\|//;
        $outdep =~ s/^\|//;
        $indep  =~ s/\|$//;
        $outdep =~ s/\|$//;

        # Skip sentences with nodes that have more than ten edges
        if ( scalar( () = split( /\|/, $indep, $UNLIMITED_NUMBER_OF_FIELDS ) ) + scalar( () = split( /\|/, $outdep, -1 ) ) > $MAXIMUM_NUMBER_OF_SUBGRAPH_EDGES ) {
            $s->set_att( 'depignore' => 'yes-edges' );
            $s->flush;
            return;
        }
        foreach my $dep ( split( /[|]/xms, $outdep ) ) {
            $dep =~ m/^(?<relation>[^(]+)[(]0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/xms;
            my $target = $i + $LAST_PAREN_MATCH{"offset"};
            next if ( $i == $target );
            $graph->add_edge( $i, $target );
        }
    }

    # Skip rootless sentences
    if ( !defined $root ) {
        $s->set_att( 'depignore' => 'yes-rootless' );
        $s->flush;
        return;
    }

    # Skip unconnected graphs (necessary because of a bug in the current version of the Stanford Dependencies converter)
    if ( ( $graph->vertices() > 1 ) && ( !$graph->is_weakly_connected() ) ) {
        $s->set_att( 'depignore' => 'yes-unconnected' );
        $s->flush;
        return;
    }

    # check if all vertices are reachable from the root
    my $graph_successors = Set::Object->new( $root, $graph->all_successors($root) );
    my $graph_vertices = Set::Object->new( $graph->vertices() );
    if ( $graph_successors->not_equal($graph_vertices) ) {
        $s->set_att( 'depignore' => 'yes-unreachable' );
        $s->flush;
        return;
    }
    $s->set_att( 'depignore' => 'no' );
    $s->flush;
    return;
}

__PACKAGE__->run(@ARGV) unless caller;

sub run {
    my ( $class, @args ) = @_;
    my $corpus_file = shift @args;
    add_ignoredep($corpus_file);
}

1;
