#!/usr/bin/perl
package Collector::Subgraph;

use 5.010;

use strict;
use warnings;
use open qw(:utf8 :std);
use utf8;

use CWB;
use CWB::CL;
use CWB::CQP;

# use version; our $VERSION = qv('0.0.1');
use Carp;    # carp croak

# use Data::Dumper;            # Dumper
# use List::Util;              # first max maxstr min minstr reduce shuffle sum
# use List::MoreUtils;         # "the stuff missing in List::Util"
# use Log::Log4perl qw(:easy); # TRACE DEBUG INFO WARN ERROR FATAL ALWAYS
# Log::Log4perl->easy_init( $DEBUG );

sub connect_to_corpus {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = {};
    $self->{"cqp"} = new CWB::CQP;
    croak("Can't start CQP backend.") unless ( defined $self->{"cqp"} );
    $self->{"cqp"}->exec("set Registry '../Pareidoscope/corpora/registry'");
    $self->{"cqp"}->exec("OANC");
    $CWB::CL::Registry = '../Pareidoscope/corpora/registry';
    $self->{"corpus_handle"} = new CWB::CL::Corpus "OANC";
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
            $indeps[$i]  =~ s/^\|//;
            $indeps[$i]  =~ s/\|$//;
            $outdeps[$i] =~ s/^\|//;
            $outdeps[$i] =~ s/\|$//;
            my @out = split /\|/, $outdeps[$i];
            next SENTENCE if ( scalar( () = split( /\|/, $indeps[$i], -1 ) ) + scalar @out > 10 );
            my $cpos = $start + $i;
            foreach my $dep (@out) {
                $dep =~ m/^(?<relation>[^(]+)\(0(?:&apos;)*,(?<offset>-?\d+)(?:&apos;)*/;
                my $target = $cpos + $+{"offset"};
                $relation{$cpos}->{$target} = $+{"relation"};

                #$raw_graph->add_edge( $cpos, $target );
            }
        }
    }
}

sub _get_attribute {
    croak('Usage:  $att_handle = $config->get_attribute($name);') unless ( scalar(@_) == 2 );
    my ( $self, $name ) = @_;

    # retrieve attribute handle from cache
    return $self->{"attributes"}->{$name} if ( exists( $self->{"attributes"}->{$name} ) );

    # try p-attribute first ...
    my $att = $self->{"corpus_handle"}->attribute( $name, "p" );

    # ... then try s-attribute
    $att = $self->{"corpus_handle"}->attribute( $name, "s" ) unless ( defined($att) );

    # ... finally try a-attribute
    $att = $self->{"corpus_handle"}->attribute( $name, "a" ) unless ( defined($att) );
    croak "Can't open attribute " . $self->{"corpus"} . ".$name, sorry." unless ( defined($att) );

    # store attribute handle in cache
    $self->{"attributes"}->{$name} = $att;
    return $att;
}

sub DESTROY {
    my ($self) = @_;
    undef $self->{"cqp"};
    undef $self->{"corpus_handle"};
}

__PACKAGE__->run(@ARGV) unless caller;

sub run {
    my ( $class, @args ) = @_;
    my $get_subgraphs = &connect_to_corpus($class);
    $get_subgraphs->get_subgraphs("test");
}

1;
