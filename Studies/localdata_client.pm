package localdata_client;

use Carp;
use IO::Socket;
use Data::Dumper;
use POSIX qw();
use Time::HiRes;
use MIME::Base64 qw();

sub init {
    my $invocant = shift;
    my ($dir, @connection_data) = @_;
    my $class = ref($invocant) || $invocant;
    my @con_subset;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Purity = 1;
    foreach my $con (@connection_data){
	push(@con_subset, $con) if(&check_server(@$con));
	last if(scalar(@con_subset) >= 4);
    }
    croak("All background servers seem to be gone. Please try again later.") unless(@con_subset);
    my $self = {"dir" => $dir, "con" => \@con_subset};
    bless($self, $class);
    return $self;
}


sub check_server {
    my ($remote_host, $remote_port, $local_port) = @_;
    my $socket = IO::Socket::INET->new(PeerAddr  => $remote_host,
                                       PeerPort  => 4878,
                                       #LocalPort => $local_port,
                                       Proto     => "tcp",
                                       ReuseAddr => 1,
                                       Timeout   => 5,
                                       Type      => SOCK_STREAM)
        or return 0;
    my $now = Time::HiRes::time;
    print $socket "chkpng:$now\n";
    chomp(my $then = <$socket>);
    close $socket;
    return sprintf("%.3f", (Time::HiRes::time - $now) * 1000);
}


sub DESTROY {
    my ($self) = @_;
    #print {$self->{"socket"}} ("fini\n");
    #close($self->{"socket"});
    #foreach my $con (@{$self->{"con"}}){
	#close($con);
    #}
    undef($self);
}


sub serialize {
    my ($self, $ngref) = @_;
    my @queue;# :shared;
    foreach my $packed_ngram (sort {length($a) <=> length($b) or $a cmp $b} keys %$ngref){
	my $ngram = unpack("H*", $packed_ngram);
	foreach my $position (keys %{$ngref->{$packed_ngram}}){
	    foreach my $match_length (keys %{$ngref->{$packed_ngram}->{$position}}){
		#push(@queue, [$ngram, $position, $match_length, $ngref->{$packed_ngram}->{$position}->{$match_length}]);
		my $frequency = scalar(keys %{$ngref->{$packed_ngram}->{$position}->{$match_length}});
		push(@queue, [$ngram, $position, $match_length, $frequency]) if ($frequency >= param("threshold"));
	    }
	}
    }
    return \@queue;
}


sub add_freq_and_am {
    my ($self, $queueref, $r1, $n, $dbname) = @_;
    my %ngret;
    my @sockets ;
    my $queue_length = scalar(@$queueref);
    return if($queue_length == 0);
    #my $dbh = DBI->connect("dbi:SQLite:" . config->{"user_data"} . "/$dbname") or croak("Cannot connect: $DBI::errstr");
    my $dbh = DBI->connect("dbi:SQLite:$dbname") or croak("Cannot connect: $DBI::errstr");
    $dbh->do("PRAGMA encoding = 'UTF-8'");
    $dbh->do("PRAGMA cache_size = 50000");
    my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, mlen, o11, c1, am) VALUES (?, ?, ?, ?, ?, ?, ?)});
    my $cons = scalar(@{$self->{"con"}});
    my %specifics;
    # if(param("return_type") eq "pos"){
    # 	%specifics = ("prefix" => "ngrams");
    # }
    # elsif(param("return_type") eq "chunk"){
    # 	%specifics = ("prefix" => "chunks");
    # }
    $specifics{'prefix'} = 'subgraphs';
    foreach my $con (@{$self->{"con"}}){
	my ($remote_host, $remote_port, $local_port) = @$con;
	croak("I need some information to connect to the remote server") unless(defined($remote_host) and defined($remote_port) and defined($local_port));
	my $socket = IO::Socket::INET->new(PeerAddr  => $remote_host,
					   PeerPort  => $remote_port,
					   #LocalPort => $local_port,
					   Proto     => "tcp",
					   ReuseAddr => 1,
					   Type      => SOCK_STREAM)
	    or croak "Couldn't connect to $remote_host:$remote_port : $@\n";
	print $socket "dir:" . $self->{"dir"} . "\n";
	print $socket "fil:" . $specifics{"prefix"} . "\n";
	push(@sockets, $socket);
    }
    #print STDERR "connected to sockets\n";
    my $block_size = 40000;
    my $per_con = $queue_length > $block_size ? POSIX::ceil($queue_length / POSIX::ceil($queue_length / $block_size)) : $queue_length;
    my $per_message = POSIX::ceil($per_con / POSIX::ceil($per_con / $block_size));
    my @results;
    while(@$queueref){
	foreach my $socket (@sockets){
	    last unless(@$queueref);
	    my @localresults;
	    my $size = @$queueref > $per_message ? $per_message : @$queueref;
	    my @localqueue = splice(@$queueref, 0, $size);
	    #my $workingqueue = "gngf:$r1:$n:," . join(",", map(MIME::Base64::encode(pack("H*", $_->[0]), "") . ":" . $_->[3], @localqueue));
	    my $workingqueue = "gngf:$r1:$n:," . join(",", map(MIME::Base64::encode($_->[0], "") . ":" . $_->[3], @localqueue));
	    print $socket $workingqueue . "\n";
	    foreach my $record (@localqueue){
		my $marked_ngram = $record->[0];
		my $position = $record->[1];
		#my $match_length = $record->[2];
		#$marked_ngram =~ m/^((?:[0-9a-f]{2}){$position})((?:[0-9a-f]{2}){$match_length})((?:[0-9a-f]{2})*)$/;
		#my ($pre, $match, $post) = ($1, $2, $3);
		#$marked_ngram = $pre . "<" . $match . ">". $post;
		push(@localresults, [$marked_ngram, $position, $match_length, $record->[3]]);
	    }
	    push(@results, [$socket, \@localresults]);
	}
	while(@results){
	    my $result = shift(@results);
	    my ($socket, $localresultsref) = @$result;
	    my $line = <$socket>;
	    chomp($line);
	    my @line = split(",", $line);
	    $dbh->do(qq{BEGIN TRANSACTION});
	    foreach my $wr (@$localresultsref){
		my $c1 = shift(@line);
		my $g2 = shift(@line);
		croak("NICHT DEFINIERT: $c1, $g2") unless(defined($c1) and defined($g2));
		$insert_result->execute($dbname, @$wr, $c1, $g2);
	    }
	    $dbh->do(qq{COMMIT});
	}
    }
    foreach my $socket (@sockets){
	print $socket "fini\n";
	close($socket);
    }
    $dbh->disconnect();
    undef($dbh);
}

1;
