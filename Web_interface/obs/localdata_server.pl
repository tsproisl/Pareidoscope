#!/usr/bin/perl

package localdata;

use warnings;
use strict;

use Fcntl ':flock';
use Storable;
use POSIX qw();
use Data::Dumper;
use MIME::Base64 qw();

sub init{
    my $invocant = shift;
    my ($dir, $c5) = @_;
    my $class = ref($invocant) || $invocant;
    my @ngds;
    my @ngramidxs;
    for my $i (1 .. 9){
	open($ngds[$i], "<:raw", "$dir/ngrams" . sprintf("%02d", $i) . ".dat") or die("Cannot open file '$dir/ngrams" . sprintf("%02d", $i) . ".dat': $!");
	$ngramidxs[$i] = Storable::retrieve("$dir/ngrams" . sprintf("%02d", $i) . ".idx");
    }
    my $self = {"tags" => $c5,
		"NGDs" => \@ngds,
		"records" => [],
		"firstrecords" => [],
		"lastrecords" => [],
		"ngramidxs" => \@ngramidxs
    };
    bless($self, $class);
    return $self;
}


sub fini{
    my ($self) = @_;
    for my $i (1 .. 9){
	close($self->{"NGDs"}->[$i]) or die("Cannot close file: $!");
    }
}


sub get_ngram_freq{
    my ($self, $ngram) = @_;
    my $length = length($ngram);
    return $self->scan_cached_records($ngram) if($self->{"records"}->[$length] and $self->{"firstrecords"}->[$length] le $ngram and $self->{"lastrecords"}->[$length] ge $ngram);
    my $max = scalar(@{$self->{"ngramidxs"}->[$length]}) / 2 - 1;
    my $maxindex = $max;
    my $minindex = 0;
    my $success = -1;
    my $recordsize;
    while($success < 0 and $minindex <= $maxindex){
	my $middle = POSIX::floor($minindex + (($maxindex - $minindex) / 2));
	if($ngram lt $self->{"ngramidxs"}->[$length]->[$middle * 2]){
	    $maxindex = $middle - 1;
	    next;
	}
	if($middle == $max){
	    $success = $self->{"ngramidxs"}->[$length]->[($middle * 2) + 1];
	    flock($self->{"NGDs"}->[$length], LOCK_EX);
	    seek($self->{"NGDs"}->[$length], 0, 2) or die("Error while seeking index file");
	    $recordsize = tell($self->{"NGDs"}->[$length]) - $success;
	    flock($self->{"NGDs"}->[$length], LOCK_UN);
	    next;
	}
	if($ngram ge $self->{"ngramidxs"}->[$length]->[($middle + 1) * 2]){
	    $minindex = $middle + 1;
	    next;
	}
	$success = $self->{"ngramidxs"}->[$length]->[($middle * 2) + 1];
	$recordsize = $self->{"ngramidxs"}->[$length]->[(($middle + 1) * 2) + 1] - $success;
    }
    die("N-gram not found: " . join(" ", unpack("C*", $ngram)) . "\n") if($success < 0);
    my $record;
    flock($self->{"NGDs"}->[$length], LOCK_EX);
    seek($self->{"NGDs"}->[$length], $success, 0) or die("Error while seeking index file");
    my $chrs = read($self->{"NGDs"}->[$length], $record, $recordsize);
    flock($self->{"NGDs"}->[$length], LOCK_UN);
    $self->{"records"}->[$length] = $record;
    ($self->{"firstrecords"}->[$length]) = substr($self->{"records"}->[$length], 0, $length);
    ($self->{"lastrecords"}->[$length]) = substr($self->{"records"}->[$length], -($length + 4), $length);
    die("Error while processing n-grams: " . join(" ", grep($_ > 0, unpack("C*", $self->{"firstrecords"}->[$length]))) . " > " . join(" ", grep($_ > 0, unpack("C*", $ngram)))) unless($self->{"firstrecords"}->[$length] le $ngram);
    die("Error while processing n-grams: " . join(" ", grep($_ > 0, unpack("C*", $self->{"lastrecords"}->[$length]))) . " < " . join(" ", grep($_ > 0, unpack("C*", $ngram)))) unless($self->{"lastrecords"}->[$length] ge $ngram);
    return $self->scan_cached_records($ngram);
}


sub scan_cached_records{
    my ($self, $ngram) = @_;
    my $length = length($ngram);
    my $maxindex = length($self->{"records"}->[$length]) / ($length + 4) - 1;
    my $minindex = 0;
    my $success = -1;
    while($success < 0 and $minindex <= $maxindex){
        my $middle = POSIX::floor($minindex + (($maxindex - $minindex) / 2));
        my $start = $middle * ($length + 4);
        my $record = substr($self->{"records"}->[$length], $start, $length);
        if($ngram eq $record){
            $success = unpack("L", substr($self->{"records"}->[$length], $start + $length, 4));
            return ($success);
        }elsif($ngram lt $record){
            $maxindex = $middle - 1;
        }else{
            $minindex = $middle + 1;
        }
    }
    die("Error while reading n-grams") if($success < 0);
}


1;

package main;

#!/usr/bin/perl

use warnings;
use strict;

use threads;
use IO::Socket;
use statistics;

my $server_port = shift(@ARGV);
$server_port = 4878 unless(defined($server_port) and sprintf("%d", $server_port) eq $server_port);

my $server = IO::Socket::INET->new(LocalPort => $server_port,
                                   Type      => SOCK_STREAM,
                                   ReuseAddr => 1,
                                   Listen    => 10)
    or die("Couldn't be a tcp server on port $server_port : $@");

print "Waiting for clients on port #$server_port.\n";
while (my $client = $server->accept){
    # $client is the new connection
    #print "connection!\n";
    #async(\&handle_connection, $client)->detach;
    my $thread = threads->create(\&handle_connection, $client)->detach;
}

close($server);


sub handle_connection {
    my $socket = shift;
    my $output = shift || $socket;
    my $exit = 0;
    chomp(my $first = <$socket>);
    if(substr($first, 0, 7) eq "chkpng:"){
	print $output substr($first, 7), "\n";
	return;
    }elsif(substr($first, 0, 4) ne "dir:"){
	print $output "Wrong protocol: $first\n";
	return;
    }
    my $dir = substr($first, 4);
    chomp(my $c5 = <$socket>);
    $c5 = eval $c5;
    my $localdata = localdata->init($dir, $c5);
    my $lastngram = "";
    my $lastc1 = 0;
    while (my $input = <$socket>) {
	#print $input;
	chomp($input);
	if($input =~ s/^gngf:(\d+):(\d+):,//){
	    my $r1 = $1;
	    my $n = $2;
	    my @outstring;
	    foreach my $pair (split(/,/, $input)){
		my ($ngram, $o11) = split(/:/, $pair);
		my $c1;
		if($ngram eq $lastngram){
		    $c1 = $lastc1;
		}else{
		    my $packed_ngram = MIME::Base64::decode($ngram);
		    $c1 = $localdata->get_ngram_freq($packed_ngram);
		    $lastngram = $ngram;
		    $lastc1 = $c1;
		}
		my $g2 = &statistics::g($o11, $r1, $c1, $n);
		push(@outstring, "$c1,$g2");
	    }
	    my $outstr = join(",", @outstring) . "\n";
	    print $output $outstr;
	}elsif($input eq "fini"){
	    $localdata->fini();
	    $exit = 1;
	}else{
	    #$exit = 1;
	}
        last if $exit;
    }
    #shutdown($socket, 2);
    #shutdown($output, 2);
}

