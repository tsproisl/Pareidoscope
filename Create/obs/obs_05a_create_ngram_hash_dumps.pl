#!/usr/bin/perl

# create hashdumps for processing on HPC system
# input: ngrams.out.uniq
# output: hashdumps {ngram => [ngid, ngfreq]}

use warnings;
use strict;

use Storable qw();
use DB_File;
use common_functions;
use DBI;

die("./05a_create_ngram_hash_dumps.pl outdir") unless(scalar(@ARGV) == 2);
my $dir = shift(@ARGV);
my $dbname = shift(@ARGV);
die("Not a directory: $dir") unless(-d $dir);
die("Not a file: $dir/$dbname") unless(-e "$dir/$dbname");

my @c5; #= qw(AJ0 AJ0-AV0 AJ0-NN1 AJ0-VVD AJ0-VVG AJ0-VVN AJC AJS AT0 AV0 AV0-AJ0 AVP AVP-PRP AVQ AVQ-CJS CJC CJS CJS-AVQ CJS-PRP CJT CJT-DT0 CRD CRD-PNI DPS DT0 DT0-CJT DTQ EX0 ITJ NN0 NN1 NN1-AJ0 NN1-NP0 NN1-VVB NN1-VVG NN2 NN2-VVZ NP0 NP0-NN1 ORD PNI PNI-CRD PNP PNQ PNX POS PRF PRP PRP-AVP PRP-CJS PUL PUN PUQ PUR TO0 UNC VBB VBD VBG VBI VBN VBZ VDB VDD VDG VDI VDN VDZ VHB VHD VHG VHI VHN VHZ VM0 VVB VVB-NN1 VVD VVD-AJ0 VVD-VVN VVG VVG-AJ0 VVG-NN1 VVI VVN VVN-AJ0 VVN-VVD VVZ VVZ-NN2 XX0 ZZ0);

my $ngids = 0;
my @lines;
tie(@lines, "DB_File", "$dir/ngrams.out.uniq", O_RDONLY, 0666, $DB_RECNO) or die "Cannot open file $dir/ngrams.out.uniq: $!\n";
my $dbh = DBI->connect( "dbi:SQLite:$dir/$dbname" ) or die("Cannot connect: $DBI::errstr");
&fetchngrams();
untie(@lines);
$dbh->disconnect();
&common_functions::log("Finished", 1, 1);
&common_functions::log("You can now run 05b_extract_sentences.pl and 05c_split_pack_sentences.sh or proceed with 06_*", 1, 1);

sub fetchngrams{
    my (%ngrams, $count, $imin, $jmin);
    my $fetchc5 = $dbh->prepare(qq{SELECT gramid, grami FROM gramis});
    $fetchc5->execute();
    while(my ($gramid, $grami) = $fetchc5->fetchrow_array){
	$c5[$gramid] = $grami;
    }
    $count = 0;
    ($imin, $jmin) = (1, 1);
    &common_functions::log("Fetch ngrams...", 1, 1);
    my $last = "";
    for(my $i=1; $i<=$#c5; $i++){
        for(my $j=1; $j<=$#c5; $j++){
	    my $ngramsref = &fetchwithprefix($i, $j);
	    my $rows = scalar(keys %$ngramsref);
            if($count + $rows > 2000000){
                my ($imax, $jmax) = ($i, $j);
                if($j > 1){
                    $jmax = $j - 1;
                }else{
                    $jmax = $#c5;
                    $imax = $i - 1;
                }
                &export(\%ngrams, $imin, $jmin, $imax, $jmax);
                $imin = $i;
                $jmin = $j;
                $count = 0;
                undef(%ngrams);
            }
            &common_functions::log("${i}_$j ($c5[$i]_$c5[$j])", 1, 1);
            &addngrams($ngramsref, \%ngrams);
            $count += $rows;
        }
    }
    &export(\%ngrams, $imin, $jmin, $#c5, $#c5);
}

sub fetchwithprefix{
    my ($p1, $p2) = @_;
    my %ngrams;
    while(1){
	my $line = $lines[$ngids];
	return \%ngrams unless(defined($line));
	my ($ngram, $length, $freq) = split(/\t/, $line);
	my @ngram = split(/ /, $ngram);
	if($ngram[0] == $p1 and $ngram[1] == $p2){
	    $ngrams{$ngram} = [$ngids+1, $freq];
	    $ngids++;
	}else{
	    return \%ngrams;
	}
    }
    return \%ngrams;
}

sub addngrams{
    my ($ng1, $ng2) = @_;
    while(my ($key, $value) = each(%$ng1)){
	$ng2->{$key} = $value;
    }
}

sub export{
    my ($ngs, $imin, $jmin, $imax, $jmax) = @_;
    #my ($imi, $jmi, $ima, $jma) = ($c5[$imin], $c5[$jmin], $c5[$imax], $c5[$jmax]);
    &common_functions::log("Dump ${imin}_$jmin:${imax}_$jmax", 1, 1);
    Storable::nstore($ngs, "$dir/hashdumps/${imin}_$jmin:${imax}_$jmax.hash");
}
