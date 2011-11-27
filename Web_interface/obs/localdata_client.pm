package localdata_client;

use warnings;
use strict;

use threads;
use threads::shared;

use CGI::Carp qw(fatalsToBrowser);
use IO::Socket;
use Data::Dumper;
use POSIX qw();
use Time::HiRes;
use MIME::Base64 qw();

sub init{
    my $invocant = shift;
    my ($dir, $c5, @connection_data) = @_;
    my $class = ref($invocant) || $invocant;
    my @con_subset;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Purity = 1;
    foreach my $con (@connection_data){
	push(@con_subset, $con) if(&check_server(@$con));
	last if(scalar(@con_subset) >= 4);
    }
    croak("All background servers seem to be gone. Please try again later.") unless(@con_subset);
    my $self = {"dir" => $dir, "c5" => Dumper($c5), "con" => \@con_subset};
    bless($self, $class);
    return $self;
}

sub check_server{
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


sub fini{
    my ($self) = @_;
    #print {$self->{"socket"}} ("fini\n");
    #close($self->{"socket"});
    #foreach my $con (@{$self->{"con"}}){
	#close($con);
    #}
    undef($self);
}


sub get_ngram_freq{
    my ($self, $ngram, $o11, $r1, $n) = @_;
    print {$self->{"socket"}} ("gngf:$ngram,$o11,$r1,$n\n");
    my $socket = $$self{"socket"};
    chomp(my $line = <$socket>);
    return split(",", $line);
}

sub serialize{
    my ($self, $ngref) = @_;
    my @queue;# :shared;
    foreach my $packed_ngram (sort {length($a) <=> length($b) or $a cmp $b} keys %$ngref){
	#my $padded_ngram = unpack("H*", $packed_ngram);
	#my $ngram = $padded_ngram;
	#$ngram =~ s/(00)*$//;
	my $ngram = unpack("H*", $packed_ngram);
	foreach my $position (keys %{$ngref->{$packed_ngram}}){
	    #push(@queue, [$padded_ngram, $ngram, $position, $ngref->{$packed_ngram}->{$position}]);
	    push(@queue, [$ngram, $position, $ngref->{$packed_ngram}->{$position}]);
	    #push(@queue, shared_clone([$ngram, $position, $ngref->{$packed_ngram}->{$position}]));
	}
    }
    return \@queue;
}

sub add_freq_and_am_OLD{
    my ($self, $queueref, $r1, $n, $dbname, $query_length) = @_;
    my %ngret;
    my @children;
    my $queue_length = scalar(@$queueref);
    my $cons = scalar(@{$self->{"con"}});
    my $last_end = -1;
    foreach my $con (@{$self->{"con"}}){
	# try to use threads (cwb must not be running)
	#my $thread = threads->create(\&client_thread, $con, $self->{"dir"}, $self->{"c5"}, $r1, $n, $cons, $queueref, $dbname, $query_length);
	my $end = POSIX::ceil($queue_length / $cons) + $last_end;
	my ($readhandle, $writehandle);
	pipe $readhandle, $writehandle;
	my $pid = fork;
	if($pid){
	    # parent
	    push(@children, [$pid, $readhandle]);
	    close($writehandle);
	}elsif($pid == 0){
	    # child
	    close($readhandle);
	    &client_fork_new($con, $self->{"dir"}, $self->{"c5"}, $r1, $n, $queueref, $last_end + 1, $end, $writehandle, $dbname, $query_length);
	}else{
	    die "couldn't fork: $!\n";
	}
	$queue_length -= ($end - $last_end);
	$last_end = $end;
	$cons--;
    }
    foreach my $pid (@children){
	waitpid($pid->[0], 0);
    }
    #foreach my $thread (threads->list()){
	#$thread->join();
    #}
}

sub add_freq_and_am{
    my ($self, $queueref, $r1, $n, $dbname, $query_length) = @_;
    my %ngret;
    my @sockets ;
    my $queue_length = scalar(@$queueref);
    my $dbh = DBI->connect("dbi:SQLite:user_data/$dbname") or die("Cannot connect: $DBI::errstr");
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
    $dbh->do("PRAGMA cache_size = 50000");
    my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, o11, c1, am) VALUES (?, ?, ?, ?, ?, ?)});
    my $cons = scalar(@{$self->{"con"}});
    foreach my $con (@{$self->{"con"}}){
	my ($remote_host, $remote_port, $local_port) = @$con;
	die("I need some information to connect to the remote server") unless(defined($remote_host) and defined($remote_port) and defined($local_port));
	my $socket = IO::Socket::INET->new(PeerAddr  => $remote_host,
					   PeerPort  => $remote_port,
					   #LocalPort => $local_port,
					   Proto     => "tcp",
					   ReuseAddr => 1,
					   Type      => SOCK_STREAM)
	    or die "Couldn't connect to $remote_host:$remote_port : $@\n";
	print $socket "dir:" . $self->{"dir"} . "\n";
	print $socket $self->{"c5"} . "\n";
	push(@sockets, $socket);
    }
    print STDERR "connected to sockets\n";
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
	    my $workingqueue = "gngf:$r1:$n:," . join(",", map(MIME::Base64::encode(pack("H*", $_->[0]), "") . ":" . $_->[2], @localqueue));
	    print $socket $workingqueue . "\n";
	    foreach my $record (@localqueue){
		my $marked_ngram = $record->[0];
		my $position = $record->[1];
		$marked_ngram =~ s/^((?:[0-9a-f]{2}){$position})((?:[0-9a-f]{2}){$query_length})((?:[0-9a-f]{2})*)$/${1}<${2}>${3}/;
		push(@localresults, [$marked_ngram, $position, $record->[2]]);
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
		die("NICHT DEFINIERT: $c1, $g2") unless(defined($c1) and defined($g2));
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


sub client_thread {
    my ($con, $dir, $c5, $r1, $n, $cons, $queueref, $dbname, $query_length) = @_;
    my ($remote_host, $remote_port, $local_port) = @$con;
    die("I need some information to connect to the remote server") unless(defined($remote_host) and defined($remote_port) and defined($local_port));
    my $socket = IO::Socket::INET->new(PeerAddr  => $remote_host,
				       PeerPort  => $remote_port,
				       #LocalPort => $local_port,
				       Proto     => "tcp",
				       ReuseAddr => 1,
				       Type      => SOCK_STREAM)
	or die "Couldn't connect to $remote_host:$remote_port : $@\n";
    my $dbh = DBI->connect("dbi:SQLite:user_data/$dbname") or die("Cannot connect: $DBI::errstr");
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
    $dbh->do("PRAGMA cache_size = 50000");
    print $socket "dir:$dir\n";
    print $socket "$c5\n";
    my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, o11, c1, am) VALUES (?, ?, ?, ?, ?, ?)});
  OUTER: while(1){
	my @localqueue;
	my $workingqueue = "gngf:$r1:$n:";
	my @localresults;
	{
	    lock($queueref);
	    my $length = scalar(@$queueref) < 50000 ? scalar(@$queueref) : 50000;
	    last OUTER if($length == 0);
	    @localqueue = @$queueref[0 .. $length - 1];
	    if(scalar(@$queueref) > $length){
		@$queueref = @$queueref[$length .. $#$queueref];
	    }else{
		my @empty :shared;
		$queueref = \@empty;
	    }
	}
	while(@localqueue){
	    my $record = shift(@localqueue);
	    $workingqueue .= "," . MIME::Base64::encode(pack("H*", $record->[0]), "") . ":" . $record->[2];
	    my $marked_ngram = $record->[0];
	    my $position = $record->[1];
	    $marked_ngram =~ s/^((?:[0-9a-f]{2}){$position})((?:[0-9a-f]{2}){$query_length})((?:[0-9a-f]{2})*)$/${1}<${2}>${3}/;
	    push(@localresults, [$marked_ngram, $position, $record->[2]]);
	    if(scalar(@localqueue) == 0){
		print $socket $workingqueue . "\n";
		my $line = <$socket>;
		chomp($line);
		my @line = split(",", $line);
		$dbh->do(qq{BEGIN TRANSACTION});
		foreach my $wr (@localresults){
		    my $c1 = shift(@line);
		    my $g2 = shift(@line);
		    die("NICHT DEFINIERT: $c1, $g2") unless(defined($c1) and defined($g2));
		    $insert_result->execute($dbname, @$wr, $c1, $g2);
		}
		$workingqueue = "gngf:$r1:$n:";
		@localresults = ();
		$dbh->do(qq{COMMIT});
	    }
	}
  }
    $dbh->disconnect();
    undef($dbh);
    print $socket "fini\n";
    close($socket);
}

