package Pareidoscope;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use Fcntl ':flock';

use data;

our $VERSION = '0.8.1';
my $data;

hook 'before' => sub {
    database->sqlite_create_function( "rmfile", 1, sub { unlink map( "public/cache/$_", @_ ); } );
    database->sqlite_create_function( "logquery", 3, sub { open( OUT, ">>:encoding(utf8)", config->{query_log} ) or die("Cannot open query log: $!"); flock( OUT, LOCK_EX ); print OUT join( "\t", @_ ), "\n"; flock( OUT, LOCK_UN ); close(OUT) or die("Cannot close query log: $!"); } );
    $data = data->new();
    my $params = params;
    $params->{"corpus"} = config->{"corpora"}->[0]->{"corpus"} unless ( defined( $params->{"corpus"} ) );
    $data->init_corpus( param("corpus") );
};

hook 'before_template' => sub {
    my $tokens = shift;
    $tokens->{"version"} = $VERSION;

    # URLs
    $tokens->{"home_url"}                  = uri_for("/");
    $tokens->{"help_url"}                  = uri_for("/help");
    $tokens->{"about_url"}                 = uri_for("/about");
    $tokens->{"change_corpus_url"}         = uri_for("/change_corpus");
    $tokens->{"word_form_query_url"}       = uri_for("/word_form_query");
    $tokens->{"lemma_query_url"}           = uri_for("/lemma_query");
    $tokens->{"complex_query_token_url"}   = uri_for("/complex_query_token");
    $tokens->{"complex_query_chunk_url"}   = uri_for("/complex_query_chunk");
    $tokens->{"word_form_results_url"}     = uri_for("/results/word_form_query");
    $tokens->{"lemma_results_url"}         = uri_for("/results/lemma_query");
    $tokens->{"complex_query_results_url"} = uri_for("/results/complex_query");

    # Corpus
    $tokens->{"url_args"}->{"corpus"} = param("corpus");
};

get '/' => sub {
    debug( "corpus=" . param("corpus") );
    template('home');
};

get '/help' => sub {
    template('help');
};

get '/about' => sub {
    template('about');
};

get '/change_corpus' => sub {
    my $beautify = sub { $_[0] = reverse $_[0]; $_[0] =~ s/(\d{3})(?=\d)/$1,/g; return scalar( reverse $_[0] ); };
    my $yesno = sub { return $_[0] ? "yes" : "no" };
    my @corpora = map( {
            "corpus"    => $_->{"corpus"},
            "name"      => $_->{"display_name"},
            "tokens"    => $beautify->( $_->{"tokens"} ),
            "sentences" => $beautify->( $_->{"sentences"} ),
            "tagset"    => $_->{"tagset"},
            "chunks"    => $yesno->( $_->{"chunk_ngrams"} ),
            "subgraphs" => $yesno->( $_->{"subgraphs"} )
        },
        grep( $_->{"available"}, @{ config->{"corpora"} } ) );
    template( 'change_corpus', { "corpora" => \@corpora } );
};

get '/word_form_query' => sub {
    template(
        'word_form_query',
        {   "word_classes" => [ "", sort keys %{ config->{"tagsets"}->{ $data->{"active"}->{"tagset"} } } ],
            "pos_tags"     => $data->{"number_to_tag"}
        }
    );
};

get '/lemma_query' => sub {
    template( 'lemma_query', { "word_classes" => [ sort keys %{ config->{"tagsets"}->{ $data->{"active"}->{"tagset"} } } ] } );
};

get '/complex_query_token' => sub {
    template(
        'complex_query_token',
        {   "word_classes" => [ "", sort keys %{ config->{"tagsets"}->{ $data->{"active"}->{"tagset"} } } ],
            "pos_tags"     => $data->{"number_to_tag"}
        }
    );
};

get '/complex_query_chunk' => sub {
    template(
        'complex_query_chunk',
        {   "word_classes" => [ "", sort keys %{ config->{"tagsets"}->{ $data->{"active"}->{"tagset"} } } ],
            "pos_tags"     => $data->{"number_to_tag"},
            "chunk_types"  => $data->{"number_to_chunk"}
        }
    );
};

any [ 'get', 'post' ] => '/results/word_form_query' => sub {
    template('single_item_query_results');
};

any [ 'get', 'post' ] => '/results/lemma_query' => sub {
    template('single_item_query_results');
};

any [ 'get', 'post' ] => '/results/complex_query' => sub {
    template('complex_query_results');
};

# get '/' => sub {

# };

# post '/' => sub {

# };

# any [ 'get', 'post' ] => '/' => sub {

# };

true;
