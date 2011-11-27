#!/usr/bin/perl

# Add dependencies from a separate file

use warnings;
use strict;

use XML::LibXML;

die("Usage: add_dependencies.pl file dependencies\n") unless ( @ARGV == 2 );
my $file    = shift(@ARGV);
my $depfile = shift(@ARGV);
die("Something is wrong with file '$file'\n") unless ( -e $file and -r _ );

my $ignored = 0;

open( my $deph, "<", $depfile )
    or die("Cannot open dependencies file $depfile: $!");
my $dom = XML::LibXML->load_xml( location => $file );
foreach my $s ( $dom->getElementsByTagName("s") ) {
    my @sent;

    # read dependencies
    my @indeps;
    my @outdeps;
    while ( defined( my $depline = <$deph> ) ) {
        last if ( $depline =~ m/^\s*$/ );
        die("Does not match: $depline\n") unless ( $depline =~ m/^([^()]+)\((.+?)-(\d+)('*)?, (.+?)-(\d+)('*)\)$/ );
        my ( $rel, $reg, $regidx, $regcopy, $dep, $depidx, $depcopy ) = ( $1, $2, $3, $4, $5, $6, $7 );
        if ( $regidx != $depidx or $regcopy ne $depcopy ) {
            push( @{ $indeps[$depidx] }, [ $rel, $reg, $regidx, $regcopy, $dep, $depidx, $depcopy ] );
            push( @{ $outdeps[$regidx] }, [ $rel, $reg, $regidx, $regcopy, $dep, $depidx, $depcopy ] );
        }
        else {
            print STDERR "ignore $depline";
            $ignored++;
        }
    }
    my $slen    = $s->getAttribute("len");
    my $counter = 0;
    foreach my $phrase ( $s->childNodes() ) {
        my $name = $phrase->nodeName();
        next if ( substr( $name, 0, 1 ) eq "#" );
        foreach my $head_or_text ( $phrase->childNodes() ) {
            my $lname = $head_or_text->nodeName();
            my $text  = $head_or_text->textContent;
            next if ( $text eq "\n" );
            chomp($text);
            $text =~ s/^\n//;
            my @lines = split( /\n/, $text );
            for my $line (@lines) {
                for my $deps ( \@indeps, \@outdeps ) {
                    $line .= "\t|" . join( "|", map( $_->[0] . "(" . ( $_->[2] - ( $counter + 1 ) ) . $_->[3] . "," . ( $_->[5] - ( $counter + 1 ) ) . $_->[6] . ")", @{ $deps->[ $counter + 1 ] } ) );
                    $line .= "|" if ( @{ $deps->[ $counter + 1 ] } );
                }
                $counter++;
            }
            $text = "\n" . join( "\n", @lines ) . "\n";
            my $newnode = XML::LibXML::Text->new($text);
            if ( $lname eq "h" ) {
                $head_or_text->replaceChild( $newnode, $head_or_text->firstChild() );
            }
            elsif ( $lname eq "#text" ) {
                $head_or_text->replaceNode($newnode);
            }
            else {
                die("Unknown name: $name\n");
            }
        }
    }
    die("$slen != $counter\n") unless ( $slen == $counter );
}

print $dom->toString(0);
close($deph) or die("Cannot close dependencies file  $depfile: $!");
print STDERR "$ignored dependency relations ignored\n";
