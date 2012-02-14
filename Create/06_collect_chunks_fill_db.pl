#!/usr/bin/perl

# Collect chunks and fill SQLite database with data
# input: encoded corpus
# output: full database, chunks.out

use warnings;
use strict;
use open qw(:std :utf8);

use CWB::CL;
use common_functions;
use DBI;

die("./06_collect_chunks_fill_db.pl outdir corpus-name dbname regfile") unless ( scalar(@ARGV) == 4 );
my $outdir  = shift(@ARGV);
my $corpus  = shift(@ARGV);
my $dbname  = shift(@ARGV);
my $regfile = shift(@ARGV);
die("Not a directory: $outdir") unless ( -d $outdir );

my @chunks = qw(adjp advp conjp intj lst np o pp prt qp sbar ucp vp);
my %chunks;
my $chunks = join( "|", @chunks );

my $maxloglevel = 3;
my $cwb_decode  = "cwb-decode -r /localhome/Databases/CWB/registry -n -H $corpus -P word -S s " . join( " ", map( "-S $_", @chunks ) );
my $dbh         = DBI->connect("dbi:SQLite:$outdir/$dbname") or die("Cannot connect: $DBI::errstr");
$dbh->do(qq{PRAGMA encoding = 'UTF-8'});
$dbh->do(qq{DROP TABLE IF EXISTS chunks});
$dbh->do(qq{DROP TABLE IF EXISTS sentences});
$dbh->do(qq{CREATE TABLE chunks (chunkid INTEGER PRIMARY KEY, chunk VARCHAR(5) NOT NULL, frequency INTEGER NOT NULL, UNIQUE (chunk))});
$dbh->do(qq{CREATE TABLE sentences (cpos INTEGER PRIMARY KEY, chunkseq TEXT NOT NULL, cposseq TEXT NOT NULL)});
open( my $decode, "-|", $cwb_decode ) or die("Cannot open pipe: $!");
open( my $co, ">:encoding(utf8)", "$outdir/chunks.out" ) or die("Cannot open $outdir/chunks.out: $!");
&create_indexes;
$dbh->disconnect();
close($decode) or die("Cannot close pipe: $!");
close($co)     or die("Cannot close $outdir/chunks.out: $!");
&common_functions::log( "Finished", 1, $maxloglevel );

sub create_indexes {
    $CWB::CL::Registry = '/localhome/Databases/CWB/registry';
    my $corpus_handle  = new CWB::CL::Corpus $corpus;
    my $word           = &get_attribute( "word", $corpus_handle );
    my $pos            = &get_attribute( "pos", $corpus_handle );
    my $lemma          = &get_attribute( "lemma", $corpus_handle );
    my $wc             = &get_attribute( "wc", $corpus_handle );
    my $insertchunk    = $dbh->prepare(qq{INSERT INTO chunks (chunk, frequency) VALUES (?, 0)});
    my $fetchchunkid   = $dbh->prepare(qq{SELECT chunkid FROM chunks WHERE chunk = ?});
    my $insertsentence = $dbh->prepare(qq{INSERT INTO sentences (cpos, chunkseq, cposseq) VALUES (?, ?, ?)});
    my $updatefreq     = $dbh->prepare(qq{UPDATE chunks SET frequency = ? WHERE chunkid = ?});
    my $gettypid       = $dbh->prepare(qq{SELECT types.typid FROM types, gramis, lemmata WHERE types.type=? AND gramis.grami=? AND lemmata.lemma=? AND lemmata.wc=? AND types.gramid=gramis.gramid AND types.lemid=lemmata.lemid});
    my $updatetype     = $dbh->prepare(qq{UPDATE types SET chunkseq=? WHERE typid=?});
    $dbh->do(qq{BEGIN TRANSACTION});
    my %typids;
    my @typids;
    my %chunkfreq;

    # fill in chunks
    foreach my $chunk (@chunks) {
        $chunks{$chunk} = &insertandreturnid( $insertchunk, $fetchchunkid, [$chunk] );
	$chunkfreq{$chunks{$chunk}} = 0;
    }

    # current sentence
    #     current chunk
    #         word
    #         word

    # events: <s> </s> <$chunks> </$chunks> ELSE
    my ( $sentpos, @chunkseq, @cposseq, $activechunk );
    &common_functions::log( "Start processing", 1, $maxloglevel );
    while ( defined( my $line = <$decode> ) ) {
        chomp($line);
        die("Non-matching line: $line\n") unless ( $line =~ m/^\s*(\d+): (.+)$/ );
        my $cpos = $1;
        $gettypid->execute( $word->cpos2str($cpos), $pos->cpos2str($cpos), $lemma->cpos2str($cpos), $wc->cpos2str($cpos) );
        my ($typid) = $gettypid->fetchrow_array;
        push( @typids, $typid );
        foreach my $token ( split( / /, $2 ) ) {
            if ( $token eq "<s>" ) {
                $sentpos = $cpos;
            }
            elsif ( $token eq "</s>" ) {
                $insertsentence->execute( $sentpos, join( " ", @chunkseq ), join( " ", @cposseq ) );
                &ngrams( \@chunkseq, scalar(@chunkseq), 1, 9, \@typids, \%typids, \@cposseq );
                undef($sentpos);
                @chunkseq = ();
                @cposseq  = ();
                @typids   = ();
            }
            elsif ( $token =~ m/<($chunks)>/ ) {
                $activechunk = $1;
                push( @chunkseq, $chunks{$activechunk} );
                push( @cposseq,  $cpos - $sentpos );
                $chunkfreq{ $chunks{$activechunk} }++;
            }
            elsif ( $token =~ m/<\/($chunks)>/ ) {
                undef($activechunk);
            }
        }
    }
    foreach my $chunk (@chunks) {
        $updatefreq->execute( $chunkfreq{ $chunks{$chunk} }, $chunks{$chunk} );
    }
    foreach my $typid ( keys %typids ) {
        $updatetype->execute( $typids{$typid}, $typid );
    }
    $dbh->do(qq{COMMIT});
}

sub ngrams {
    my ( $tagsref, $slen, $gmin, $gmax, $arrayref, $hashref, $cposref ) = @_;
    die("How long is this sentence?") if ( scalar(@$tagsref) != $slen );
    for ( my $start = 0; $start <= $slen - $gmin; $start++ ) {
        my $maxlength = $slen - $start > $gmax ? $gmax : $slen - $start;
        for ( my $length = $gmin; $length <= $maxlength; $length++ ) {
            my ( @ngram, $ngram );
            @ngram = @$tagsref[ $start .. $start + $length - 1 ];
            $ngram = join( " ", @ngram );
            print $co "$ngram\t$length\n";
            my $end = defined( $cposref->[ $start + $length ] ) ? $cposref->[ $start + $length ] - 1 : $#$arrayref;
            foreach ( $cposref->[$start] .. $end ) {
                $hashref->{ $arrayref->[$_] }++;
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
