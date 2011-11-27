#!/usr/bin/perl

# create vertical files for use with CWB
# input: BNC XML files
# output: Vertical files

use warnings;
use strict;

use Encode;
#use entities;
use common_functions;
use Unicode::Normalize;

my $maxloglevel = 5;
my $corpus = "British National Corpus";
my @files = </projects/korpora/BNC-XML/texts/*/*/*.xml>;
#my @files = </projects/korpora/BNC-XML/texts/A/A0/A06.xml>;
my $outdir = "/localhome/Corpora/BNC_vrt";

my %c5_ambig_to_wc = ("AJ0" => "ADJ", "AJ0-AV0" => "ADJ", "AJ0-NN1" => "ADJ", "AJ0-VVD" => "ADJ", "AJ0-VVG" => "ADJ", "AJ0-VVN" => "ADJ", "AJC" => "ADJ", "AJS" => "ADJ",
		      "AT0" => "ART",
		      "AV0" => "ADV", "AV0-AJ0" => "ADV", "AVP" => "ADV", "AVP-PRP" => "ADV", "AVQ" => "ADV",  "AVQ-CJS" => "ADV",
		      "CJC" => "CONJ", "CJS" => "CONJ", "CJS-AVQ" => "CONJ", "CJS-PRP" => "CONJ", "CJT" => "CONJ", "CJT-DT0" => "CONJ",
		      "CRD" => "ADJ", "CRD-PNI" => "ADJ",
		      "DPS" => "PRON",
		      "DT0" => "ADJ", "DT0-CJT" => "ADJ",
		      "DTQ" => "PRON", "EX0" => "PRON", "ITJ" => "INTERJ",
		      "NN0" => "SUBST", "NN1" => "SUBST", "NN1-AJ0" => "SUBST", "NN1-NP0" => "SUBST", "NN1-VVB" => "SUBST", "NN1-VVG" => "SUBST", "NN2" => "SUBST", "NN2-VVZ" => "SUBST", "NP0" => "SUBST", "NP0-NN1" => "SUBST",
		      "ORD" => "ADJ",
		      "PNI" => "PRON", "PNI-CRD" => "PRON", "PNP" => "PRON", "PNQ" => "PRON", "PNX" => "PRON",
		      "POS" => "UNC",
		      "PRF" => "PREP", "PRP" => "PREP", "PRP-AVP" => "PREP", "PRP-CJS" => "PREP",
		      "PUL" => "PUNC", "PUN" => "PUNC", "PUQ" => "PUNC", "PUR" => "PUNC",
		      "TO0" => "PREP",
		      "UNC" => "UNC",
		      "VBB" => "VERB", "VBD" => "VERB", "VBG" => "VERB", "VBI" => "VERB", "VBN" => "VERB", "VBZ" => "VERB", "VDB" => "VERB", "VDD" => "VERB", "VDG" => "VERB", "VDI" => "VERB", "VDN" => "VERB", "VDZ" => "VERB", "VHB" => "VERB", "VHD" => "VERB", "VHG" => "VERB", "VHI" => "VERB", "VHN" => "VERB", "VHZ" => "VERB", "VM0" => "VERB", "VVB" => "VERB", "VVB-NN1" => "VERB", "VVD" => "VERB", "VVD-AJ0" => "VERB", "VVD-VVN" => "VERB", "VVG" => "VERB", "VVG-AJ0" => "VERB", "VVG-NN1" => "VERB", "VVI" => "VERB", "VVN" => "VERB", "VVN-AJ0" => "VERB", "VVN-VVD" => "VERB", "VVZ" => "VERB", "VVZ-NN2" => "VERB",
		      "XX0" => "ADV",
		      "ZZ0" => "SUBST");


&xml2vrt(\@files);

