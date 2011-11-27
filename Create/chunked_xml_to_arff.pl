#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;

my $filename = shift(@ARGV);
die("Bad filename: $filename\n") unless ( -r $filename );
open( my $fh, "<", $filename ) or die("Cannot open $filename: $!");

my %deps;
my @deps;
my %wfs;
while (<$fh>) {
    chomp;
    if ( substr( $_, 0, 1 ) ne "<" ) {
        my $wordform = ( split(/\t/) )[0];
        $wfs{$wordform}++;
        my $deps = ( split(/\t/) )[4];
        $deps =~ s/^|//;
        foreach my $dep ( split( /\|/, $deps ) ) {
            next if ( $dep eq "" );
	    $dep =~ s/['.]/-/g;
            $dep =~ m/^([^(]+)\(/;
            $deps{$1}++;
        }
    }
}
@deps = sort keys %deps;

print "\@relation anc_masc\n\n";

print "\@attribute wordform { " . join(", ", map {s/'/\\'/g;"'$_'"} sort keys %wfs) . " }\n";
#print "\@attribute wordform string\n";
foreach (@deps) {
    print "\@attribute in_$_ { yes, no }\n";
}
foreach (@deps) {
    print "\@attribute out_$_ { yes, no }\n";
}
print "\n\@data\n";

seek( $fh, 0, 0 );
my $open;
my @s;
while (<$fh>) {
    chomp;
    next if ( substr( $_, 0, 5 ) eq "<?xml" );
    if ( substr( $_, 0, 3 ) eq "<s " ) {
        undef(@s);
        next;
    }
    next if ( $_ eq "<h>" or $_ eq "</h>" or $_ eq "<corpus>" or $_ eq "</corpus>" );
    if ( $_ eq "</s>" ) {

        # @out = ([wordform, [[{in-deps}, {out-deps}], [...]]])
        my @out;
        for ( my $i = 0; $i <= $#s; $i++ ) {
            $out[$i]->[0] = $s[$i]->[0];
            my $deps = $s[$i]->[4];
            $deps =~ s/^\|//;
            foreach my $dep ( split( /\|/, $deps ) ) {
                next if ( $dep eq "" );
                $dep =~ m/^([^(]+)\((-?\d+)('*), (-?\d+)('*)\)$/;
                my ( $rel, $gov, $gcopy, $dep, $dcopy ) = ( $1, $2, $3, $4, $5 );
                $gcopy                                        = length($gcopy);
                $dcopy                                        = length($dcopy);
                $out[$i]->[1]->[$dcopy]->[0]->{$rel}          = 1;
                $out[ $i + $gov ]->[1]->[$gcopy]->[1]->{$rel} = 1;
            }
        }
        foreach my $out (@out) {
            foreach my $copy ( @{ $out->[1] } ) {
		my $outstring = $out->[0];
		$outstring =~ s/'/\\'/g;
                print "'$outstring',";
                print join( ",", map( $copy->[0]->{$_} ? "yes" : "?", @deps ) ) . ",";
                print join( ",", map( $copy->[1]->{$_} ? "yes" : "?", @deps ) );
                print "\n";
            }
        }
        next;
    }

    # opening
    if (m{^<(?!/)([^>]+)>$}) {
        die("Illegal structure\.") if ($open);
        $open = $1;
    }

    # closing
    if (m{^</([^>]+)>$}) {
        die("Illegal structure\.") unless ($open);
        undef($open);
    }
    if ( substr( $_, 0, 1 ) ne "<" ) {
        my @fields = split(/\t/);
        die("Huh: $_\n") unless ( @fields == 5 );
        push( @fields, $open );
        push( @s,      \@fields );
    }
}

close($fh) or die("Cannot close $filename: $!");
