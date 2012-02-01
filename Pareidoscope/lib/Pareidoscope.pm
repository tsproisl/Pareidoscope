package Pareidoscope;
use Dancer ':syntax';

use Dancer::Plugin::Database;
use Fcntl ':flock';

our $VERSION = '0.8.1';

hook 'before' => sub {
    database->sqlite_create_function( "rmfile", 1, sub { unlink map( "public/cache/$_", @_ ); } );
    database->sqlite_create_function( "logquery", 3, sub { open( OUT, ">>:encoding(utf8)", config->{query_log} ) or die("Cannot open query log: $!"); flock( OUT, LOCK_EX ); print OUT join( "\t", @_ ), "\n"; flock( OUT, LOCK_UN ); close(OUT) or die("Cannot close query log: $!"); } );
};

get '/' => sub {
    template( 'home', { version => $VERSION } );
};

true;
