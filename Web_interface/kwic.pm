package kwic;

use warnings;
use strict;
use CGI::Carp qw(fatalsToBrowser);
use URI::Escape;

sub display{
    my ($cgi, $config) = @_;
    my $state = $config->keep_states_href({}, qw(c));
    my ($size, $end);
    my $vars;
    my $sid = $config->get_attribute("s_id");
    $config->{"cache"}->retrieve($config->{"params"}->{"id"});
    ($size) = $config->{"cqp"}->exec("size " . $config->{"params"}->{"id"});
    $end = $config->{"params"}->{"start"} + 39 > $size - 1 ? $size - 1 : $config->{"params"}->{"start"} + 39;
    my @ranges = $config->{"cqp"}->dump($config->{"params"}->{"id"}, $config->{"params"}->{"start"}, $end);
    $vars->{"start"} = $config->{"params"}->{"start"} + 1;
    $vars->{"end"} = $end + 1;
    $vars->{"matches"} = $size;
    foreach my $n ($config->{"params"}->{"start"} .. $end){
	my $row;
	my $idx = $n - $config->{"params"}->{"start"};
	my ($s, $e, $t, $k) = @{$ranges[$idx]};
	my ($cs, $ce, $ellip_start, $ellip_end) = &context($config, $s, $e, "1s");
	my $id = $sid->cpos2struc2str($s);
	my $dispid = $id;
	$dispid =~ s/-/&nbsp;/g;
	$row->{"id"} = $dispid;
	$row->{"id_href"} = "pareidoscope.cgi?m=dc&id=" . $config->{"params"}->{"id"} . "&q=$id&s=Link&$state";
	$row->{"pre"} = &format($cgi, $config, $cs, $s - 1, $t, $k);
	$row->{"kwic"} = &format($cgi, $config, $s, $e, $t, $k);
	$row->{"post"} = &format($cgi, $config, $e + 1, $ce, $t, $k);
	push(@{$vars->{"rows"}}, $row);
    }
    $vars->{"previous_href"} = "pareidoscope.cgi?m=d&id=" . $config->{"params"}->{"id"} . "&start=" . &max($config->{"params"}->{"start"} - 40, 0) . "&s=Link&$state" if($config->{"params"}->{"start"} > 0);
    $vars->{"next_href"} = "pareidoscope.cgi?m=d&id=" . $config->{"params"}->{"id"} . "&start=" . ($config->{"params"}->{"start"} + 40) . "&s=Link&$state" unless($end + 1 == $size);
    return $vars;
}


# ($c_start, $c_end, $ellip_start, $ellip_end) = My::KWIC::Context($lang, $start, $end);
#   start and end cpos of context around region $start .. $end;
#   $ellip_start and $ellip_end indicate that it might be appropriate to put an ellipsis "..." before/after context
sub context{
    croak 'Usage:  ($c_start, $c_end) = kwic::context($config, $start, $end [, $context]);' unless(@_ == 3 or @_ == 4);
    my ($config, $s, $e, $context) = @_;
    my $cs = $s - 5;    # default context: 5 words (if appropriate context cannot be determined)
    my $ce = $e + 5;
    my $ellip_start = 1;
    my $ellip_end = 1;
    if(defined($context)){
	$context =~ /^\s*([0-9]*)\s*([a-z_][a-z0-9_-]*)\s*$/ or croak "kwic::context: invalid context specification '$context'.";
	my $num  = $1;
	my $unit = $2;
	$num = 1 unless($num);
	croak "kwic::context: invalid context specification '$context'." unless($num >= 1);
	if($unit =~ /^words?$/){
	    $cs = $s - $num;
	    $ce = $e + $num;
	}else{
	    my $att = $config->get_attribute($unit);    # hope it's a structural attribute, otherwise we'll just crash
	    croak "kwic::context: attribute does not exist in context specification '$context'." unless(defined($att));
	    my $struc = $att->cpos2struc($s);
	    if(defined $struc){
		$struc = $struc + 1 - $num;
		$struc = 0 if($struc < 0);
		($cs, undef) = $att->struc2cpos($struc);
		$ellip_start = 0;
	    }
	    $struc = $att->cpos2struc($e);
	    if(defined $struc){
		$struc = $struc - 1 + $num;
		my $max = $att->max_struc;
		$struc = $max - 1 if($struc >= $max);
		(undef, $ce) = $att->struc2cpos($struc);
		$ellip_end = 0;
	    }
	}
    }
    # now make sure context doesn't extend beyond corpus limits
    my $att = $config->get_attribute("word");
    my $max = $att->max_cpos;
    if($cs < 0){
	$ellip_start = 0;
	$cs = 0;
    }
    if($ce >= $max){
	$ellip_end = 0;
	$ce = $max - 1;
    }
    return ($cs, $ce, $ellip_start, $ellip_end);
}


# $html_string = My::KWIC::Format($lang, $start, $end [, $target, $keyword]);
#   format corpus range $s .. $e as HTML string according to parameter settings
sub format {
    croak 'Usage:  $html_string = kwic::format($cgi, $config, $start, $end [, $target, $keyword]);' unless @_ >= 4 and @_ <= 6;
    my ($cgi, $config, $start, $end, $target, $keyword) = @_;
    # load relevant attributes (to avoid multiple lookups)
    my $Word  = $config->get_attribute("word");
    my $POS   = $config->get_attribute("pos");
    
    # now go through range of cpos and format each token
    my @html = ();    # list of HTML-formatted tokens (and phrase boundaries)
    for my $cpos ($start .. $end) {
	my $html  = "";                                                          # process token annotations
	my $word  = $Word->cpos2str($cpos);
	my $pos   = $POS->cpos2str($cpos);
	$html = $cgi->span({'title'=>$cgi->escapeHTML("$word") . "/" . $cgi->escapeHTML("$pos")}, $cgi->escapeHTML("$word"));
	if ( $cpos == $keyword ) {
	    $html = $cgi->span( { -class => 'keyword' }, $html );
	}
	if ( $cpos == $target ) {
	    $html = $cgi->span( { -class => 'target' }, $html );
	}
	push @html, $html;
    }
    return join(" ", @html);
}


sub display_context{
    my ($cgi, $config) = @_;
    my $sentid = $config->{"params"}->{"q"};
    my $sid = $config->get_attribute("s_id");
    my $ps;
    $sentid =~ s/\s+/ /g;
    $config->{"cache"}->retrieve($config->{"params"}->{"id"});
    my @ranges = $config->{"cqp"}->dump($config->{"params"}->{"id"});
    foreach my $range (@ranges){
	my ($s, $e, $t, $k) = @$range;
	my $p;
	my $id = $sid->cpos2struc2str($s);
	next unless($id eq $sentid);
	my ($cs, $ce, $ellip_start, $ellip_end) = &context($config, $s, $e, "5s");
	$id =~ s/-/&nbsp;/g;
	$p->{"pre"} = &format($cgi, $config, $cs, $s - 1, $t, $k);
	$p->{"kwic"} = &format($cgi, $config, $s, $e, $t, $k);
	$p->{"post"} = &format($cgi, $config, $e + 1, $ce, $t, $k);
	push(@$ps, $p);
    }
    return $ps;
}


sub max{
    my ($arg1, $arg2) = @_;
    return $arg1 if($arg1 >= $arg2);
    return $arg2;
}


1;
