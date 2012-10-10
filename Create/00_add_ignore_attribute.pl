#!/usr/bin/perl
package Attribute::Ignore;

use 5.010;

use strict;
use warnings;
use open qw(:utf8 :std);
use utf8;
use English qw(-no_match_vars);

# use version; our $VERSION = qv('0.0.1');
use Carp;    # carp croak

# use Data::Dumper;            # Dumper
# use List::Util;              # first max maxstr min minstr reduce shuffle sum
use List::MoreUtils qw(first_index);         # "the stuff missing in List::Util"
use Log::Log4perl qw(:easy); # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
Log::Log4perl->easy_init( $DEBUG );

use Readonly;
Readonly my $UNLIMITED_NUMBER_OF_FIELDS       => -1;
Readonly my $MAXIMUM_NUMBER_OF_SUBGRAPH_EDGES => 10;

use Graph::Directed;
use Set::Object;

sub add_ignore {
    my ($corpus_file) = @_;
    open my $cfh, '<', $corpus_file or croak "Cannot open $corpus_file: $OS_ERROR";
    open my $out, '>', "${corpus_file}.ignore_test" or croak "Cannot open ${corpus_file}.ignore: $OS_ERROR";
    local $INPUT_RECORD_SEPARATOR = "</s>\n";
OUTER:
    while ( my $sentence = <$cfh> ) {
        my @sentence = split /\n/xms, $sentence;
	$sentence[$#sentence] .= "\n";
	my $s_index = first_index {/^<s[ ][^>]+>$/xms} @sentence;
        my @tokens = grep { $_ !~ /^<[^>]+>$/xms } @sentence;
	my ( @word_forms, @indeps, @outdeps, @roots );
        my $root;
        foreach my $token (@tokens) {
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
		$sentence[$s_index] =~ s/\s*>$/ ignore="yes-edges">/xms;
		print $out join "\n", @sentence;
                next OUTER;
            }
            foreach my $dep ( split( /[|]/xms, $outdep ) ) {
                #$dep =~ m/^(?<relation>[^(]+)[(]0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/xms;
		$dep =~ m/^(?<relation>[^(]+)[(]0(?:')*,(?<offset>-?\d+)(?:')*/xms;
                my $target = $i + $LAST_PAREN_MATCH{"offset"};
                next if ( $i == $target );
                $graph->add_edge( $i, $target );
            }
        }

        # Skip rootless sentences
        if ( !defined $root ) {
	    $sentence[$s_index] =~ s/\s*>$/ ignore="yes-rootless">/xms;
	    print $out join "\n", @sentence;
            next OUTER;
        }

        # Skip unconnected graphs (necessary because of a bug in the current version of the Stanford Dependencies converter)
        if ( ( $graph->vertices() > 1 ) && ( !$graph->is_weakly_connected() ) ) {
	    $sentence[$s_index] =~ s/\s*>$/ ignore="yes-unconnected">/xms;
	    print $out join "\n", @sentence;
            next OUTER;
        }

        # check if all vertices are reachable from the root
        my $graph_successors = Set::Object->new( $root, $graph->all_successors($root) );
        my $graph_vertices = Set::Object->new( $graph->vertices() );
        if ( $graph_successors->not_equal($graph_vertices) ) {
	    $sentence[$s_index] =~ s/\s*>$/ ignore="yes-unreachable">/xms;
	    print $out join "\n", @sentence;
            next OUTER;
        }
	$sentence[$s_index] =~ s/\s*>$/ ignore="no">/xms;
	print $out join "\n", @sentence;
    }
    close $cfh or croak "Cannot close $corpus_file: $OS_ERROR";
    close $out or croak "Cannot close ${corpus_file}.ignore: $OS_ERROR";
}

__PACKAGE__->run(@ARGV) unless caller;

sub run {
    my ( $class, @args ) = @_;
    my $corpus_file = shift @args;
    add_ignore($corpus_file);
}

1;
