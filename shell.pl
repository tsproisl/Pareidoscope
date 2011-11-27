#!/usr/bin/perl

# text-based interface for n-gram analysis
# normally, the cgi interface should be preferred

#--- NGramShell ---#
package NGramShell;
use lib "/home/linguistik/tsproisl/bin/lib/perl5/site_perl";
use warnings;
use strict;

use Encode;
use base qw(Term::Shell);
use DBI;
#se DBM_Filter;
use CWB::CQP;

use readlocaldata;
use statistics;
use entities;

use Data::Dumper;

my $tmp = "/localhome/Databases/temp/cwb";
my $cqp;
my $dbh;
my @nr2grami;
my %grami2nr;
my $n = 4068395610;




my $conttable = "       | n-gram | !n-gram |
 ------+--------+---------+----
  word |  O11   |   O12   | R1
 ------+--------+---------+----
 !word |  O21   |   O22   | R2
 ------+--------+---------+----
       |   C1   |    C2   | N";

# IDEAS
# implement dynamic 0.5% threshold
#

#       | n-gram | !n-gram |
# ------+--------+---------+----
#  word |  O11   |   O12   | R1
# ------+--------+---------+----
# !word |  O21   |   O22   | R2
# ------+--------+---------+----
#       |   C1   |    C2   | N

# INIT
sub init{
    my $self = shift;
    $dbh = DBI->connect( "dbi:SQLite:$tmp/testcorp.db" ) or die("Cannot connect: $DBI::errstr");
    $cqp = new CWB::CQP("-r /localhome/Databases/CWB/registry");
    $cqp->set_error_handler('die'); # built-in, useful for one-off scripts
    $cqp->exec("TESTCORP;");
    my $fetchc5 = $dbh->prepare(qq{SELECT gramid, grami FROM gramis});
    $fetchc5->execute();
    while(my ($gramid, $grami) = $fetchc5->fetchrow_array){
        $nr2grami[$gramid] = $grami;
	$grami2nr{$grami} = $gramid;
    }
    &readlocaldata::init($tmp, \@nr2grami);
}

# FINI
sub fini{
    my $self = shift;
    $dbh->disconnect();
    undef $cqp; # close down CQP server (exits gracefully)
    &readlocaldata::fini();
}

# WORDFORM
sub run_wordform{
    my $self = shift;
    my @args = @_;
    my ($wf, $wfe, $threshold, $tag, $c5, $typid, $query, $typesref);
    my $gettypids = $dbh->prepare(qq{SELECT typid, type, grami, freq, ngfreq FROM types WHERE type=?});
    my $gettypidsgrami = $dbh->prepare(qq{SELECT typid, freq, ngfreq FROM types WHERE type=? AND grami=?});
    return unless(&check_args($self, \@args, 1, 2));
    $wf = $args[0];
    if(defined($args[1])){
	$threshold = $args[1];
    }else{
	print "Using dynamic threshold of 0.5\%\n";
    }
    if($wf =~ m/(.+?)(?<!\\)_(.+)$/){
	$wf = $1;
	$tag = $2;
	if(exists($grami2nr{$tag})){
	    $c5 = $grami2nr{$tag};
	}else{
	    print "Not a valid part-of-speech tag: $tag\n";
	    return;
	}
    }
    if(defined($c5)){
	$gettypidsgrami->execute($wf, $c5);
	$typesref = $gettypidsgrami->fetchall_arrayref;
    }else{
	$gettypids->execute($wf);
	$typesref = $gettypids->fetchall_arrayref;
    }
    #$wfe = &entities::utf8_to_latin1($wf);
    #$query = defined($tag) ? "A = [word='$wfe' & c5='$tag'];" : "A = [word='$wfe'];";
    #my @lines = $cqp->exec_query($query);
    #$cqp->exec_query($query);
    #my @lines = $cqp->exec("size A;");
    #print "frequency: $lines[0]\n";
    #$typid = $words2ids{Encode::decode("utf8", $wf)};
    #foreach my $row (@$typids){
	#$typids{$row->[0]} = [$row->[1], $row->[2], $row->[3]];
    #}
    #%typids = map(($_->[0], $_->[1]), @$typids);
    #print join(", ", @typids), "\n";
    #print Dumper(\%typids);
    &analyze_types($typesref, $threshold);
}
sub smry_wordform{"returns all n-grams a given word form does occur in"}
sub help_wordform{
    <<'END';
Synopsis
wordform wordform[_tag] [threshold]

       | n-gram | !n-gram |
 ------+--------+---------+----
  word |  O11   |   O12   | R1
 ------+--------+---------+----
 !word |  O21   |   O22   | R2
 ------+--------+---------+----
       |   C1   |    C2   | N

What does wordform do?
1. Find out in which n-gram slots the wordform occurs and how often (O11, R1)
2. Find out how frequent these n-grams are (C1)
3. Apply a statistical test (currently the G-test) to the contingency tables
4. Sort according to G and print out the n-grams which are most strongly associated with the wordform
END
}

