package config;

use warnings;
use strict;

#open(STDERR,">$0.debug");

use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Encode;
use Fcntl ':flock';
use URI::Escape;

use Data::Dumper;

use lib "/srv/www/homepages/tsproisl/pareidoscope/local/lib/perl/5.10.1";
use lib "/srv/www/homepages/tsproisl/pareidoscope/local/share/perl/5.10.1";

use CWB;
use CWB::CL;
use CWB::CQP;
use CWB::Web::Cache;
use DBI;

# config for:
#
# tagsets (tags, word classes)
# corpus workbench
# databases
# corpora

sub new {
    my $invocant = shift;
    my ($cgi) = @_;
    my $class = ref($invocant) || $invocant;
    # read conf file
    if (my $err = read_conf_file("pareidoscope.conf")) {
	croak($err);
    }
    my $self = {
	"version" => "0.8.1",
	"corpora" => [@CONF::corpora],
	"word_classes_to_tags" => {%CONF::word_classes_to_tags},
	"tags_to_word_classes" => {%CONF::tags_to_word_classes},
	"tags_to_numbers" => {},
	"numbers_to_tags" => [],
	"chunks_to_numbers" => {},
	"numbers_to_chunks" => [],
	"cache_dbh" => undef,
	"ngrams_dbh" => undef,
	"cqp" => undef,
	"cache" => undef,
	"attributes" => {},
	"corpus_handle" => undef,
	# CGI parameters
	"params" => {},
	#
	"active" => undef,
	"dbh" => undef,
	"chunk_dbh" => undef
    };
    @{$self}{keys %CONF::paths_and_cache} = values %CONF::paths_and_cache;

    #---------------------------
    # CONNECT TO CACHE DATABASE
    #---------------------------
    $self->{"cache_dbh"} = DBI->connect( "dbi:SQLite:" . $self->{"cache_database"}) or die("Cannot connect: $DBI::errstr");
    $self->{"cache_dbh"}->do("SELECT icu_load_collation('en_GB', 'BE')");
    $self->{"cache_dbh"}->do("PRAGMA foreign_keys = ON");
    #$self->{"cache_dbh"}->do("PRAGMA cache_size = 50000");
    $self->{"cache_dbh"}->sqlite_create_function("rmfile", 1, sub {unlink map("user_data/$_", @_);});
    $self->{"cache_dbh"}->sqlite_create_function("logquery", 3, sub {open(OUT, ">>:encoding(utf8)", $self->{"query_log"}) or die("Cannot open query log: $!"); flock(OUT,LOCK_EX); print OUT join("\t", @_), "\n"; flock(OUT,LOCK_UN); close(OUT) or die("Cannot close query log: $!");});

    #-----------
    # START CQP
    #-----------
    # incurs moderate overhead for CGI scripts that do not use CQP
    $self->{"cqp"} = new CWB::CQP;
    croak "Error: Can't start CQP backend." unless(defined($self->{"cqp"}));
    # prints HTML page with error message
    $self->{"cqp"}->set_error_handler(\&cqp_error_handler);
    # set non-standard registry directory
    $self->{"cqp"}->exec("set Registry '" . $self->{"registry"} . "'") if(defined($self->{"registry"}));

    #---------------------
    # CREATE CACHE OBJECT
    #---------------------
    $self->{"cache"} = new CWB::Web::Cache -cqp => $self->{"cqp"}, -cachedir => $self->{"cache_dir"}, -cachesize => $self->{"cache_size"}, -cachetime => $self->{"cache_expire"};
    #----------------------
    # CREATE CORPUS HANDLE
    #----------------------
    # cache requested attribute handles ($Attributes{$name})
    # set non-standard registry directory
    $CWB::CL::Registry = $self->{"registry"} if(defined($self->{"registry"}));

    #----------------------
    # FETCH CGI PARAMETERS
    #----------------------
    my (%p_q, %p_t);
    if(defined($cgi->param('m'))){
	$self->{"params"}->{"m"} = $cgi->param('m');
    }elsif(defined($cgi->url_param('m'))){
	$self->{"params"}->{"m"} = $cgi->url_param('m');
    }else{
	$self->{"params"}->{"m"} = "o";
    }
    $self->{"params"}->{"s"} = $cgi->param('s') if(defined($cgi->param('s')));
    # c: corpus
    # rt: return type (pos or chunk)
    # f*: filter
    # dt: display type (split or lump)
    # q: cqp query
    foreach my $param qw(id flen frel ftag fwc fpos fch start c rt dt q){
	$self->{"params"}->{$param} = $cgi->param($param) if(defined($cgi->param($param)));
	$self->{"params"}->{$param} = $cgi->url_param($param) if(defined($cgi->url_param($param)) and not defined($self->{"params"}->{$param}));
    }
    $self->{"params"}->{"start"} = 0 unless(defined($self->{"params"}->{"start"}));
    $self->{"params"}->{"c"} = $self->{"corpora"}->[0]->{"corpus"} unless(defined($self->{"params"}->{"c"}));

    # fetch q1--q9 and t1--t9
    # t:  token
    # tt: token type (wf [word form] or l [lemma])
    # p:  part-of-speech
    # w:  word class
    # ct:  chunk type (adjp, ...)
    # h:  head (a token)
    # ht: head type (wf or l)
    # i: ignore case
    foreach my $letter qw(ct h ht i p t tt w){
	my ($p1, $p2, $p3, $p4, $p5, $p6, $p7, $p8, $p9);
	my %p;
	for(my $i = 1; $i <= 9; $i++){
	    my $x = "$letter$i";
	    eval "\$p$i = \$cgi->param('$x') if(\$cgi->param('$x'))";
	}
	%p = map(($_, eval "return \$p$_"), (1 .. 9));
	$self->{"params"}->{$letter} = \%p;
    }
    bless($self, $class);
    return $self;
}


