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

use version; our $VERSION = qv('0.0.1');
use Carp;    # carp croak

use Readonly;
Readonly my $MAXIMUM_NUMBER_OF_RELATIONS => 10;
Readonly my $UNLIMITED_NUMBER_OF_FIELDS  => -1;
Readonly my $GET_ATTRIBUTE_USAGE         => 'Usage: $att_handle = $self->_get_attribute($name);';

# use Data::Dumper;            # Dumper
# use List::Util;              # first max maxstr min minstr reduce shuffle sum
# use List::MoreUtils;         # "the stuff missing in List::Util"
# use Log::Log4perl qw(:easy); # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
# Log::Log4perl->easy_init( $DEBUG );

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
    bless $self, $class;
    return $self;
}

sub get_subgraphs {
    my ( $self, $word ) = @_;
    my $s_handle      = $self->_get_attribute("s");
    my $indep_handle  = $self->_get_attribute("indep");
    my $outdep_handle = $self->_get_attribute("outdep");
    $self->{"cqp"}->exec( sprintf "A = [word = \"%s\" %%c]", $word );
    my @matches = $self->{"cqp"}->exec("tabulate A match");
SENTENCE:
    foreach my $match (@matches) {
        my ( $start, $end ) = $s_handle->cpos2struc2cpos($match);
        my @indeps  = $indep_handle->cpos2str( $start .. $end );
        my @outdeps = $outdep_handle->cpos2str( $start .. $end );
        my %relation;
        foreach my $i ( 0 .. $#outdeps ) {
            $indeps[$i]  =~ s/^[|]//xms;
            $indeps[$i]  =~ s/[|]$//xms;
            $outdeps[$i] =~ s/^[|]//xms;
            $outdeps[$i] =~ s/[|]$//xms;
            my @out = split /[|]/xms, $outdeps[$i];
            next SENTENCE if ( scalar( () = split /[|]/xms, $indeps[$i], $UNLIMITED_NUMBER_OF_FIELDS ) + scalar @out > $MAXIMUM_NUMBER_OF_RELATIONS );
            my $cpos = $start + $i;
            foreach my $dep (@out) {
                $dep =~ m/^ (?<relation>[^(]+)[(]0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/xms;
                my $target = $cpos + $LAST_PAREN_MATCH{"offset"};
                $relation{$cpos}->{$target} = $LAST_PAREN_MATCH{"relation"};

                #$raw_graph->add_edge( $cpos, $target );
            }
        }
    }
    return;
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
    $get_subgraphs->get_subgraphs("test");
    return;
}

1;