sub xml2vrt{
    my ($filesref) = @_;
    foreach my $file (@$filesref){
        my $filename;
        my $textid;
        my $sentences;
	$file =~ m{/([^/]+)\.xml};
        $filename = $1;
        die("Strange filename: $file") unless defined($filename);
	&common_functions::log("Processing $filename", 1, $maxloglevel);
        open(my $PIPE, "cat $file | tr -d '\\n' | sed -e 's/&#10;//g;' | xmllint --format - | xsltproc oneWordPerLine.xsl - |") or die "Can't run xsltproc: $!";
	#binmode($PIPE, "utf8");
	$sentences = &get_sentence_iterator($PIPE, $textid, $filename);
	#open(OUT, ">:encoding(iso-8859-1)", "$outdir/$filename.vrt") or die("Cannot open $outdir/$filename.vrt: $!");
	open(OUT, ">:encoding(utf8)", "$outdir/$filename.vrt") or die("Cannot open $outdir/$filename.vrt: $!");
	print OUT "<?xml version='1.0' encoding='UTF-8'?>\n";
	print OUT "<file name='$filename'>\n";
        while(defined(my $sentence = $sentences->())){
            my ($sentref, $sentid) = @$sentence;
            my $sentlen = scalar(@$sentref);
            print OUT "<s id='${filename}-$sentid' len='$sentlen'>\n";
	    print OUT join("\n", map(join("\t", @$_), @$sentref)) . "\n";
            print OUT "</s>\n";
        }
        close($PIPE) or die("Bad xsltproc: $! $?");
	print OUT "</file>\n";
	close(OUT) or die("Cannot close $outdir/$filename.vrt: $!");
    }
}

sub get_sentence_iterator{
    my ($PIPE, $textid, $filename) = @_;
    my $lastid = "";
    my $nexttolastid;
    my @sentence;
    my @flush;
    my $sentid;
    my $sentcounter = 0;
    my $line = "";
    my $inprocess = 1;
    my $last = 0;
    return sub {
        while(defined($line) and $inprocess){
            my $text;
	    my @columns;
	    my ($id, $wf, $lemma, $tag, $pos);
            $line = <$PIPE>;
            unless(defined $line){
                $last = 1;
                $inprocess = 0;
                last;
            }
	    $line = Encode::decode("utf8", $line);
	    $line = Unicode::Normalize::NFKC($line);
	    $line =~ s/&/&amp;/g;
	    $line =~ s/</&lt;/g;
	    $line =~ s/>/&gt;/g;
	    $line =~ s/"/&quot;/g;
	    $line =~ s/'/&apos;/g;
	    #$line = entities::encode_entities($line);
            @columns = map(&strip_whitespace($_), split(/\t/, $line));
            die("Not exactly five columns: $line") if(scalar(@columns) != 5);
            ($id, $wf, $lemma, $tag, $pos) = @columns;
            if($lemma eq '' and $wf eq ''){
                &common_functions::log("Null lemma and null word form at $filename, $id: $line", 1, $maxloglevel);
                next;
            }
            if($lemma eq ''){
                if($tag eq 'PUN' or $tag eq 'PUL' or $tag eq 'PUR' or $tag eq 'PUQ'){
                    $lemma = $wf;
                    $pos = "PUNC";
                }elsif($tag eq 'UNC' and $pos eq 'UNC'){
                    $lemma = $wf;
                }else{
                    die("We missed something: $line (tag: '$tag', pos: '$pos')");
                }
            }
            if($wf eq ''){
                if($tag eq 'PUN' or $tag eq 'PUL' or $tag eq 'PUR' or $tag eq 'PUQ'){
                    $wf = $lemma;
                    $pos = "PUNC";
                }elsif($tag eq 'UNC' and $pos eq 'UNC'){
                    $wf = $lemma;
                }else{
                    die("We missed something: $line (tag: '$tag', pos: '$pos')");
                }
            }
	    # repair word classes
	    $pos = $c5_ambig_to_wc{$tag} if($pos ne $c5_ambig_to_wc{$tag});
	    # remove whitespace from tokens and lemmata (a hack)
	    $wf =~ s/\s+//g;
	    $lemma =~ s/\s+//g;
            ($text, $sentid) = split(/\./, $id);
            if($text ne $filename){
                die("$text ne $filename") if($filename ne "G3C");
            }
            if($sentid ne $lastid){
                if($lastid ne ""){
                    $inprocess = 0;
		    $sentcounter++;
                    @flush = @sentence;
		    $nexttolastid = $lastid;
                }
                @sentence = ();
                $lastid = $sentid;
            }
            push(@sentence, [$wf, $lemma, $tag, $pos]);
        }
        if(defined($line)){
            $inprocess = 1;
            #return [\@flush, $sentcounter];
            return [\@flush, $nexttolastid];
	    #$lastid = $sentid;
        }
        if($last){
            $last = 0;
            #push(@sentence, ["</s>", "</s>", "</s>", "</s>"]);
            $sentcounter++;
            #return [\@sentence, $sentcounter];
            return [\@sentence, $sentid];
        }
        return;
    }
}

sub strip_whitespace{
    my $string = shift;
    $string =~ s/^\s*//;
    $string =~ s/\s*$//;
    return $string;
}

