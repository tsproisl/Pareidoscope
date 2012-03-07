package kwic;
use Dancer ':syntax';

use Carp;
use List::Util qw(max);
use URI::Escape;

sub display{
    my ($data) = @_;
    my %state;
    $state{"corpus"} = param("corpus");
    $state{"id"} = param("id");
    $state{"s"} = "Link";
    my ($size, $end);
    my $vars;
    my $sid = $data->get_attribute("s_id");
    $data->{"cache"}->retrieve(param("id"));
    ($size) = $data->{"cqp"}->exec("size " . param("id"));
    $end = param("start") + 39 > $size - 1 ? $size - 1 : param("start") + 39;
    my @ranges = $data->{"cqp"}->dump(param("id"), param("start"), $end);
    $vars->{"match_start"} = param("start") + 1;
    $vars->{"match_end"} = $end + 1;
    $vars->{"matches"} = $size;
    foreach my $n (param("start") .. $end){
	my $row;
	my $idx = $n - param("start");
	my ($s, $e, $t, $k) = @{$ranges[$idx]};
	my ($cs, $ce, $ellip_start, $ellip_end) = &context($data, $s, $e, "1s");
	my $id = $sid->cpos2struc2str($s);
	my $dispid = $id;
	$dispid =~ s/-/&nbsp;/g;
	$row->{"id"} = $dispid;
	#$row->{"id_href"} = "pareidoscope.cgi?m=dc&id=" . param("id") . "&q=$id&s=Link&$state";
	$row->{"id_href"} = {%state};
	$row->{"id_href"}->{"sentence_id"} = $id;	
	$row->{"pre"} = &format($data, $cs, $s - 1, $t, $k);
	$row->{"kwic"} = &format($data, $s, $e, $t, $k);
	$row->{"post"} = &format($data, $e + 1, $ce, $t, $k);
	push(@{$vars->{"rows"}}, $row);
    }
    $state{"query"} = URI::Escape::uri_escape(param("query"));
    $vars->{"previous_href"} = {%state};
    $vars->{"previous_href"}->{"start"} = max(param("start") - 40, 0);
    $vars->{"next_href"} = {%state};
    $vars->{"next_href"}->{"start"} = param("start") + 40;
    return $vars;
}


# ($c_start, $c_end, $ellip_start, $ellip_end) = My::KWIC::Context($lang, $start, $end);
#   start and end cpos of context around region $start .. $end;
#   $ellip_start and $ellip_end indicate that it might be appropriate to put an ellipsis "..." before/after context
sub context{
    croak 'Usage:  ($c_start, $c_end) = kwic::context($config, $start, $end [, $context]);' unless(@_ == 3 or @_ == 4);
    my ($data, $s, $e, $context) = @_;
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
	    my $att = $data->get_attribute($unit);    # hope it's a structural attribute, otherwise we'll just crash
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
    my $att = $data->get_attribute("word");
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
    my ($data, $start, $end, $target, $keyword) = @_;
    # load relevant attributes (to avoid multiple lookups)
    my $Word  = $data->get_attribute("word");
    my $POS   = $data->get_attribute("pos");
    
    # now go through range of cpos and format each token
    my @html = ();    # list of HTML-formatted tokens (and phrase boundaries)
    for my $cpos ($start .. $end) {
	my $html  = "";                                                          # process token annotations
	my $word  = $Word->cpos2str($cpos);
	my $pos   = $POS->cpos2str($cpos);
	#$html = "<span title='" . &escapeHTML($word) . "/" . &escapeHTML($pos) . "'>" . &escapeHTML($word) . "</span>";
	$html = "<span title='" . $word . "/" . $pos . "'>" . $word . "</span>";
	if ( $cpos == $keyword ) {
	    $html = "<span class='keyword'>$html</span>";
	}
	if ( $cpos == $target ) {
	    $html = "<span class='target'>$html</span>";
	}
	push @html, $html;
    }
    return join(" ", @html);
}


sub display_context{
    my ($data) = @_;
    my $sentid = param("sentence_id");
    my $sid = $data->get_attribute("s_id");
    my $ps;
    $sentid =~ s/\s+/ /g;
    $data->{"cache"}->retrieve(param("id"));
    my @ranges = $data->{"cqp"}->dump(param("id"));
    foreach my $range (@ranges){
	my ($s, $e, $t, $k) = @$range;
	my $p;
	my $id = $sid->cpos2struc2str($s);
	next unless($id eq $sentid);
	my ($cs, $ce, $ellip_start, $ellip_end) = &context($data, $s, $e, "5s");
	$id =~ s/-/&nbsp;/g;
	$p->{"pre"} = &format($data, $cs, $s - 1, $t, $k);
	$p->{"kwic"} = &format($data, $s, $e, $t, $k);
	$p->{"post"} = &format($data, $e + 1, $ce, $t, $k);
	push(@$ps, $p);
    }
    return $ps;
}


sub escapeHTML {
    $_[0] =~ s/&/&amp;/g;
    $_[0] =~ s/</&lt;/g;
    $_[0] =~ s/>/&gt;/g;
    $_[0] =~ s/'/&apos;/g;
    $_[0] =~ s/"/&quot;/g;
    return $_[0];
}

1;