#!/usr/bin/perl

use warnings;
use strict;

use IO::Socket;
use Time::HiRes;

die("I need two arguments: host, port") unless(scalar(@ARGV) == 2);
my ($remote_host, $remote_port) = @ARGV;

#print "one\n";
my $socket = IO::Socket::INET->new(PeerAddr  => $remote_host,
				   PeerPort  => $remote_port,
				   #LocalPort => $local_port,
				   Proto     => "tcp",
				   ReuseAddr => 1,
				   Timeout   => 5,
				   Type      => SOCK_STREAM)
    or die "Couldn't connect to $remote_host:$remote_port : $@\n";

#print "two\n";
my $now = Time::HiRes::time;
print $socket "chkpng:$now\n";
#print "three\n";
chomp(my $then = <$socket>);
printf("%.3f\n", (Time::HiRes::time - $now) * 1000);

