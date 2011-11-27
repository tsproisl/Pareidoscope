#!/usr/bin/perl

use warnings;
use strict;
use open qw(:std :utf8);

use Data::Dumper;

print '<?xml version="1.0" encoding="UTF-8" ?>', "\n";
print "<corpus>\n";
{
    my $sid;
    my $s;
    while(<>){
	chomp;
	if(/^\s*$/){
	    $sid++;
	    print "<s id='$sid' len='" . scalar(@$s) . "'>\n";
	    &proc_s($s);
	    print "</s>\n";
	    $s = [];
	}else{
	    push(@$s, [split(/\t/)]);
	}
    }
}
print "</corpus>\n";

sub proc_s {
    my $s = shift;
    my $open_chunk;
    foreach my $tok (@$s){
	if($tok->[2] =~ m/^B-(.+)$/){
	    print "</$open_chunk>\n" if(defined($open_chunk));
	    $open_chunk = lc($1);
	    print "<$open_chunk>\n";
	}
	elsif($tok->[2] eq "O"){
	    print "</$open_chunk>\n" if(defined($open_chunk));
	    $open_chunk = "o";
	    print "<$open_chunk>\n";
	}
	print "<h>\n" if($tok->[3] ne "NOFUNC");
	print &escape(join("\t", @{$tok}[0,1]) . "\n");
	print "</h>\n" if($tok->[3] ne "NOFUNC");
    }
    print "</$open_chunk>\n" if(defined($open_chunk));
}

sub escape{
    my $arg = shift;
    $arg =~ s/&/&amp;/g;
    $arg =~ s/</&lt;/g;
    $arg =~ s/>/&gt;/g;
    $arg =~ s/'/&apos;/g;
    $arg =~ s/"/&quot;/g;
    return $arg;
}
