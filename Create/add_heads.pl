#!/usr/bin/perl

# Some chunks have their heads not marked. This is fixed.

use warnings;
use strict;

use XML::LibXML;

die("Specify a file name\n") unless(@ARGV == 1);
my $file = shift(@ARGV);
die("Something is wrong with file '$file'\n") unless(-e $file and -r _);

my $dom = XML::LibXML->load_xml(location => $file);
foreach my $s ($dom->getElementsByTagName("s")){
    foreach my $phrase ($s->childNodes()){
	my $name = $phrase->nodeName();
	next if(substr($name, 0, 1) eq "#");
	my @h = $phrase->getChildrenByTagName("h");
	if(@h == 0){
	    my @children = $phrase->childNodes();
	    die("Too many or too few children\n") unless(@children == 1);
	    my $text = $phrase->textContent;
	    $phrase->removeChild($children[0]);
	    chomp($text);
	    $text =~ s/^\n//;
	    my @text = split(/\n/, $text);
	    my $newhead = XML::LibXML::Element->new("h");
	    if(@text > 1){
		$newhead->appendTextNode("\n" . $text[$#text] . "\n");
		my $oldtext = join("\n", @text[0 .. $#text - 1]);
		$oldtext = "\n" . $oldtext . "\n";
		$phrase->appendChild(XML::LibXML::Text->new($oldtext));
		$phrase->appendChild($newhead);
		$phrase->appendChild(XML::LibXML::Text->new("\n"));
	    }
	    elsif(@text < 1){
		die("Not enough text in node\n");
	    }
	    else{
		$newhead->appendTextNode("\n" . $text[0] . "\n");
		$phrase->appendChild(XML::LibXML::Text->new("\n"));
		$phrase->appendChild($newhead);
		$phrase->appendChild(XML::LibXML::Text->new("\n"));
	    }
	}
	elsif(@h > 1){
	    # 1 head is okay
	    die("Strange phrase: more than one head!\n");
	}
    }
}

print $dom->toString(0);