# LEMMA
sub run_lemma{
    my $self = shift;
    my @args = @_;
    my ($lemma, $wc, $threshold, $lemmaq, $typids, %typids);
    print "Bitte weitergehen... es gibt hier nichts zu sehen\n";
    return;
    return unless(&check_args($self, \@args, 1, 2));
    $lemma = $args[0];
    if(defined($args[1])){
	$threshold = $args[1];
    }else{
	print "Using dynamic threshold of 0.5\%\n";
    }
    if($lemma =~ m/(.+?)(?<!\\)_(.+)$/){
	$lemma = $1;
	$wc = uc($2);
    }
    ###
    $lemmaq = &dequote($dbh->quote($lemma));
    #$gettypids->execute($lemmaq, $wc);
    #$typids = $gettypids->fetchall_arrayref;
    #foreach my $row (@$typids){
	#$typids{$row->[0]} = [$row->[1], $row->[2], $row->[3]];
    #}
    #print Dumper(\%typids);
    #&analyze_types(\%typids, $threshold);
}
sub smry_lemma{"returns all n-grams a given lemma does occur in"}
sub help_lemma{
    <<'END';
Synopsis
lemma lemma[_word class] [threshold]

       | n-gram | !n-gram |
 ------+--------+---------+----
  word |  O11   |   O12   | R1
 ------+--------+---------+----
 !word |  O21   |   O22   | R2
 ------+--------+---------+----
       |   C1   |    C2   | N

What does lemma do?
1. Find all wordforms belonging to the lemma
2. Find out in which n-gram slots these wordforms occur and how often (O11, R1)
2. Find out how frequent these n-grams are (C1)
3. Apply a statistical test (currently the G-test) to the contingency tables
4. Sort according to G and print out the n-grams which are most strongly associated with the wordforms
END
}

