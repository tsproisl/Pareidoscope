package Pareidoscope;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use Fcntl ':flock';
use Data::Dumper;

use data;
use executequeries;
use visualizegraph;

use version; our $VERSION = qv('0.9');
my $data;

hook 'before' => sub {
    database->sqlite_create_function( 'rmfile', 1, sub { unlink map( "public/cache/$_", @_ ); } );
    database->sqlite_create_function( 'logquery', 3, sub { open( OUT, ">>:encoding(utf8)", config->{query_log} ) or die("Cannot open query log: $!"); flock( OUT, LOCK_EX ); print OUT join( "\t", @_ ), "\n"; flock( OUT, LOCK_UN ); close(OUT) or die("Cannot close query log: $!"); } );
    $data = data->new();
    params->{'corpus'} = config->{'corpora'}->[0]->{'corpus'} unless ( defined( param('corpus') ) );
    params->{'start'} = 0 unless ( defined( param('start') ) );
    $data->init_corpus( param('corpus') );
};

hook 'before_template' => sub {
    my $tokens = shift;
    $tokens->{'version'} = $VERSION;

    # URLs
    $tokens->{'home_url'}                  = uri_for('/');
    $tokens->{'help_url'}                  = uri_for('/help');
    $tokens->{'about_url'}                 = uri_for('/about');
    $tokens->{'change_corpus_url'}         = uri_for('/change_corpus');
    $tokens->{'word_form_query_url'}       = uri_for('/word_form_query');
    $tokens->{'lemma_query_url'}           = uri_for('/lemma_query');
    $tokens->{'complex_query_token_url'}   = uri_for('/complex_query_token');
    $tokens->{'complex_query_chunk_url'}   = uri_for('/complex_query_chunk');
    $tokens->{'word_form_results_url'}     = uri_for('/results/word_form_query');
    $tokens->{'lemma_results_url'}         = uri_for('/results/lemma_query');
    $tokens->{'complex_query_results_url'} = uri_for('/results/complex_query');
    $tokens->{'concordance_url'}           = uri_for('/results/concordance');
    $tokens->{lex_url}                     = uri_for('/results/lexical_ngram_query');
    $tokens->{struc_url}                   = uri_for('/results/structural_ngram_query');
    $tokens->{'display_context_url'}       = uri_for('results/display_context');

    # Corpus
    $tokens->{'url_args'}->{'corpus'} = param('corpus');
    $tokens->{'corpus_name'}          = $data->{'active'}->{'display_name'};
    $tokens->{'chunks'}               = $data->{'active'}->{'chunk_ngrams'};
    $tokens->{'dependencies'}         = $data->{'active'}->{'subgraphs'};
};

get '/' => sub {
    debug( 'corpus=' . param('corpus') );
    template( 'home', { 'current' => uri_for('/') } );
};

get '/help' => sub {
    template( 'help', { 'current' => uri_for('/help') } );
};

get '/about' => sub {
    template( 'about', { 'current' => uri_for('/about') } );
};

get '/change_corpus' => sub {
    my $beautify = sub { $_[0] = reverse $_[0]; $_[0] =~ s/(\d{3})(?=\d)/$1,/g; return scalar( reverse $_[0] ); };
    my $yesno = sub { return $_[0] ? 'yes' : 'no' };
    my @corpora = map( {
            'corpus'    => $_->{'corpus'},
            'name'      => $_->{'display_name'},
            'tokens'    => $beautify->( $_->{'tokens'} ),
            'sentences' => $beautify->( $_->{'sentences'} ),
            'tagset'    => $_->{'tagset'},
            'chunks'    => $yesno->( $_->{'chunk_ngrams'} ),
            'subgraphs' => $yesno->( $_->{'subgraphs'} )
        },
        grep( $_->{'available'}, @{ config->{'corpora'} } ) );
    template(
        'change_corpus',
        {   'corpora' => \@corpora,
            'current' => uri_for('/about')
        }
    );
};

