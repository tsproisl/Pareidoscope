#!/usr/bin/perl

use Dancer;
use IO::Socket;
use threads;
use threads::shared;

get "/" => sub {
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => 4878,

        #LocalPort => $local_port,
        Proto     => "tcp",
        ReuseAddr => 1,
        Timeout   => 5,
        Type      => SOCK_STREAM
    ) or die("Couldn't be a tcp client on port 4878 : $@");

    my @queue :shared;
    my $flag :shared;
    $flag = 1;

    my $writer = threads->create( \&writer, $socket, \$flag, \@queue );
    my $reader = threads->create( \&reader, $socket );

    foreach (1 .. 5) {
	push(@queue, "string$_");
	print STDERR "push $_\n";
	sleep(1);
    }
    $flag = 0;

    $writer->join();
    $reader->join();
};

sub writer {
    my $socket = shift;
    my $flag = shift;
    my $queue = shift;
    print $socket "test\n";
    while ($$flag or @$queue) {
	if (@$queue) {
	    print $socket shift(@$queue) . "\n";
	}
    }
    print STDERR "writer done\n";
}

sub reader {
    my $socket = shift;
    foreach (1 .. 6) {
	my $line = <$socket>;
	print STDERR "err: $line";
	print $line;
    }
    print STDERR "reader done\n";
}

dance;
