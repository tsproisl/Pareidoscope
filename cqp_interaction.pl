#!/usr/bin/perl

use warnings;
use strict;

use Encode;
use CWB::CQP;
use entities;

binmode(STDOUT, "utf8");

my $cqp = new CWB::CQP("-r /localhome/Databases/CWB/registry");
$cqp->set_error_handler('die'); # built-in, useful for one-off scripts
$cqp->exec("TESTCORP;");
$cqp->exec("set Context s;");
$cqp->exec("set Timing on;");

while(defined(my $line = <STDIN>)){
    chomp($line);
    $line = Encode::decode("utf8", $line);
    $line = entities::encode_entities($line);
    $line = Encode::encode("iso-8859-1", $line);
    $cqp->begin_query;
    $cqp->exec("Result = $line");
    print $cqp->status, "\n";
    $cqp->end_query;
    #my @lines = $cqp->exec("cat;");
    my @lines = $cqp->exec("size Result;");
    foreach my $res (@lines){
	$res = Encode::decode("iso-8859-1", $res);
	$res = entities::decode_entities($res);
	print $res, "\n";
    }
}

# close down CQP server (exits gracefully)
undef $cqp;