get '/word_form_query' => sub {
    template(
        'word_form_query',
        {   'word_classes' => [ q{}, sort keys %{ config->{'tagsets'}->{ $data->{'active'}->{'tagset'} } } ],
            'pos_tags'     => $data->{'number_to_tag'},
            'current'      => uri_for('/word_form_query'),
        }
    );
};

get '/lemma_query' => sub {
    template(
        'lemma_query',
        {   'word_classes' => [ sort keys %{ config->{'tagsets'}->{ $data->{'active'}->{'tagset'} } } ],
            'current'      => uri_for('/lemma_query'),
        }
    );
};

get '/complex_query_token' => sub {
    template(
        'complex_query_token',
        {   'word_classes' => [ '', sort keys %{ config->{'tagsets'}->{ $data->{'active'}->{'tagset'} } } ],
            'pos_tags'     => $data->{'number_to_tag'},
            'current'      => uri_for('/complex_query_token'),
        }
    );
};

get '/complex_query_chunk' => sub {
    template(
        'complex_query_chunk',
        {   'word_classes' => [ q{}, sort keys %{ config->{'tagsets'}->{ $data->{'active'}->{'tagset'} } } ],
            'pos_tags'     => $data->{'number_to_tag'},
            'chunk_types'  => $data->{'number_to_chunk'},
            'current'      => uri_for('/complex_query_chunk')
        }
    );
};

any [ 'get', 'post' ] => '/results/word_form_query' => sub {
    my %vars;
    $vars{'query_type'} = 'Word form query';
    $vars{'current'}    = uri_for('/results/word_form_query');
    if ( param('return_type') eq 'pos' || param('return_type') eq 'chunk' ) {
        %vars = ( %vars, %{ &executequeries::single_item_query($data) } );
        template( 'single_item_query_results', \%vars );
    }
    elsif ( param('return_type') eq 'dep' ) {
        ...;
    }
};

any [ 'get', 'post' ] => '/results/lemma_query' => sub {
    my %vars;
    $vars{'query_type'} = 'Lemma query';
    $vars{'current'}    = uri_for('/results/lemma_query');
    %vars = ( %vars, %{ &executequeries::single_item_query($data) } );
    if ( param('return_type') eq 'pos' || param('return_type') eq 'chunk' ) {
        %vars = ( %vars, %{ &executequeries::single_item_query($data) } );
        template( 'single_item_query_results', \%vars );
    }
    elsif ( param('return_type') eq 'dep' ) {
        ...;
    }
};

any [ 'get', 'post' ] => '/results/complex_query' => sub {
    my %vars;
    $vars{'current'} = uri_for('/results/complex_query');
    %vars = %{ &executequeries::ngram_query($data) };
    template( 'complex_query_results', \%vars );
};

get '/results/concordance' => sub {
    my %vars;
    $vars{'current'} = uri_for('/results/concordance');
    %vars = ( %vars, %{ &executequeries::cqp_query($data) } );
    template( 'kwic', \%vars );
};

get '/results/display_context' => sub {
    my %vars;
    $vars{'current'} = uri_for('/results/display_context');
    $vars{'ps'}      = &kwic::display_context($data);
    template( 'context_display', \%vars );
};

get '/results/lexical_ngram_query' => sub {
    my %vars;
    $vars{'current'} = uri_for('/results/lexical_ngram_query');
    %vars = ( %vars, %{ &executequeries::lexn_query($data) } );
    template( 'lexical_query_results', \%vars );
};

any [ 'get', 'post' ] => '/results/structural_ngram_query' => sub {
    my %vars;
    $vars{'current'} = uri_for('/results/structural_ngram_query');
    %vars = ( %vars, %{ &executequeries::strucn_query($data) } );
    template( 'complex_query_results', \%vars );
};

get '/visualization/graph' => sub {
    visualizegraph::visualize_graph($data);
};

# get '/' => sub {

# };

# post '/' => sub {

# };

# any [ 'get', 'post' ] => '/' => sub {

# };

1;
