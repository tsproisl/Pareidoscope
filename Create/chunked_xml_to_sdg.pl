#!/usr/bin/perl

#################
package sentence;
#################

use warnings;
use strict;

sub new {
    my $class = shift;
    my $self  = {
        "id"        => "",
        "tokens"    => [],
        "deptokens" => {}
    };
    bless( $self, $class );
    return $self;
}

1;

##############
package token;
##############

use warnings;
use strict;

sub new {
    my $class = shift;
    my $self  = {
        "wordform" => "",
        "pos"      => "",
        "lemma"    => "",
        "wc"       => "",
        "deps"     => undef,
        "chunk"    => ""
    };
    bless( $self, $class );
    return $self;
}

1;

#############
package main;
#############

use warnings;
use strict;

use Storable;

my $outfield  = "wc";
my %structure = (
    "wordform" => 0,
    "pos"      => 1,
    "lemma"    => 2,
    "wc"       => 3,
    "deps"     => 4,
);

my $filename = shift(@ARGV);
die("Bad filename: $filename\n") unless ( -r $filename );
open( my $fh, "<", $filename ) or die("Cannot open $filename: $!");

my %deps;
my @deps;
my %annotation;
my @annotation;
my $sentences;
while (<$fh>) {
    chomp;
    $sentences++ if ( substr( $_, 0, 3 ) eq "<s " );
    if ( substr( $_, 0, 1 ) ne "<" ) {
        my @line = split(/\t/);
        $annotation{ $line[ $structure{$outfield} ] }++;
        my $deps = $line[ $structure{"deps"} ];
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
$deps{ $deps[$_] } = $_ foreach ( 0 .. $#deps );
@annotation = sort keys %annotation;
$annotation{ $annotation[$_] } = $_ foreach ( 0 .. $#annotation );


print $sentences, "\n";

seek( $fh, 0, 0 );
my $open;
my $s;
my $scounter;
while (<$fh>) {
    chomp;
    next if ( substr( $_, 0, 5 ) eq "<?xml" );
    if ( substr( $_, 0, 3 ) eq "<s " ) {
        $s = new sentence;
	$scounter++;
        next;
    }
    next if ( $_ eq "<h>" or $_ eq "</h>" or $_ eq "<corpus>" or $_ eq "</corpus>" );
    if ( $_ eq "</s>" ) {
	print $scounter, "\n";
        for ( my $i = 0; $i <= $#{ $s->{"tokens"} }; $i++ ) {
            my $deps = $s->{"tokens"}->[$i]->{"deps"};
            $deps =~ s/^\|//;
            foreach my $dep ( split( /\|/, $deps ) ) {
                next if ( $dep eq "" );
                $dep =~ m/^([^(]+)\((-?\d+)('*), (-?\d+)('*)\)$/;
                my ( $rel, $gov, $gcopy, $dep, $dcopy ) = ( $1, $2, $3, $4, $5 );
		unless ( $s->{"deptokens"}->{ ( $i + $gov ) . $gcopy } ) {
                    $s->{"deptokens"}->{ ( $i + $gov ) . $gcopy } = Storable::dclone( $s->{"tokens"}->[ $i + $gov ] );
                    $s->{"deptokens"}->{ ( $i + $gov ) . $gcopy }->{"deps"} = {};
                }
		$s->{"deptokens"}->{ ( $i + $gov ) . $gcopy }->{"deps"}->{"$i$dcopy"} = $deps{$rel};
                unless ( $s->{"deptokens"}->{"$i$dcopy"} ) {
                    $s->{"deptokens"}->{"$i$dcopy"} = Storable::dclone( $s->{"tokens"}->[$i] );
                    $s->{"deptokens"}->{"$i$dcopy"}->{"deps"} = {};
                }
            }
        }
        foreach my $row ( sort keys %{ $s->{"deptokens"} } ) {
            my @line;
            foreach my $col ( sort keys %{ $s->{"deptokens"} } ) {
                if ( $row eq $col ) {
                    push( @line, $annotation{$s->{"deptokens"}->{$row}->{$outfield}} );
                }
                elsif ( $s->{"deptokens"}->{$row}->{"deps"}->{$col} ) {
                    push( @line, $s->{"deptokens"}->{$row}->{"deps"}->{$col} );
                }
                else {
                    push( @line, "-" );
                }
            }
	    print join(" ", @line), "\n";
        }
	print "#\n";
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
        die("Huh: $_\n") unless ( @fields == keys %structure );
        my $t = new token;
        foreach ( keys %structure ) {
            $t->{$_} = $fields[ $structure{$_} ];
        }
        $t->{"chunk"} = $open;
        push( @{ $s->{"tokens"} }, $t );
    }
}

close($fh) or die("Cannot close $filename: $!");

1;