sub client_fork_new {
    #my ($con, $dir, $c5, $r1, $n, $queueref, $wh, $dbname, $query_length) = @_;
    my ($con, $dir, $c5, $r1, $n, $queueref, $start, $end, $wh, $dbname, $query_length) = @_;
    my ($remote_host, $remote_port, $local_port) = @$con;
    my @results;
    my $workingqueue = "gngf:$r1:$n:";
    my $ql = 0;
    my @localresults;
    die("I need some information to connect to the remote server") unless(defined($remote_host) and defined($remote_port) and defined($local_port));
    my $socket = IO::Socket::INET->new(PeerAddr  => $remote_host,
				       PeerPort  => $remote_port,
				       #LocalPort => $local_port,
				       Proto     => "tcp",
				       ReuseAddr => 1,
				       Type      => SOCK_STREAM)
	or die "Couldn't connect to $remote_host:$remote_port : $@\n";
    my $dbh = DBI->connect("dbi:SQLite:user_data/$dbname") or die("Cannot connect: $DBI::errstr");
    $dbh->do("SELECT icu_load_collation('en_GB', 'BE')");
    $dbh->do("PRAGMA cache_size = 50000");
    print $socket "dir:$dir\n";
    print $socket "$c5\n";
    my $insert_result = $dbh->prepare(qq{INSERT INTO results (qid, result, position, o11, c1, am) VALUES (?, ?, ?, ?, ?, ?)});
    #while(@$queueref){
    for (my $i = $start; $i <= $end; $i++) {
	#my $record = shift(@$queueref);
	my $record = ($queueref->[$i]);
	$workingqueue .= "," . MIME::Base64::encode(pack("H*", $record->[0]), "") . ":" . $record->[2];
	my $marked_ngram = $record->[0];
	my $position = $record->[1];
	$marked_ngram =~ s/^((?:[0-9a-f]{2}){$position})((?:[0-9a-f]{2}){$query_length})((?:[0-9a-f]{2})*)$/${1}<${2}>${3}/;
	push(@localresults, [$marked_ngram, $position, $record->[2]]);
	$ql++;
	#if($ql == 50000 or scalar(@$queueref) == 0){
	if($ql == 50000 or $i == $end){
	    print $socket $workingqueue . "\n";
	    my $line = <$socket>;
	    chomp($line);
	    my @line = split(",", $line);
	    $dbh->do(qq{BEGIN TRANSACTION});
	    foreach my $wr (@localresults){
		my $c1 = shift(@line);
		my $g2 = shift(@line);
		die("NICHT DEFINIERT: $c1, $g2") unless(defined($c1) and defined($g2));
		$insert_result->execute($dbname, @$wr, $c1, $g2);
	    }
	    $workingqueue = "gngf:$r1:$n:";
	    $ql = 0;
	    @localresults = ();
	    $dbh->do(qq{COMMIT});
	}
    }
    $dbh->disconnect();
    undef($dbh);
    print $socket "fini\n";
    close($socket);
    #local $Data::Dumper::Indent = 0;
    #local $Data::Dumper::Purity = 1;
    #my $ret = Dumper(\@results);
    close($wh);
    exit(0);
}

1;
