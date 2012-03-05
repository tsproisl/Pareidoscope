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
use Carp;                    # carp croak
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
    $self->{"cqp"}->exec( "set Registry '../Pareidoscope/corpora/registry'" );
    $CWB::CL::Registry = '../Pareidoscope/corpora/registry';
    $self->{"corpus_handle"} = new CWB::CL::Corpus "OANC";
    croak "Error: can't open corpus OANC, aborted." unless ( defined $self->{"corpus_handle"} );
    bless $self, $class;
    return $self;
}

sub get_subgraphs {
    my ($self) = @_;
    
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
}

1;