# N-GRAM
sub run_ngram{
    my $self = shift;
    my @args = @_;
    my ($wf, @ng, $wfq, $typids, @typids, $query, $position, @o11, $ngid, $ngfreq, @G, $r1, @out);
    print "Bitte weitergehen... es gibt hier nichts zu sehen\n";
    return;
    return unless(&check_args($self, \@args, 3, 10));
    $wf = $args[0];
    @ng = map(uc($_), @args[1..$#args]);
    $wfq = $dbh->quote($wf);
    ($query, $position, $ngid) = &build_ngram_query($wfq, \@ng);
    print $query, "\n";
    $ngfreq = &readlocaldata::get_ng_freq($ngid);
    my $fetchtypids = $dbh->prepare($query);
    $fetchtypids->execute;
    $r1 = $fetchtypids->rows;
    $typids = $fetchtypids->fetchall_arrayref;
    print "fetched $r1 rows\n";
    foreach my $row (@$typids){
	for(my $i=0; $i<=$#$row; $i++){
	    $o11[$i]->{$row->[$i]}++;
	}
    }
    #print Dumper(\@o11);
    for(my $i=0; $i<=$#o11; $i++){
	foreach my $typid (keys %{$o11[$i]}){
	    $typids[$i]->{$typid} = &type_in_ngram($typid, $ngid, $i);
	}
    }
    print "collected type frequencies\n";
    #print Dumper(\@typids);
    for(my $i=0; $i<=$#o11; $i++){
	foreach my $typid (keys %{$o11[$i]}){
	    $G[$i]->{$typid} = &statistics::g($o11[$i]->{$typid}, $r1, $typids[$i]->{$typid}, $ngfreq);
	}
    }
    #print Dumper(\@G);
    for(my $i=0; $i<=$#G; $i++){
	my $max = scalar(keys %{$G[$i]}) > 54 ? 53 : scalar(keys %{$G[$i]}) - 1;
	my $j = 0;
	foreach my $typid ((sort {$G[$i]->{$b} <=> $G[$i]->{$a}} keys %{$G[$i]})[0..$max]){
	    $out[$j]->[$i] = [$typid, $o11[$i]->{$typid}, $typids[$i]->{$typid}, $G[$i]->{$typid}];
	    $j++;
	}
    }
    #print Dumper(\@out);
    print "+" . "-" x 32 . "+" . "-" x 32 . "+" . "-" x 32 . "+\n";
    foreach my $row (@out){
	print "| " . join(" | ", map(defined($_) ? sprintf("%14s %5s %3s %7s", &fetch_type($_->[0]), $_->[1], $_->[2], $_->[3]) : " " x 25, @$row)), " |\n";
    }
    print "+" . "-" x 32 . "+" . "-" x 32 . "+" . "-" x 32 . "+\n";
}
sub smry_ngram{"returns all n-grams a given lemma does occur in"}
sub help_ngram{
    <<'END';
ngram wordform ngram
END
}

sub check_args{
    my ($self, $args, $min, $max) = @_;
    my $found = scalar(@$args);
    my $cmd = $self->{"API"}->{"command"}->{"run"}->{"name"};
    if($found < $min or $found > $max){
	print sprintf("$found argument%s found but between $min and $max arguments expected. Use 'help $cmd' for further information.\n", $found == 1 ? "" : "s");
	return 0;
    }
    return 1;
}

sub fetch_ngram{
    my ($ngid, $position) = @_;
    my $getng = $dbh->prepare(qq{SELECT length, s1, s2, s3, s4, s5, s6, s7, s8, s9 FROM ngrams WHERE ngid=?});
    $getng->execute($ngid);
    my @ngram = $getng->fetchrow_array;
    my @clearngram = map($nr2grami[$_], @ngram[1..$ngram[0]]);
    $clearngram[$position-1] = "_$clearngram[$position-1]_";
    return join(" ", @clearngram);
}

sub fetch_type{
    my ($typid) = @_;
    my $gettype = $dbh->prepare(qq{SELECT type FROM types WHERE typid=?});
    $gettype->execute($typid);
    return ($gettype->fetchrow_array)[0];
}

sub dequote{
    my $string = shift;
    return substr($string, 1, length($string)-2);
}

sub analyze_types{
    my ($typesref, $threshold) = @_;
    while(@$typesref){
	my $localthreshold = $threshold;
	my %ngids;
	my $rowref = shift(@$typesref);
	my $typid = shift(@$rowref);
	my $type = shift(@$rowref);
	my $grami = shift(@$rowref);
	my $typefreq = shift(@$rowref);
	my $ngfreq = shift(@$rowref);
	print "frequency: $typefreq\n";
	my $iter = &readlocaldata::get_data_interface($typid);
	# TODO: typefreq neu berechnen, falls $tag definiert ist
	#$localthreshold = sprintf("%d", $typesref->{$typid}->[2] / 100 * 0.5) unless(defined($localthreshold));
	#$localthreshold = sprintf("%d", $typesref->{$typid}->[2] / 100 * 0.5) unless(defined($localthreshold));
	$localthreshold = 1 if($localthreshold < 1);
	while(my $ref = $iter->()){
	    while(@$ref){
		my $ngid = shift(@$ref);
		my $position = shift(@$ref);
		my $ngramfreq = shift(@$ref);
		my $freq = shift(@$ref);
	    #for(my $i = 0; $i <= $#$ref - 3; $i += 4){
		#my $ngid = $ref->[$i];
		#my $position = $ref->[$i+1];
		#my $freq = $ref->[$i+2];
		#my $ngfreq = $ref->[$i+3];
		next if($freq < $localthreshold);
		#my ($ngram, $length, $ngfreq) = split(/\t/, $ngrams[$ngid]);
		#my ($length, $ngfreq, @ngram) = &readlocaldata::get_ngram_info($ngid);
		#$ngram[$position] = "_$ngram[$position]_";
		my $G = &statistics::g($freq, $ngfreq, $ngramfreq, $n);
		# !!! TODO !!!
		$ngids{"$ngid-$position"} = [$freq, $ngramfreq, $G];
	    }
	}
	print "$typefreq n-gram tokens, using frequency threshold of $localthreshold\n";
	print "+" . "-" x 44 . "+" . "-" x 9 . "+" . "-" x 9 . "+" . "-" x 13 . "+\n";
	print sprintf("| %42s | %7s | %7s | %11s |\n", qw{n-gram freq ngfreq log-like});
	print "+" . "-" x 44 . "+" . "-" x 9 . "+" . "-" x 9 . "+" . "-" x 13 . "+\n";
	my $max = scalar(keys %ngids) > 54 ? 53 : scalar(keys %ngids) - 1 ;
	foreach my $ngidpos ((sort {$ngids{$b}->[2] <=> $ngids{$a}->[2]} keys %ngids)[0..$max]){
	    $ngidpos =~ m/^(\d+)-(\d+)$/;
	    print sprintf("| %42s | %7s | %7s | %11s |\n", &find_ngram($1, $2, $ngids{$ngidpos}->[1]), @{$ngids{$ngidpos}});
	}
	print "+" . "-" x 44 . "+" . "-" x 9 . "+" . "-" x 9 . "+" . "-" x 13 . "+\n";
    }
}

sub find_ngram{
    my ($ngid, $position, $ngf) = @_;
    my ($length, $ngfreq, @ngram) = &readlocaldata::get_ngram_info($ngid);
    die("How frequent is this n-gram? $ngf != $ngfreq\n$ngid: @ngram") if($ngf != $ngfreq);
    $ngram[$position] = "<" . $ngram[$position] . ">";
    return join(" ", @ngram);
}

#sub analyze_types_old{
#    my ($typidsref, $threshold) = @_;
#    foreach my $typid (keys %$typidsref){
#	my $localthreshold = $threshold;
#	print "$typidsref->{$typid}->[0]_" . $nr2grami{$typidsref->{$typid}->[1]} . " ($typidsref->{$typid}->[2])\n";
#	my %ngids;
#	my $iter = &readlocaldata::get_data_interface($typid);
#	my $typefreq = &readlocaldata::get_type_freq($typid);
#	$localthreshold = sprintf("%d", $typidsref->{$typid}->[2] / 100 * 0.5) unless(defined($localthreshold));
#	$localthreshold = 1 if($localthreshold < 1);
#	while(my $ref = $iter->()){
#	    while(@$ref){
#		my $ngid = shift(@$ref);
#		my $position = shift(@$ref);
#		my $freq = shift(@$ref);
#		next if($freq < $localthreshold);
#		my $ngfreq = &readlocaldata::get_ng_freq($ngid);
#		my $G = &statistics::g($freq, $typefreq, $ngfreq, $n);
#		#print &fetch_ngram($ngid, $position) . ": $position ($freq / $ngfreq / $typefreq) $G\n";
#		#$getngfreq->execute($ngid);
#		#my $ngfreq = $getngfreq->fetchall_arrayref;
#		#print $ngfreq->[0]->[0], "\n";
#		$ngids{"$ngid-$position"} = [$freq, $ngfreq, $G];
#	    }
#	}
#	print "$typefreq n-gram tokens, using frequency threshold of $localthreshold\n";
#	print "+" . "-" x 44 . "+" . "-" x 9 . "+" . "-" x 9 . "+" . "-" x 13 . "+\n";
#	print sprintf("| %42s | %7s | %7s | %11s |\n", qw{n-gram freq ngfreq log-like});
#	print "+" . "-" x 44 . "+" . "-" x 9 . "+" . "-" x 9 . "+" . "-" x 13 . "+\n";
#	my $max = scalar(keys %ngids) > 54 ? 53 : scalar(keys %ngids) - 1 ;
#	foreach my $ngidpos ((sort {$ngids{$b}->[2] <=> $ngids{$a}->[2]} keys %ngids)[0..$max]){
#	    $ngidpos =~ m/^(\d+)-(\d+)$/;
#	    print sprintf("| %42s | %7s | %7s | %11s |\n", &fetch_ngram($1, $2), @{$ngids{$ngidpos}});
#	}
#	print "+" . "-" x 44 . "+" . "-" x 9 . "+" . "-" x 9 . "+" . "-" x 13 . "+\n";
#    }
#}

sub build_ngram_query{
    my ($type, $ngref) = @_;
    my ($position, $cngref) = &clean_ngram($ngref);
    my @ngram = map($grami2nr{$_}, @$cngref);
    my $ngid = &find_ngram_id(\@ngram);
    my @ngids = &split_ngram(\@ngram);
    my $query = "SELECT ";
    $query .= join(", ", map("t$_.typid", (0..$#ngram)));
    $query .= " FROM ";
    $query .= join(", ", map("tokens AS t$_", (0..$#ngram)));
    $query .= ", ";
    $query .= join(", ", map("bigrams AS b$_", (0..$#ngids)));
    $query .= ", types AS ty WHERE ";
    $query .= join(" AND ", map("t$_.sentid=b0.sentid", (0..$#ngram)));
    $query .= " AND ";
    $query .= join(" AND ", map("t$_.position=b0.position+$_", (0..$#ngram)));
    $query .= " AND ";
    $query .= join(" AND ", map("b$_.ngid=$ngids[$_]", (0..$#ngids)));
    if(scalar(@ngids) > 1){
	$query .= " AND ";
	$query .= join(" AND ", map("b$_.sentid=b0.sentid", (1..$#ngids)));
	$query .= " AND ";
	$query .= join(" AND ", map("b$_.position=b0.position+" . 2*$_, (1..$#ngids)));
    }
    $query .= " AND ty.type=$type AND ty.grami=$ngram[$position] AND ty.typid=t$position.typid";
    return $query, $position, $ngid;
}

sub clean_ngram{
    my $ngref = shift;
    my @ngram = @$ngref;
    for(my $i = 0; $i <= $#ngram; $i++){
	if($ngram[$i] =~ m/_([^_]+)_/){
	    $ngram[$i] = $1;
	    return ($i, \@ngram);
	}
    }
    return (-1, \@ngram);
}

sub split_ngram{
    my ($ngref, @ngids) = @_;
    if(scalar(@$ngref) >= 2 and scalar(@$ngref) <= 3){
	# add id to @ngids and return @ngids
	push(@ngids, &find_ngram_id($ngref));
	return @ngids;
    }elsif(scalar(@$ngref) > 3){
	# id von @$ngref[0..2]
	push(@ngids, &find_ngram_id([@$ngref[0..2]]));
	$ngref = [@$ngref[2..$#$ngref]];
	return &split_ngram($ngref, @ngids);
    }else{
	die("An n-gram of length " . scalar(@$ngref) . " was not expected...");
    }
}

sub find_ngram_id{
    my ($ngref) = @_;
    my @ngram = @$ngref;
    my $findngramid = $dbh->prepare(qq{SELECT ngid FROM ngrams WHERE s1=? AND s2=? AND s3=? AND s4=? AND s5=? AND s6=? AND s7=? AND s8=? AND s9=?});
    $findngramid->execute((@ngram, (0,0,0,0,0,0,0,0,0))[0..8]);
    my $ngid = $findngramid->fetchrow_arrayref;
    return $ngid->[0];
}

sub type_in_ngram{
    my ($typid, $ngid, $position) = @_;
    my $iter = &readlocaldata::get_data_interface($typid);
    my $c = 0;
    OUTER: while(my $ref = $iter->()){
	$c++;
	my $erg = -1;
	my $first = 0;
	my $last = (scalar(@$ref) / 3) - 1;
	#print "$c: $ref->[0] -- " . $ref->[$last*3] . "\n";
	die("ngids not sorted ($c): $ref->[0] > $ngid") if($ref->[0] > $ngid);
	next OUTER if($ref->[$last*3] < $ngid);
	INNER: while($first <= $last and $erg < 0){
	    my $middle = sprintf("%d", $first + (($last - $first) / 2));
	    if($ref->[$middle*3] < $ngid){
		#print "\t$middle: " . $ref->[$middle*3] . " < $ngid\n";
		$first = $middle + 1;
	    }elsif($ref->[$middle*3] > $ngid){
		#print "\t$middle: " . $ref->[$middle*3] . " > $ngid\n";
		$last = $middle - 1;
	    }else{
		#print "\t$middle: " . $ref->[$middle*3] . " = $ngid\n";
		my $freq = &find_position($ngid, $middle*3, $position+1, $ref, 0);
		#print "freq = $freq\n";
		next OUTER if($freq == 0);
		return $freq;
	    }
	}
	#while(@$ref){
	#    my $lngid = shift(@$ref);
	#    my $lposition = shift(@$ref);
	#    my $freq = shift(@$ref);
	#    return $freq if($lngid == $ngid and $lposition == $position + 1);
	#}
    }
    return 0;
}

sub find_position{
    my ($ngid, $current, $position, $ref, $direction) = @_;
    #print "$ngid, $current, $position, $ref, $direction\n";
    #print join(", ", ($ref->[$current], $ref->[$current+1], $ref->[$current+2])), "\n";
    return 0 if($ref->[$current] != $ngid);
    if($ref->[$current+1] < $position){
	die("ngids not sorted") if($direction == -1);
	return &find_position($ngid, $current+3, $position, $ref, 1);
    }elsif($ref->[$current+1] > $position){
	die("ngids not sorted") if($direction == 1);
	return &find_position($ngid, $current-3, $position, $ref, -1);
    }else{
	return $ref->[$current+2];
    }
}

1;

#--- main ---#
package main;
use warnings;
use strict;

my $shell = NGramShell->new;
$shell->cmdloop;
