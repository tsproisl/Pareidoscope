#!/usr/bin/perl

package localdata;

use warnings;
use strict;

use Fcntl ':flock';
use Storable;
use POSIX qw();
use Data::Dumper;
use MIME::Base64 qw();

sub init {
    my $invocant = shift;

    # $file: ngrams oder chunks
    my ( $dir, $file ) = @_;
    my $class = ref($invocant) || $invocant;
    my @ngds;
    my @ngramidxs;
    my @indices = $file eq "subgraph" ? ( 1 .. 5 ) : ( 1 .. 9 );

    # Subgraphs: $ngds[($i ** 2) * 2]
    for my $i (@indices) {
        open( $ngds[$i], "<:raw", "$dir/$file" . sprintf( "%02d", $i ) . ".dat" ) or die( "Cannot open file '$dir/$file" . sprintf( "%02d", $i ) . ".dat': $!" );
        $ngramidxs[$i] = Storable::retrieve( "$dir/$file" . sprintf( "%02d", $i ) . ".idx" );
    }
    my $self = {
        "NGDs"         => \@ngds,
        "records"      => [],
        "firstrecords" => [],
        "lastrecords"  => [],
        "ngramidxs"    => \@ngramidxs,
	"file"         => $file
    };
    bless( $self, $class );
    return $self;
}

sub fini {
    my ($self) = @_;
    foreach my $ngd ( @{ $self->{"NGDs"} } ) {
        close($ngd) or die("Cannot close file: $!");
    }
}

sub get_ngram_freq {
    my ( $self, $ngram ) = @_;
    my $length = length($ngram);
    my $index = $self->{"file"} eq "subgraph" ? sqrt($length / 2) : $length;
    return $self->scan_cached_records($ngram) if ( $self->{"records"}->[$index] and ( $self->{"firstrecords"}->[$index] le $ngram ) and ( $self->{"lastrecords"}->[$index] ge $ngram ) );
    my $max      = scalar( @{ $self->{"ngramidxs"}->[$index] } ) / 2 - 1;
    my $maxindex = $max;
    my $minindex = 0;
    my $success  = -1;
    my $recordsize;

    while ( $success < 0 and $minindex <= $maxindex ) {
        my $middle = POSIX::floor( $minindex + ( ( $maxindex - $minindex ) / 2 ) );
        if ( $ngram lt $self->{"ngramidxs"}->[$index]->[ $middle * 2 ] ) {
            $maxindex = $middle - 1;
            next;
        }
        if ( $middle == $max ) {
            $success = $self->{"ngramidxs"}->[$index]->[ ( $middle * 2 ) + 1 ];
            flock( $self->{"NGDs"}->[$index], LOCK_EX );
            seek( $self->{"NGDs"}->[$index], 0, 2 ) or die("Error while seeking index file");
            $recordsize = tell( $self->{"NGDs"}->[$index] ) - $success;
            flock( $self->{"NGDs"}->[$index], LOCK_UN );
            next;
        }
        if ( $ngram ge $self->{"ngramidxs"}->[$index]->[ ( $middle + 1 ) * 2 ] ) {
            $minindex = $middle + 1;
            next;
        }
        $success    = $self->{"ngramidxs"}->[$index]->[ ( $middle * 2 ) + 1 ];
        $recordsize = $self->{"ngramidxs"}->[$index]->[ ( ( $middle + 1 ) * 2 ) + 1 ] - $success;
    }

    die( "N-gram not found: hex " . join( " ", unpack( "H*", $ngram ) ) . "\n" ) if ( $success < 0 );
    my $record;
    flock( $self->{"NGDs"}->[$index], LOCK_EX );
    seek( $self->{"NGDs"}->[$index], $success, 0 ) or die("Error while seeking index file");
    my $chrs = read( $self->{"NGDs"}->[$index], $record, $recordsize );
    flock( $self->{"NGDs"}->[$index], LOCK_UN );
    $self->{"records"}->[$index] = $record;
    ( $self->{"firstrecords"}->[$index] ) = substr( $self->{"records"}->[$index], 0, $length );
    ( $self->{"lastrecords"}->[$index] ) = substr( $self->{"records"}->[$index], -( $length + 4 ), $length );
    die( "Error while processing n-grams: hex " . join( " ", grep( $_ > 0, unpack( "H*", $self->{"firstrecords"}->[$index] ) ) ) . " > hex " . join( " ", grep( $_ > 0, unpack( "H*", $ngram ) ) ) ) unless ( $self->{"firstrecords"}->[$index] le $ngram );
    die( "Error while processing n-grams: hex " . join( " ", grep( $_ > 0, unpack( "H*", $self->{"lastrecords"}->[$index] ) ) ) . " < hex " . join( " ", grep( $_ > 0, unpack( "H*", $ngram ) ) ) ) unless ( $self->{"lastrecords"}->[$index] ge $ngram );
    return $self->scan_cached_records($ngram);
}

