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

# ngid ; n-gram ; frequency
# word ; frequency ; (n-gram ; position ; frequency)+
# word surface <-> word id
# n-gram surface <-> n-gram id

my $btree = new DB_File::BTREEINFO;
$btree->{'cachesize'} = 1024*1024*256;

my $dir = "/localhome/Databases/temp/cwb";
my %words2ids;
my %ids2words;
my $w2i = tie(%words2ids, "DB_File", "$dir/words2ids.btree", O_RDONLY, 0666, $btree) or die("Cannot open file '$dir/words2ids.btree': $!");
$w2i->Filter_Push('utf8');
unlink("$dir/ids2words.btree");
my $i2w = tie(%ids2words, "DB_File", "$dir/ids2words.btree", O_RDWR|O_CREAT, 0600, $btree) or die("Cannot open file '$dir/ids2words.btree': $!");
$i2w->Filter_Push('utf8');

while(my ($key, $val) = each %words2ids){
    die("$val is already here: $ids2words{$val}") if(exists($ids2words{$val}));
    $ids2words{$val} = $key;
}

undef($w2i);
untie(%words2ids);
undef($i2w);
untie(%ids2words);
