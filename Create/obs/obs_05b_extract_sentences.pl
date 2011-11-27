#!/usr/bin/perl

use warnings;
use strict;

use Encode;
use CWB::CQP;
use entities;
use DB_File;
use DBM_Filter;
use common_functions;
use Data::Dumper;

binmode(STDOUT, "utf8");

my $corpus = "TESTCORP";
my @c5 = qw(AJ0 AJ0-AV0 AJ0-NN1 AJ0-VVD AJ0-VVG AJ0-VVN AJC AJS AT0 AV0 AV0-AJ0 AVP AVP-PRP AVQ AVQ-CJS CJC CJS CJS-AVQ CJS-PRP CJT CJT-DT0 CRD CRD-PNI DPS DT0 DT0-CJT DTQ EX0 ITJ NN0 NN1 NN1-AJ0 NN1-NP0 NN1-VVB NN1-VVG NN2 NN2-VVZ NP0 NP0-NN1 ORD PNI PNI-CRD PNP PNQ PNX POS PRF PRP PRP-AVP PRP-CJS PUL PUN PUQ PUR TO0 UNC VBB VBD VBG VBI VBN VBZ VDB VDD VDG VDI VDN VDZ VHB VHD VHG VHI VHN VHZ VM0 VVB VVB-NN1 VVD VVD-AJ0 VVD-VVN VVG VVG-AJ0 VVG-NN1 VVI VVN VVN-AJ0 VVN-VVD VVZ VVZ-NN2 XX0 ZZ0);
my $c5 = join("|", @c5);

my $btree = new DB_File::BTREEINFO;
$btree->{'cachesize'} = 1024*1024*512;

my $outdir = "/localhome/Databases/temp/cwb";
my $maxloglevel = 3;

my %words2ids;
my $wordids = 0;
#my $w2i = tie(%words2ids, "DB_File", "$outdir/words2ids.btree", O_RDWR|O_CREAT, 0600, $DB_BTREE) or die("Cannot open file '$outdir/words2ids.btree': $!");
my $w2i = tie(%words2ids, "DB_File", "$outdir/words2ids.btree", O_RDONLY, 0600, $btree) or die("Cannot open file '$outdir/words2ids.btree': $!");
$w2i->Filter_Push('utf8');
open(SENT, ">:encoding(utf8)", "$outdir/sentences.out") or die("Cannot open $outdir/sentences.out: $!");
&extract_sentences;
close(SENT) or die("Cannot close $outdir/sentences.out: $!");
undef($w2i);
untie(%words2ids);
&common_functions::log("Finished", 1, $maxloglevel);
&common_functions::log("You can now run\n\t05c_split_pack_sentences.sh", 1, $maxloglevel);


sub extract_sentences{
    my $cqp = new CWB::CQP("-r /localhome/Databases/CWB/registry");
    $cqp->set_error_handler('die'); # built-in, useful for one-off scripts
    $cqp->exec("$corpus;");
    $cqp->exec("set Context s;");
    &common_functions::log("Start query", 1, $maxloglevel);
    #$cqp->exec_query("Result = <s> []* </s> cut 20000;");
    $cqp->exec_query("Result = <s> []* </s>;");
    &common_functions::log($cqp->status, 1, $maxloglevel);
    my $size = ($cqp->exec("size Result;"))[0];
    &common_functions::log("Processing $size sentences", 1, $maxloglevel);
    $cqp->exec("show +c5 -cpos +s_len;");
#$cqp->run("cat Result 0 99;");
    $cqp->run("cat Result;");
    my $ergcounter = 0;
    while(defined(my $res = $cqp->getline)){
	my $slen;
	my $obslen = 0;
	my @sentence;
	$ergcounter++;
	&common_functions::log(sprintf("%.2f%% (%d)", ($ergcounter/$size)*100, $ergcounter), 2, $maxloglevel) if($ergcounter % 6000 == 0);
	$res = entities::latin1_to_utf8($res);
	die("Returned line doesn't match (< ... >)") unless(substr($res, 0, 1) eq "<" and substr($res, -1, 1) eq ">");
	$res = substr($res, 1, length($res) - 2);
	die("Returned line doesn't match (<s_len> ... </s_len>)") unless(substr($res, 0, 7) eq "<s_len " and substr($res, -8, 8) eq "</s_len>");
	$res = substr($res, 0, length($res) - 8);
	$res =~ m/^<s_len (\d+)>/;
	$slen = $1;
	$res =~ s/^<s_len (\d+)>//;
	while($res =~ m!(.+?)/($c5)(?:\s+|$)!g){
	    my $tokid;
	    my $token = $1;
	    my $tag = $2;
	    if(exists($words2ids{$token})){
		$tokid = $words2ids{$token};
	    }else{
		die("No token id found for $token");
	    }
	    push(@sentence, "$tokid/$tag");
	    $obslen++;
	}
	die("How long is this line: $slen or $obslen? '$res'") if($slen != $obslen);
	print SENT join(" ", @sentence), "\n";
    }
    undef $cqp; # close down CQP server (exits gracefully)
} 