sub scan_cached_records {
    my ( $self, $ngram ) = @_;
    my $length   = length($ngram);
    my $index = $self->{"file"} eq "subgraph" ? sqrt($length / 2) : $length;
    my $maxindex = length( $self->{"records"}->[$index] ) / ( $length + 4 ) - 1;
    my $minindex = 0;
    my $success  = -1;
    while ( $success < 0 and $minindex <= $maxindex ) {
        my $middle = POSIX::floor( $minindex + ( ( $maxindex - $minindex ) / 2 ) );
        my $start = $middle * ( $length + 4 );
        my $record = substr( $self->{"records"}->[$index], $start, $length );
        if ( $ngram eq $record ) {
            $success = unpack( "L", substr( $self->{"records"}->[$index], $start + $length, 4 ) );
            return ($success);
        }
        elsif ( $ngram lt $record ) {
            $maxindex = $middle - 1;
        }
        else {
            $minindex = $middle + 1;
        }
    }
    die("Error while reading n-grams") if ( $success < 0 );
}

1;

package main;

#!/usr/bin/perl

use warnings;
use strict;

use threads;
use IO::Socket;
use statistics;

my $server_port = shift(@ARGV);
$server_port = 4878 unless ( defined($server_port) and sprintf( "%d", $server_port ) eq $server_port );

my $server = IO::Socket::INET->new(
    LocalPort => $server_port,
    Type      => SOCK_STREAM,
    ReuseAddr => 1,
    Listen    => 10
) or die("Couldn't be a tcp server on port $server_port : $@");

my $time_to_die = 0;
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub { $time_to_die = 1; };

print "Waiting for clients on port #$server_port.\n";
while ( not $time_to_die ) {
    while ( my $client = $server->accept ) {

        # $client is the new connection
        #print "connection!\n";
        #async(\&handle_connection, $client)->detach;
        my $thread = threads->create( \&handle_connection, $client )->detach;
    }
}

close($server);

sub handle_connection {
    my $socket = shift;
    my $output = shift || $socket;
    my $exit   = 0;
    chomp( my $first = <$socket> );
    if ( substr( $first, 0, 7 ) eq "chkpng:" ) {
        print $output substr( $first, 7 ), "\n";
        return;
    }
    elsif ( substr( $first, 0, 4 ) ne "dir:" ) {
        print $output "Wrong protocol: $first\n";
        return;
    }
    my $dir = substr( $first, 4 );

    # $file
    chomp( my $file_prefix = <$socket> );
    if ( substr( $file_prefix, 0, 4 ) ne "fil:" ) {
        print $output "Wrong protocol: $file_prefix\n";
        return;
    }
    $file_prefix = substr( $file_prefix, 4 );
    my $localdata = localdata->init( $dir, $file_prefix );
    my $lastngram = "";
    my $lastc1    = 0;
    while ( my $input = <$socket> ) {

        #print $input;
        chomp($input);
        if ( $input =~ s/^gngf:(\d+):(\d+):,// ) {
            my $r1 = $1;
            my $n  = $2;
            my @outstring;
            foreach my $pair ( split( /,/, $input ) ) {
                my ( $ngram, $o11 ) = split( /:/, $pair );
                my $c1;
                if ( $ngram eq $lastngram ) {
                    $c1 = $lastc1;
                }
                else {
                    my $packed_ngram = MIME::Base64::decode($ngram);
                    $c1        = $localdata->get_ngram_freq($packed_ngram);
                    $lastngram = $ngram;
                    $lastc1    = $c1;
                }
                my $g2 = &statistics::g( $o11, $r1, $c1, $n );
                push( @outstring, "$c1,$g2" );
            }
            my $outstr = join( ",", @outstring ) . "\n";
            print $output $outstr;
        }
        elsif ( $input eq "fini" ) {
            $localdata->fini();
            $exit = 1;
        }
        else {

            #$exit = 1;
        }
        last if $exit;
    }

    #shutdown($socket, 2);
    #shutdown($output, 2);
}

