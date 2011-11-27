package cqi_oo;

use warnings;
use strict;

use CGI::Carp qw(fatalsToBrowser);

#use lib "/srv/www/homepages/tsproisl/pareidoscope/local/lib/perl/5.10.1";
use lib "/srv/www/homepages/tsproisl/pareidoscope/local/share/perl/5.10.1";

use CWB::CQI;
use CWB::CQI::Client;

use Data::Dumper;

sub init{
    my $invocant = shift;
    my ($user, $password, $host, $port) = @_;
    my $class = ref($invocant) || $invocant;
    cqi_connect($user, $password, $host, $port);
    my %corpora = map {$_ => 1} cqi_list_corpora();
    my $self = {"user" => $user,
		"password" => $password,
		"host" => $host,
		"port" => $port,
		"corpora" => \%corpora,
		"subcorpora" => {}
    };
    bless($self, $class);
    return $self;
}

sub fini{
    my ($self) = @_;
    foreach my $subcorpus (keys %{$self->{"subcorpora"}}){
	cqi_drop_subcorpus($subcorpus);
    }
    cqi_bye();
    $self->{"subcorpora"} = {};
    $self->{"corpora"} = {};
}

sub oo_cqi_query{
    my ($self, $corpus, $query) = @_;
    my $subcorpus = "S" . sprintf("%x", time . int(rand() * 1000000));
    #print "<pre>corpus: $corpus, subcorpus: $subcorpus, query: $query\n</pre>\n";
    #print "<pre>" . Dumper($self) . "</pre>\n";
    my $status = cqi_query($corpus, $subcorpus, $query);
    if($status != $CWB::CQI::STATUS_OK) {
      croak("failed [$CWB::CQI::CommandName{$status}]\n");
      return;
    }
    $self->{"subcorpora"}->{"$corpus:$subcorpus"}++;
    return $subcorpus;
}

sub oo_subcorpus_size{
    my ($self, $subcorpus) = @_;
    return cqi_subcorpus_size($subcorpus);
}

sub oo_cqi_dump_subcorpus{
    my ($self, $subcorpus, $size) = @_;
    #my @match = cqi_dump_subcorpus($subcorpus, $CWB::CQI::CONST_FIELD_MATCH, 0, $size - 1);
    my @match = cqi_dump_subcorpus($subcorpus, 'match', 0, $size - 1);
    #my @matchend = cqi_dump_subcorpus($subcorpus, $CWB::CQI::CONST_FIELD_MATCHEND, 0, $size - 1);
    my @matchend = cqi_dump_subcorpus($subcorpus, 'matchend', 0, $size - 1);
    return (\@match, \@matchend);
}

sub oo_cqi_cpos2struc{
    my ($self, $attribute, @cpos) = @_;
    return cqi_cpos2struc($attribute, @cpos);
}

sub oo_cqi_struc2cpos{
    my ($self, $attribute, @cpos) = @_;
    return cqi_struc2cpos($attribute, @cpos);
}

sub oo_cqi_cpos2str{
    my ($self, $attribute, @cpos) = @_;
    #print "<pre>attribute: $attribute\n" . Dumper(\@cpos) . "</pre>\n";
    return cqi_cpos2str($attribute, @cpos);
}

1;
