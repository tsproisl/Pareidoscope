package Pareidoscope;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use Fcntl ':flock';

our $VERSION = '0.8.1';

hook 'before' => sub {
    database->sqlite_create_function( "rmfile", 1, sub { unlink map( "public/cache/$_", @_ ); } );
    database->sqlite_create_function( "logquery", 3, sub { open( OUT, ">>:encoding(utf8)", config->{query_log} ) or die("Cannot open query log: $!"); flock( OUT, LOCK_EX ); print OUT join( "\t", @_ ), "\n"; flock( OUT, LOCK_UN ); close(OUT) or die("Cannot close query log: $!"); } );
    my $params = params;
    $params->{"c"} = "foo" unless(defined($params->{"c"}));
    $params->{"test"} = "bar" unless($params->{"test"});
};

hook 'before_template' => sub {
    my $tokens = shift;
    $tokens->{"version"} = $VERSION;
    $tokens->{"home_url"} = uri_for("/");
    $tokens->{"help_url"} = uri_for("/help");
    $tokens->{"about_url"} = uri_for("/about");
    $tokens->{"change_corpus_url"} = uri_for("/change_corpus");
    $tokens->{"word_form_query_url"} = uri_for("/word_form_query");
    $tokens->{"lemma_query_url"} = uri_for("/lemma_query");
    $tokens->{"complex_query_token_url"} = uri_for("/complex_query_token");
    $tokens->{"complex_query_chunk_url"} = uri_for("/complex_query_chunk");
};

get '/' => sub {
    debug("c=" . param("c"));
    debug("d=" . param("d")) if(param("d"));
    debug("test=" . param("test"));
    template('home', {url_args => [{name => "x", value => "alpha"}, {name => "y", value => "beta"}, {name => "z", value => "gamma"}]});
};

get '/help' => sub {
    template('help');
};

get '/about' => sub {
    template('about');
};

get '/change_corpus' => sub {
    template('change_corpus');
};

get '/word_form_query' => sub {
    template('word_form_query');
};

get '/lemma_query' => sub {
    template('lemma_query');
};

get '/complex_query_token' => sub {
    template('complex_query_token');
};

get '/complex_query_chunk' => sub {
    template('complex_query_chunk');
};

# get '/' => sub {

# };

# post '/' => sub {

# };

# any [ 'get', 'post' ] => '/' => sub {

# };

true;
