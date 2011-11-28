#!/usr/bin/perl

use warnings;
use strict;

use XML::LibXML;
use chunklink_2_2_2000_for_conll_tsproisl;

use Data::Dumper;

my $infile = shift(@ARGV);
my $counter;

open( my $in,  "<:encoding(utf8)", $infile )          or die("Cannot open file $infile: $!");
open( my $out, ">:encoding(utf8)", $infile . ".out" ) or die("Cannot open file $infile.out: $!");

OUTER: while ( my $line = <$in> ) {
    if ( $line =~ /^<\/?(corpus|text)[> ]/ ) {
        print $out $line;
        next;
    }
    if ( $line =~ /^<sentence / ) {
        $line =~ s/^<sentence /<s /;
        my @wordstagslemmata;
        my @pstree;
        my @dependencies;
        while ( my $sline = <$in> ) {
            if ( $sline eq "</sentence>\n" ) {
                my @chunker_output = split( /\n/, chunk( join( " ", @pstree ) ) );
                die("Strange phrase structure tree") if ( scalar(@chunker_output) != scalar(@wordstagslemmata) );
                my $len = @chunker_output;
                $line =~ s/>\n/ len="$len">\n/;
                @chunker_output = map { [ ( split(/\s+/), $_ )[ 6, 5, 4, 7 ] ] } @chunker_output;
                for ( my $i = 0; $i <= $#chunker_output; $i++ ) {
                    die( "Token mismatch: " . $chunker_output[$i]->[0] . "/" . substr( $wordstagslemmata[$i], 0, length( $chunker_output[$i]->[0] ) ) ) unless ( $chunker_output[$i]->[0] eq substr( $wordstagslemmata[$i], 0, length( $chunker_output[$i]->[0] ) ) );
                }
                &proc_s( \@chunker_output, \@wordstagslemmata );
		#print Dumper(\@chunker_output);
                my $sentence = &add_heads( $line . join( "", @wordstagslemmata ) . "</s>\n" );
		$sentence = &add_dependencies($sentence, \@dependencies);
                print $out $sentence;
                $counter++;
                #last OUTER if ( $counter >= 50 );
                last;
            }
            elsif ( $sline eq "<wordstagslemmata>\n" ) {
                while ( my $wline = <$in> ) {
                    last if ( $wline eq "</wordstagslemmata>\n" );

                    #chomp($wline);
                    push( @wordstagslemmata, $wline );
                }
            }
            elsif ( $sline eq "<pstree>\n" ) {
                while ( my $pline = <$in> ) {
                    last if ( $pline eq "</pstree>\n" );
                    chomp($pline);
                    push( @pstree, $pline );
                    next OUTER if ( join( " ", @pstree ) eq "X" );
                }
            }
            elsif ( $sline eq "<dependencies>\n" ) {
                while ( my $dline = <$in> ) {
                    last if ( $dline eq "</dependencies>\n" );
                    chomp($dline);
                    push( @dependencies, $dline );
                }
            }
        }
    }
}

close($in)  or die("Cannot close file $infile: $!");
close($out) or die("Cannot close file $infile.out: $!");

sub proc_s {
    my ( $s, $o ) = @_;
    my $open_chunk;
    for ( my $i = 0; $i <= $#$s; $i++ ) {
        my $tok = $s->[$i];
        my $pre = "";
        if ( $tok->[2] =~ m/^B-(.+)$/ ) {
            $pre = "</$open_chunk>\n" if ( defined($open_chunk) );
            $open_chunk = lc($1);
            $pre .= "<$open_chunk>\n";
        }
        elsif ( $tok->[2] eq "O" ) {
            $pre = "</$open_chunk>\n" if ( defined($open_chunk) );
            $open_chunk = "o";
            $pre .= "<$open_chunk>\n";
        }
        $pre .= "<h>\n" if ( $tok->[3] ne "NOFUNC" );
        $o->[$i] = $pre . $o->[$i] if ( defined($open_chunk) );
        $o->[$i] .= "</h>\n" if ( $tok->[3] ne "NOFUNC" );
    }
    $o->[$#$o] .= "</$open_chunk>\n" if ( defined($open_chunk) );
}

sub add_heads {
    my $sentence = shift;
    #print $sentence, "\n";
    my $dom = XML::LibXML->load_xml( string => $sentence );
    foreach my $s ( $dom->getElementsByTagName("s") ) {
        foreach my $phrase ( $s->childNodes() ) {
            my $name = $phrase->nodeName();
            next if ( substr( $name, 0, 1 ) eq "#" );
            my @h = $phrase->getChildrenByTagName("h");
            if ( @h == 0 ) {
                my @children = $phrase->childNodes();
                die("Too many or too few children\n") unless ( @children == 1 );
                my $text = $phrase->textContent;
                $phrase->removeChild( $children[0] );
                chomp($text);
                $text =~ s/^\n//;
                my @text = split( /\n/, $text );
                my $newhead = XML::LibXML::Element->new("h");

                if ( @text > 1 ) {
                    $newhead->appendTextNode( "\n" . $text[$#text] . "\n" );
                    my $oldtext = join( "\n", @text[ 0 .. $#text - 1 ] );
                    $oldtext = "\n" . $oldtext . "\n";
                    $phrase->appendChild( XML::LibXML::Text->new($oldtext) );
                    $phrase->appendChild($newhead);
                    $phrase->appendChild( XML::LibXML::Text->new("\n") );
                }
                elsif ( @text < 1 ) {
                    die("Not enough text in node\n");
                }
                else {
                    $newhead->appendTextNode( "\n" . $text[0] . "\n" );
                    $phrase->appendChild( XML::LibXML::Text->new("\n") );
                    $phrase->appendChild($newhead);
                    $phrase->appendChild( XML::LibXML::Text->new("\n") );
                }
            }
            elsif ( @h > 1 ) {

                # 1 head is okay
                die("Strange phrase: more than one head! " . $s->getAttribute("id"));
            }
        }
    }
    return $dom->toString(0);
}

sub add_dependencies {
    my $sentence = shift;
    my $deps = shift;
    my $dom = XML::LibXML->load_xml( string => $sentence );
    foreach my $s ( $dom->getElementsByTagName("s") ) {
        my @sent;
	my $root = 0;
	
        # read dependencies
        my @indeps;
        my @outdeps;
	foreach my $depline (@$deps) {
	    next if($depline =~ /^\s*$/);
            die("Does not match: $depline\n") unless ( $depline =~ m/^([^()]+)\((.+?)-(\d+)((?:&apos;)*), (.+?)-(\d+)((?:&apos;)*)\)$/ );
            my ( $rel, $reg, $regidx, $regcopy, $dep, $depidx, $depcopy ) = ( $1, $2, $3, $4, $5, $6, $7 );
            if ( $regidx != $depidx or $regcopy ne $depcopy ) {
		if ($rel eq "root") {
		    $root = $depidx;
		}
		else {
		    push( @{ $indeps[$depidx] },  [ $rel, $reg, $regidx, $regcopy, $dep, $depidx, $depcopy ] );
		    push( @{ $outdeps[$regidx] }, [ $rel, $reg, $regidx, $regcopy, $dep, $depidx, $depcopy ] );
		}
            }
            else {
                print STDERR "ignore $depline\n";
                #$ignored++;
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
		    $line .= "\t";
                    $counter++;
		    $line .= "root" if ($counter == $root);
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

    #print $dom->toString(0);
    return $dom->toString(0);
}
