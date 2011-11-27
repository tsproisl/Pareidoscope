package common_functions;

use warnings;
use strict;

sub log{
    my ($string, $level, $maxloglevel) = @_;
    my ($sec, $min, $hour) = (localtime)[0..2];
    my $time = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    open(LOG, ">>logfile.txt") or die("Cannot open logfile: $!");
    print "[$time] $string\n" if($level <= $maxloglevel);
    print LOG "[$time] $string\n" if($level <= $maxloglevel);
    close(LOG) or die("Cannot close logfile: $!");
}

1;