sub init_corpus {
    my ($self, $corpus) = @_;
    my @corpora = grep($_->{"corpus"} eq $corpus, @{$self->{"corpora"}});
    croak("Unknown corpus: $corpus") unless(@corpora == 1);
    $self->{"active"} = shift @corpora;
    $self->{"dbh"} = DBI->connect( "dbi:SQLite:" . $self->{"active"}->{"database"}) or die("Cannot connect: $DBI::errstr");
    $self->{"dbh"}->do("SELECT icu_load_collation('en_GB', 'BE')");
    $self->{"dbh"}->do("PRAGMA foreign_keys = ON");
    if($self->{"active"}->{"chunk_db"}){
	$self->{"chunk_dbh"} = DBI->connect( "dbi:SQLite:" . $self->{"active"}->{"chunk_db"}) or die("Cannot connect: $DBI::errstr");
	$self->{"chunk_dbh"}->do("SELECT icu_load_collation('en_GB', 'BE')");
	$self->{"chunk_dbh"}->do("PRAGMA foreign_keys = ON");
    }
    # tags -> numbers
    my $fetchpos = $self->{"dbh"}->prepare(qq{SELECT gramid, grami FROM gramis});
    $fetchpos->execute();
    while(my ($gramid, $grami) = $fetchpos->fetchrow_array){
	$self->{"number_to_tag"}->[$gramid] = $grami;
        $self->{"tag_to_number"}->{$grami} = $gramid;
    }
    $fetchpos->finish();
    # chunks -> numbers
    if($self->{"active"}->{"chunk_db"}){
	my $fetch_chunk = $self->{"chunk_dbh"}->prepare(qq{SELECT chunkid, chunk FROM chunks});
	$fetch_chunk->execute();
	while(my ($chunkid, $chunk) = $fetch_chunk->fetchrow_array){
	    $self->{"number_to_chunk"}->[$chunkid] = $chunk;
	    $self->{"chunk_to_number"}->{$chunk} = $chunkid;
	}
	$fetch_chunk->finish();
    }
    # corpus handle
    $self->{"corpus_handle"} = new CWB::CL::Corpus $self->{"active"}->{"corpus"};
    croak("Error: can't open corpus " . $self->{"active"}->{"corpus"} . ", aborted.") unless(defined($self->{"corpus_handle"}));
}


sub DESTROY {
    my ($self) = @_;
    $self->{"dbh"}->disconnect();
    $self->{"cache_dbh"}->disconnect();
    $self->{"chunk_dbh"}->disconnect() if($self->{"active"}->{"chunk_db"});
    undef($self->{"dbh"});
    undef($self->{"cache_dbh"});
    undef($self->{"chunk_dbh"});
    undef($self->{"cqp"});
    undef($self->{"cache"});
    undef($self->{"corpus_handle"});
    undef($self->{"params"});
}


# $att_handle = config::get_attribute($name);
#   - get CL attribute handle for specified attribute $name (returns CWB::CL::Attribute object)
sub get_attribute{
  croak 'Usage:  $att_handle = $config->get_attribute($name);' unless(scalar(@_) == 2);
  my ($self, $name) = @_;
  # retrieve attribute handle from cache
  return $self->{"attributes"}->{$name} if(exists($self->{"attributes"}->{$name}));
  # try p-attribute first ...
  my $att = $self->{"corpus_handle"}->attribute($name, "p");
  # ... then try s-attribute
  $att = $self->{"corpus_handle"}->attribute($name, "s") unless(defined($att));
  # ... finally try a-attribute
  $att = $self->{"corpus_handle"}->attribute($name, "a") unless(defined($att));
  croak "Can't open attribute ". $self->{"corpus"} . ".$name, sorry." unless(defined($att));
  # store attribute handle in cache
  $self->{"attributes"}->{$name} = $att;
  return $att;
}


