package data;

use Dancer ':syntax';

use DBI;

use CWB;
use CWB::CL;
use CWB::CQP;
use CWB::Web::Cache;

sub new {
    my $invocant = shift;
    my ($cgi)    = @_;
    my $class    = ref($invocant) || $invocant;
    my $self = {};

    #-----------
    # START CQP
    #-----------
    # incurs moderate overhead for CGI scripts that do not use CQP
    $self->{"cqp"} = new CWB::CQP;
    croak("Can't start CQP backend.") unless ( defined( $self->{"cqp"} ) );

    # prints HTML page with error message
    $self->{"cqp"}->set_error_handler( \&cqp_error_handler );

    # set non-standard registry directory
    $self->{"cqp"}->exec( "set Registry '" . config->{"registry"} . "'" );

    #---------------------
    # CREATE CACHE OBJECT
    #---------------------
    $self->{"cache"} = new CWB::Web::Cache -cqp => $self->{"cqp"}, -cachedir => config->{"cqp_cache"}, -cachesize => config->{"cache_size"}, -cachetime => config->{"cache_expire"};

    #----------------------
    # CREATE CORPUS HANDLE
    #----------------------
    # cache requested attribute handles ($Attributes{$name})
    # set non-standard registry directory
    $CWB::CL::Registry = config->{"registry"};

    bless( $self, $class );
    return $self;
}

sub cqp_error_handler {
    error( "CQP error: " . join( "\n", @_ ) );
}

sub init_corpus {
    my ( $self, $corpus ) = @_;
    my @corpora = grep( $_->{"corpus"} eq $corpus, @{ config->{"corpora"} } );
    error("Unknown corpus: $corpus") unless ( @corpora == 1 );
    $self->{"active"} = shift @corpora;
    $self->{"dbh"} = DBI->connect( "dbi:SQLite:" . $self->{"active"}->{"database"} ) or die("Cannot connect: $DBI::errstr");
    $self->{"dbh"}->do("PRAGMA foreign_keys = ON");

    # tags -> numbers
    my $fetchpos = $self->{"dbh"}->prepare(qq{SELECT gramid, grami FROM gramis});
    $fetchpos->execute();
    while ( my ( $gramid, $grami ) = $fetchpos->fetchrow_array ) {
        $self->{"number_to_tag"}->[$gramid] = $grami;
        $self->{"tag_to_number"}->{$grami} = $gramid;
    }
    $fetchpos->finish();

    # chunks -> numbers
    if ( $self->{"active"}->{"chunk_ngrams"} ) {
        my $fetch_chunk = $self->{"dbh"}->prepare(qq{SELECT chunkid, chunk FROM chunks});
        $fetch_chunk->execute();
        while ( my ( $chunkid, $chunk ) = $fetch_chunk->fetchrow_array ) {
            $self->{"number_to_chunk"}->[$chunkid] = $chunk;
            $self->{"chunk_to_number"}->{$chunk} = $chunkid;
        }
        $fetch_chunk->finish();
    }

    # corpus handle
    $self->{"corpus_handle"} = new CWB::CL::Corpus $self->{"active"}->{"corpus"};
    croak( "Error: can't open corpus " . $self->{"active"}->{"corpus"} . ", aborted." ) unless ( defined( $self->{"corpus_handle"} ) );
}

sub DESTROY {
    my ($self) = @_;
    $self->{"dbh"}->disconnect();
    undef( $self->{"dbh"} );
    undef( $self->{"cqp"} );
    undef( $self->{"cache"} );
    undef( $self->{"corpus_handle"} );
}

1;
