#!/usr/bin/perl

# fill the SQLite database with data and collect sentences and ngrams
# output: full database, tabulate.out, ngrams.out

use warnings;
use strict;

use Encode;
use CWB::CQP;
use CWB::CL;
use entities;
use common_functions;
use Data::Dumper;
use DBI;

use open qw(:std :utf8);

#binmode(STDOUT, "utf8");

# ngid ; n-gram ; frequency
# word ; frequency ; (n-gram ; position ; frequency)
# word surface <-> word id
# n-gram surface <-> n-gram id

die("./03a_create_indexes.pl outdir corpus-name dbname regfile tagset") unless ( scalar(@ARGV) == 5 );
my $outdir  = shift(@ARGV);
my $corpus  = shift(@ARGV);
my $dbname  = shift(@ARGV);
my $regfile = shift(@ARGV);
my $tset    = shift(@ARGV);
die("Not a directory: $outdir") unless ( -d $outdir );

my @tagset;
{
    no warnings "qw";

    if ( $tset eq "c5" ) {

        # C5 tagset without ambiguity tags
        @tagset = qw(AJ0 AJC AJS AT0 AV0 AVP AVQ CJC CJS CJT CRD DPS DT0 DTQ EX0 ITJ NN0 NN1 NN2 NP0 ORD PNI PNP PNQ PNX POS PRF PRP PUL PUN PUQ PUR TO0 UNC VBB VBD VBG VBI VBN VBZ VDB VDD VDG VDI VDN VDZ VHB VHD VHG VHI VHN VHZ VM0 VVB VVD VVG VVI VVN VVZ XX0 ZZ0);
    }
    elsif ( $tset eq "penn_extended" ) {

        # PTB tagset plus additional tags from ANC MASC I: XX, HYPH (hyphen), AFX (affix), NFP (ellipsis: ...)
        #@tagset = qw(AFX CC CD DT EX FW HYPH IN JJ JJR JJS LS MD NFP NN NNP NNPS NNS PDT POS PRP PRP$ RB RBR RBS RP SYM TO UH VB VBD VBG VBN VBP VBZ WDT WP WP$ WRB XX # $ , . :  `` '' ( ) [ ] { });
        @tagset = qw(AFX CC CD DT EX FW HYPH IN JJ JJR JJS LS MD NFP NN NNP NNPS NNS PDT POS PRP PRP$ RB RBR RBS RP SYM TO UH VB VBD VBG VBN VBP VBZ WDT WP WP$ WRB XX # $ , . :  `` '' -LRB- -RRB- -LSB- -RSB- -LCB- -RCB-);
    }
    elsif ( $tset eq "penn" ) {

        # nur PTB
        #@tagset = qw(CC CD DT EX FW IN JJ JJR JJS LS MD NN NNP NNPS NNS PDT POS PRP PRP$ RB RBR RBS RP SYM TO UH VB VBD VBG VBN VBP VBZ WDT WP WP$ WRB # $ , . :  `` '' ( ) [ ] { });
        @tagset = qw(CC CD DT EX FW IN JJ JJR JJS LS MD NN NNP NNPS NNS PDT POS PRP PRP$ RB RBR RBS RP SYM TO UH VB VBD VBG VBN VBP VBZ WDT WP WP$ WRB # $ , . :  `` '' -LRB- -RRB- -LSB- -RSB- -LCB- -RCB-);
    }
}
my %tagset;
my $tagset = join( "|", @tagset );
my %lemmata;    # %lemmata = (lemma => {wc => [id, freq]})
my %types;      # %types = (type => {grami => {lemid => [id, freq, ngfreq]}})

my $maxloglevel = 3;

my $dbh = DBI->connect("dbi:SQLite:$outdir/$dbname") or die("Cannot connect: $DBI::errstr");
#$dbh->do("PRAGMA foreign_keys = ON");
$dbh->do("PRAGMA encoding = 'UTF-8'");
$dbh->do(qq{DROP TABLE IF EXISTS lemmata});
$dbh->do(qq{DROP TABLE IF EXISTS types});
$dbh->do(qq{DROP TABLE IF EXISTS gramis});
$dbh->do(qq{DROP INDEX IF EXISTS lemididx});
$dbh->do(qq{CREATE TABLE lemmata (lemid INTEGER PRIMARY KEY, lemma VARCHAR(255) NOT NULL, wc VARCHAR(10) NOT NULL, freq INTEGER NOT NULL, UNIQUE (lemma, wc))});
$dbh->do(qq{CREATE TABLE types (typid INTEGER PRIMARY KEY, lemid INTEGER NOT NULL, type VARCHAR(255) NOT NULL, gramid INTEGER NOT NULL, freq INTEGER NOT NULL, posseq INTEGER, chunkseq INTEGER, FOREIGN KEY (lemid) REFERENCES lemmata (lemid), FOREIGN KEY (gramid) REFERENCES gramis (gramid), UNIQUE (type, gramid, lemid))});
$dbh->do(qq{CREATE TABLE gramis (gramid INTEGER PRIMARY KEY, grami VARCHAR(25) NOT NULL, UNIQUE (grami))});
$dbh->do(qq{CREATE INDEX lemididx ON types (lemid)});
open( NG, ">:encoding(utf8)", "$outdir/ngrams.out" ) or die("Cannot open $outdir/ngrams.out: $!");
&create_indexes;
$dbh->disconnect();
close(NG) or die("Cannot close $outdir/ngrams.out: $!");
&common_functions::log( "Finished", 1, $maxloglevel );

sub create_indexes {
    my $cqp = new CWB::CQP;
    $cqp->set_error_handler('die');    # built-in, useful for one-off scripts
    $cqp->exec("set Registry '/localhome/Databases/CWB/registry'");
    $cqp->exec($corpus);
    $CWB::CL::Registry = '/localhome/Databases/CWB/registry';
    my $corpus_handle = new CWB::CL::Corpus $corpus;
    my $insertgrami   = $dbh->prepare(qq{INSERT INTO gramis (grami) VALUES (?)});
    my $fetchgramid   = $dbh->prepare(qq{SELECT gramid FROM gramis WHERE grami=?});
    my $insertlemma   = $dbh->prepare(qq{INSERT INTO lemmata (lemma, wc, freq) VALUES (?, ?, ?)});
    my $fetchlemid    = $dbh->prepare(qq{SELECT lemid FROM lemmata WHERE lemma=? AND wc=? AND freq=?});
    my $inserttype    = $dbh->prepare(qq{INSERT INTO types (type, gramid, lemid, freq, posseq, chunkseq) VALUES (?, ?, ?, ?, ?, ?)});
    my $fetchtypid    = $dbh->prepare(qq{SELECT typid FROM types WHERE type=? AND gramid=? AND lemid=? AND freq=? AND posseq=? AND chunkseq=?});
    my $updatelemma   = $dbh->prepare(qq{UPDATE lemmata SET freq=? WHERE lemid=?});

    #my $updatetype = $dbh->prepare(qq{UPDATE types SET freq=? WHERE typid=?});
    my $updatetype = $dbh->prepare(qq{UPDATE types SET freq=?, posseq=? WHERE typid=?});
    $dbh->do(qq{BEGIN TRANSACTION});
    foreach my $tag (@tagset) {
        $tagset{$tag} = &insertandreturnid( $insertgrami, $fetchgramid, [$tag] );
    }
    &common_functions::log( "Start processing", 1, $maxloglevel );
    my $ergcounter = 0;
    my $Slen = &get_attribute( "s_len", $corpus_handle );
    $cqp->exec("A = <s> [] expand to s");
    my ($size) = $cqp->exec("size A");
    &common_functions::log( "Finished query. There are $size sentences.", 1, $maxloglevel );
    $cqp->exec("tabulate A match .. matchend word, match .. matchend pos, match .. matchend lemma, match .. matchend wc, match > \"$outdir/tabulate.out\"");
    open( TAB, "<:encoding(utf8)", "$outdir/tabulate.out" ) or die("Cannot open $outdir/tabulate.out: $!");
    &common_functions::log( "Finished tabulating results.", 1, $maxloglevel );

    while ( defined( my $match = <TAB> ) ) {
        chomp($match);
        my ( $words, $corptags, $lemmata, $wcs, $position ) = split( /\t/, $match );

        #my (@tokens, @tags, @sentence);
        my ( @tokens, @tags, @lemmids );
        my ( @words, @corptags, @lemmata, @wcs );
        my $slen;
        @words    = split( / /, $words );
        @corptags = split( / /, $corptags );
        @lemmata  = split( / /, $lemmata );
        @wcs      = split( / /, $wcs );
        $ergcounter++;
        &common_functions::log( sprintf( "%d/%d (%.2f%%)", $ergcounter, $size, ( ( $ergcounter / $size ) * 100 ) ), 1, $maxloglevel ) unless ( $ergcounter % 100000 );
        die("Damn, tabulate does not seem to work as expected!") unless ( scalar(@words) == scalar(@corptags) and scalar(@words) == scalar(@lemmata) and scalar(@words) == scalar(@wcs) );
        $slen = $Slen->cpos2str($position);
        die("Different lengths for tabulate and s_len attribute") unless ( $slen == scalar(@words) );

        for ( my $i = 0; $i <= $#words; $i++ ) {
            my ( $lemid, $typid );
            my $type  = $words[$i];
            my $tag   = $corptags[$i];
            my $wc    = $wcs[$i];
            my $lemma = $lemmata[$i];
            my $grami = $tagset{$tag};
            print "$tag\n" unless ( defined($grami) );
            if ( exists( $lemmata{$lemma}->{$wc} ) ) {
                $lemid = $lemmata{$lemma}->{$wc}->[0];
                $lemmata{$lemma}->{$wc}->[1]++;
            }
            else {
                $lemid = &insertandreturnid( $insertlemma, $fetchlemid, [ $lemma, $wc, 1 ] );
                $lemmata{$lemma}->{$wc} = [ $lemid, 1 ];
            }
            if ( exists( $types{$type}->{$grami}->{$lemid} ) ) {
                $typid = $types{$type}->{$grami}->{$lemid}->[0];
                $types{$type}->{$grami}->{$lemid}->[1]++;
            }
            else {
                $typid = &insertandreturnid( $inserttype, $fetchtypid, [ $type, $grami, $lemid, 1, 0, 0 ] );
                $types{$type}->{$grami}->{$lemid} = [ $typid, 1, 0 ];
            }
            push( @tokens,  $type );
            push( @tags,    $grami );
            push( @lemmids, $lemid );

            #push(@sentence, "$typid/$grami");
        }
        &ngrams( \@tags, $slen, 1, 9, \@tokens, \@lemmids, \%types );
    }
    close(TAB) or die("Cannot close $outdir/tabulate.out: $!");

    $dbh->do(qq{COMMIT});
    $dbh->do(qq{BEGIN TRANSACTION});
    &common_functions::log( "All sentences processed", 1, $maxloglevel );
    undef $corpus_handle;
    undef $cqp;    # close down CQP server (exits gracefully)
    &common_functions::log( "Update lemma information in database", 1, $maxloglevel );
    foreach my $lemma ( keys %lemmata ) {
        foreach my $wc ( keys %{ $lemmata{$lemma} } ) {

            #$updatelemma->execute($lemmata{$lemma}->{$wc}->[0], $lemma, $wc, $lemmata{$lemma}->{$wc}->[1]);
            $updatelemma->execute( $lemmata{$lemma}->{$wc}->[1], $lemmata{$lemma}->{$wc}->[0] );
        }
    }
    $dbh->do(qq{COMMIT});
    $dbh->do(qq{BEGIN TRANSACTION});
    &common_functions::log( "Update type information in database", 1, $maxloglevel );
    foreach my $type ( keys %types ) {
        foreach my $grami ( keys %{ $types{$type} } ) {
            foreach my $lemid ( keys %{ $types{$type}->{$grami} } ) {

                #$updatetype->execute($types{$type}->{$grami}->{$lemid}->[0], $type, $grami, $lemid, $types{$type}->{$grami}->{$lemid}->[1], 1);
                $updatetype->execute( $types{$type}->{$grami}->{$lemid}->[1], $types{$type}->{$grami}->{$lemid}->[2], $types{$type}->{$grami}->{$lemid}->[0] );
            }
        }
    }
    $dbh->do(qq{COMMIT});
}

sub ngrams {
    my ( $tagsref, $slen, $gmin, $gmax, $tokensref, $lemmidsref, $typesref ) = @_;
    die("How long is this sentence?") if ( scalar(@$tagsref) != $slen );
    for ( my $start = 0; $start <= $slen - $gmin; $start++ ) {
        my $maxlength = $slen - $start > $gmax ? $gmax : $slen - $start;
        for ( my $length = $gmin; $length <= $maxlength; $length++ ) {
            my ( @ngram, $ngram );
            @ngram = @$tagsref[ $start .. $start + $length - 1 ];
            $ngram = join( " ", @ngram );
            print NG "$ngram\t$length\n";
            foreach ( $start .. $start + $length - 1 ) {
                my $x = $tokensref->[$_];
                $x = $tagsref->[$_];
                $x = $lemmidsref->[$_];
                $typesref->{ $tokensref->[$_] }->{ $tagsref->[$_] }->{ $lemmidsref->[$_] }->[2]++;
            }
        }
    }
}

sub insertandreturnid {
    my ( $insert, $get, $argsref ) = @_;
    $insert->execute(@$argsref);
    $get->execute(@$argsref);
    my $all  = $get->fetchall_arrayref;
    my $rows = scalar(@$all);
    die("Query returns more than one ID") if ( $rows > 1 );
    die("Query returns no ID") if ( $rows < 1 );
    my ($id) = @{ $all->[0] };
    return $id;
}

sub get_attribute {
    my ( $name, $corpus_handle ) = @_;

    # try p-attribute first ...
    my $att = $corpus_handle->attribute( $name, "p" );

    # ... then try s-attribute
    $att = $corpus_handle->attribute( $name, "s" ) unless ( defined($att) );

    # ... finally try a-attribute
    $att = $corpus_handle->attribute( $name, "a" ) unless ( defined($att) );
    die "Can't open attribute " . $corpus . ".$name, sorry." unless ( defined($att) );

    # store attribute handle in cache
    return $att;
}
