package Pareidoscope;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use Fcntl ':flock';

our $VERSION = '0.8.1';

hook 'before' => sub {
    database->sqlite_create_function( "rmfile", 1, sub { unlink map( "public/cache/$_", @_ ); } );
    database->sqlite_create_function( "logquery", 3, sub { open( OUT, ">>:encoding(utf8)", config->{query_log} ) or die("Cannot open query log: $!"); flock( OUT, LOCK_EX ); print OUT join( "\t", @_ ), "\n"; flock( OUT, LOCK_UN ); close(OUT) or die("Cannot close query log: $!"); } );
    my $params = params;
    $params->{"c"} = "foo" unless($params->{"c"});
    $params->{"test"} = "bar" unless($params->{"test"});
};

hook 'before_template' => sub {
    my $tokens = shift;
    $tokens->{version} = $VERSION;
};

get '/' => sub {
    debug("c=" . param("c"));
    debug("d=" . param("d")) if(param("d"));
    debug("test=" . param("test"));
    template('home');
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

get '/complex_query_token_level' => sub {
    template('complex_query_token');
};

get '/complex_query_chunk_level' => sub {
    template('complex_query_chunk');
};

# get '/' => sub {

# };

# post '/' => sub {

# };

# any [ 'get', 'post' ] => '/' => sub {

# };

true;