sub read_conf_file {
    my $file = shift;
    our $err;
    {   # Put config data into a separate namespace
        package CONF;
	use warnings;
	use strict;
	
        # Process the contents of the config file
        my $rc = do($file);

        # Check for errors
        if ($@) {
            $::err = "ERROR: Failure compiling '$file' - $@";
        } elsif (! defined($rc)) {
            $::err = "ERROR: Failure reading '$file' - $!";
        } elsif (! $rc) {
            $::err = "ERROR: Failure processing '$file'";
        }
    }

    return ($err);
}


#----------------
# ERROR HANDLERS
#----------------
sub error{
    my ($heading, @lines) = @_;
    my $cgi = new CGI;
    print
	$cgi->header(-type=>'text/html', -charset=>'utf-8',),
	# meta info
	$cgi->start_html(-title=>'Pareidoscope: Error',
			 -encoding => 'utf-8',
			 -meta => {'author'=>'Thomas Proisl',
				   'keywords'=>'lexicogrammar, lexico-grammar, collocation, collocations, construction, constructions, valency',
				   'description'=>'Pareidoscope &ndash; a reasearch tool for investigating patterns of lexicogrammatical interaction'},
			 -style => {'src'=>'/Envision12/Envision.css'});
    print "<h2>$heading</h2>", "<pre>", join("\n", @lines), "\n</pre>";
    print $cgi->end_html;
}

sub cqp_error_handler{
    &error("Query execution error:", @_);
}


#-------------
# KEEP STATES
#-------------

sub keep_states_hidden {
    my ($self, $cgi, $overrideref, @keep) = @_;
    my %keep = map(($_, 1), (@keep, keys %$overrideref));
    foreach my $param (keys %keep) {
	next unless(defined($self->{"params"}->{$param}) or $overrideref->{$param});
	my $print = sub {
	    my ($key, $suffix, $value) = @_;
	    $key .= $suffix if(defined($suffix));
	    $value = $overrideref->{$key} if(defined($overrideref->{$key}));
	    $value = "" unless(defined($value));
	    $cgi->param($key, $value);
	    print $cgi->hidden($key, $value);
	};
	if(ref($self->{"params"}->{$param}) eq "HASH"){
	    foreach (keys %{$self->{"params"}->{$param}}){
		$print->($param, $_, $self->{"params"}->{$param}->{$_}) if(defined($self->{"params"}->{$param}->{$_}) and $self->{"params"}->{$param}->{$_} ne "");
	    }
	} else {
	    $print->($param, undef, $self->{"params"}->{$param});
	}
    }
}


sub keep_states_listref_of_hashrefs {
    my ($self, $overrideref, @keep) = @_;
    my %keep = map(($_, 1), (@keep, keys %$overrideref));
    my @list;
    foreach my $param (keys %keep) {
	next unless(defined($self->{"params"}->{$param}) or $overrideref->{$param});
	my $add = sub {
	    my ($key, $suffix, $value) = @_;
	    $key .= $suffix if(defined($suffix));
	    $value = $overrideref->{$key} if(defined($overrideref->{$key}));
	    $value = "" unless(defined($value));
	    return {"name" => $key, "value" => $value};
	};
	if(ref($self->{"params"}->{$param}) eq "HASH"){
	    foreach (keys %{$self->{"params"}->{$param}}){
		push(@list, $add->($param, $_, $self->{"params"}->{$param}->{$_})) if(defined($self->{"params"}->{$param}->{$_}) and $self->{"params"}->{$param}->{$_} ne "");
	    }
	} else {
	    push(@list, $add->($param, undef, $self->{"params"}->{$param}));
	}
    }
    return [@list];
}


sub keep_states_href {
    my ($self, $overrideref, @keep) = @_;
    my %keep = map(($_, 1), (@keep, keys %$overrideref));
    my @href;
    foreach my $param (keys %keep) {
	next unless(defined($self->{"params"}->{$param}) or $overrideref->{$param});
	my $add = sub {
	    my ($key, $suffix, $value) = @_;
	    $key .= $suffix if(defined($suffix));
	    $value = $overrideref->{$key} if(defined($overrideref->{$key}));
	    $value = "" unless(defined($value));
	    return "$key=" . URI::Escape::uri_escape($value);
	};
	if(ref($self->{"params"}->{$param}) eq "HASH"){
	    foreach (keys %{$self->{"params"}->{$param}}){
		push(@href, $add->($param, $_, $self->{"params"}->{$param}->{$_})) if(defined($self->{"params"}->{$param}->{$_}) and $self->{"params"}->{$param}->{$_} ne "");
	    }
	} else {
	    push(@href, $add->($param, undef, $self->{"params"}->{$param}));
	}
    }
    return join("&", @href);
}



#################
# OLD FUNCTIONS #
#################





1;
