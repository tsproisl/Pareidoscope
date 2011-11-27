#!/usr/bin/perl

# create list of types and the ngrams they occur in (to be run on HPC system)
# input: hashdumps, split sentences
# output: list (typid ngid position ngfreq)

use warnings;
use strict;

use DB_File;
use Storable qw();

use Data::Dumper;

my $minlength = 2;
my $maxlength = 9;
my %sentids;
my $nr1 = shift(@ARGV);
my $nr2 = shift(@ARGV);
my $path = shift(@ARGV);
my $in = $path; #"/tmp/slli02"; #"/localhome/Databases/temp/ngrams";
my $data = $path; #"/tmp/slli02"; #"/localhome/Corpora/Packed_BNC";
my $out = $path; #"/tmp/slli02"; #".";


my @nghashes = <$in/*.hash>;
my @bncfiles = <$in/x*>;
die("There is no hash dump!") if(scalar(@nghashes) < 1);
die("This script was written for a single bnc file!") if(scalar(@bncfiles) > 1);
open(my $OUT, ">$out/$nr1-$nr2.txt") or die("Cannot open outfile: $!");

foreach my $ngelem (@nghashes){
    $ngelem =~ m!/([^/]+\.hash)$!;
    my $hashname = $1;
    my $nghash  = Storable::retrieve($ngelem);
    my $bncfile = $bncfiles[0];
    my ($first, $last);# = (0, 0);
    if($hashname =~ m/([^_]+)_([^:]+):([^_]+)_([^.]+)\.hash$/){
	($first, $last) = ($1, $3);
    }else{
	die("File name has unexpected form: $nghashes[0]");
    }
    &extract_ngrams($nghash, $bncfile, $first, $last);
}
close($OUT) or die("Cannot close outfile: $!");

sub extract_ngrams{
    my ($nghash, $bncfile, $first, $last) = @_;
    open(my $FH, $bncfile) or die("Cannot open $bncfile: $!");
    #my %range = map(($c5[$_], 1), ($c5{$first} .. $c5{$last}));
    my %range = map(($_, 1), ($first .. $last));
    while(defined(my $sentence = <$FH>)){
	my @tokens;
	my @tags;
	chomp($sentence);
	my @toktags = split(/\s+/, $sentence);
	foreach my $toktag (@toktags){
	    my ($tok, $tag) = split(/\//, $toktag);
	    push(@tokens, $tok);
	    push(@tags, $tag);
	}
	&ngrams($nghash, \@tags, \@tokens, scalar(@toktags), 2, 9, \%range);
    }
    close($FH) or die("Cannot close $bncfile: $! $?");
}

sub ngrams{
    my ($nghash, $tagsref, $tokensref, $slen, $gmin, $gmax, $rangeref) = @_;
    my $lmax = $gmax < $slen ? $gmax : $slen;
    for(my $i = 0; $i <= $slen - $gmin; $i++){
	next unless(exists($rangeref->{$tagsref->[$i]}));
        my $maxpos = ($i + $lmax) < $slen ? $i + $lmax : $slen;
        for(my $l = $gmin; $l <= $maxpos - $i; $l++){
            my @ngram;
            my $ngram;
            my $ngid;
	    my $ngfreq;
            @ngram = @$tagsref[$i .. $i + $l - 1];
            $ngram = join(" ", @ngram);
            #die("Poorly programmed...") if($l != scalar(@ngram));
            next unless(exists($nghash->{$ngram}));
	    $ngid = $nghash->{$ngram}->[0];
	    $ngfreq = $nghash->{$ngram}->[1];
            for(my $j = $i; $j < $i + $l; $j++){
		print $OUT $tokensref->[$j] . "\t$ngid\t" .  ($j - $i) . "\t$ngfreq\n";
            }
        }
    }
}
