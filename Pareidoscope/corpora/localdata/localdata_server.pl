#!/usr/bin/perl

package localdata;

use warnings;
use strict;

use Fcntl ':flock';
use Storable;
use POSIX qw();
use MIME::Base64 qw();

sub init {
    my $invocant = shift;

    # $file: ngrams oder chunks
    my ( $dir, $file ) = @_;
    my $class = ref($invocant) || $invocant;
    my @ngds;
    my @ngramidxs;
    my @indices = $file eq "subgraphs" ? ( 1 .. 5 ) : ( 1 .. 9 );

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
        "file"         => $file,
        "lastsuccess"  => [],
    };
    bless( $self, $class );
    return $self;
}

sub fini {
    my ($self) = @_;
    for ( my $i = 1; $i < @{ $self->{"NGDs"} }; $i++ ) {
        close( $self->{"NGDs"}->[$i] ) or die("Cannot close file: $!");
    }
}

sub get_ngram_freq {
    my ( $self, $ngram ) = @_;
    my $length = length($ngram);
    my $index = $self->{"file"} eq "subgraphs" ? sqrt( $length / 2 ) : $length;

    # print "ngram: " . join(" ", unpack('H*', $ngram)) . ", length: $length, index: $index\n";
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
    $self->{"lastsuccess"}->[$index] = $success;

    # print "index: $index\n";
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
    my $index    = $self->{"file"} eq "subgraphs" ? sqrt( $length / 2 ) : $length;
    my $maxindex = length( $self->{"records"}->[$index] ) / ( $length + 4 ) - 1;
    my $minindex = 0;
    my $success  = -1;
    while ( $success < 0 and $minindex <= $maxindex ) {

        # print "minindex: $minindex, maxindex: $maxindex\n";
        my $middle = POSIX::floor( $minindex + ( ( $maxindex - $minindex ) / 2 ) );
        my $start = $middle * ( $length + 4 );
        my $record = substr( $self->{"records"}->[$index], $start, $length );
        if ( $ngram eq $record ) {
            $success = unpack( "L", substr( $self->{"records"}->[$index], $start + $length, 4 ) );
            return ( $success, ( $self->{"lastsuccess"}->[$index] + $start ) / ( $length + 4 ) );
        }
        elsif ( $ngram lt $record ) {
            $maxindex = $middle - 1;
        }
        else {
            $minindex = $middle + 1;
        }
    }
    die( "Error while reading $index-gram " . join " ", unpack( "H*", $ngram ) ) if ( $success < 0 );
}

sub get_ngram_by_index {
    my ( $self, $position, $index ) = @_;
    my $length = $self->{"file"} eq "subgraphs" ? ( $index**2 ) * 2 : $index;
    my $record;
    flock( $self->{"NGDs"}->[$index], LOCK_EX );
    seek( $self->{"NGDs"}->[$index], $position * ( $length + 4 ), 0 ) or die("Error while seeking index file");
    my $chrs = read( $self->{"NGDs"}->[$index], $record, $length + 4 );
    flock( $self->{"NGDs"}->[$index], LOCK_UN );
    my $ngram = substr $record, 0, $length;
    my $c1 = unpack "L", substr( $record, $length, 4 );
    return ( $c1, $ngram );
}

1;

package main;

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
    my $localdata  = localdata->init( $dir, $file_prefix );
    my $lastngram  = "";
    my $lastc1     = -1;
    my $lastindex  = -1;
    my $lastlength = -1;
    while ( my $input = <$socket> ) {

        #print $input;
        chomp($input);

        # {g}et {n}-{g}ram {f}requency/{i}ndex
        if ( $input =~ s/^(gng[fi]):(\d+):(\d+):,// ) {
            my $mode = $1;
            my $r1   = $2;
            my $n    = $3;
            my @outstring;
            foreach my $pair ( split( /,/, $input ) ) {
                my ( $ngram, $o11 ) = split( /:/, $pair );
                my ( $c1, $index );
                if ( $ngram eq $lastngram ) {
                    $c1    = $lastc1;
                    $index = $lastindex;
                }
                else {
                    my $packed_ngram = MIME::Base64::decode($ngram);
                    ( $c1, $index ) = $localdata->get_ngram_freq($packed_ngram);
                    $lastc1    = $c1;
                    $lastindex = $index;
                    $lastngram = $ngram;

                    # print join " ", unpack( "H*", $packed_ngram ) . "\n";
                }
                if ( $mode eq 'gngf' ) {
                    my $g2 = &statistics::g( $o11, $r1, $c1, $n );
                    push( @outstring, "$c1,$g2" );
                }
                elsif ( $mode eq 'gngi' ) {
                    push( @outstring, "$c1,$index" );
                }
            }
            my $outstr = join( ",", @outstring ) . "\n";
            print $output $outstr;
        }

        # {g}et {n}-{g}ram {b}y {i}ndex
        elsif ( $input =~ s/^gngbi:,// ) {
            my @outstring;
            foreach my $pair ( split /,/, $input ) {
                my ( $index, $length ) = split /:/, $pair;
                my ( $c1, $ngram );
                if ( $index == $lastindex && $length == $lastlength ) {
                    $c1    = $lastc1;
                    $ngram = $lastngram;
                }
                else {
                    my $packed_ngram;
                    ( $packed_ngram, $c1 ) = $localdata->get_ngram_by_index($index);
                    ( $c1, $ngram ) = MIME::Base64::encode( $packed_ngram, $length );
                    $lastngram  = $ngram;
                    $lastc1     = $c1;
                    $lastlength = $length;
                    $lastindex  = $index;
                }
                push( @outstring, "$c1,$ngram" );
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

