#!/usr/bin/perl

use warnings;
use strict;

use IO::Socket;
use threads;

my $server = IO::Socket::INET->new(
    LocalPort => 4878,
    Type      => SOCK_STREAM,
    ReuseAddr => 1,
    Listen    => 10
) or die("Couldn't be a tcp server on port 4878 : $@");

while ( my $client = $server->accept ) {

    # $client is the new connection
    #print "connection!\n";
    #async(\&handle_connection, $client)->detach;
    my $thread = threads->create( \&handle_connection, $client )->detach;
}

sub handle_connection {
    my $socket = shift;
    my $output = shift || $socket;
    while (<$socket>) {
	print;
	print $output $_;
    }
}
