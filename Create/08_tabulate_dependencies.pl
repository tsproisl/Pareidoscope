#!/usr/bin/perl

# tabulate dependencies and create numeric IDs for dependency relations
# output: dependencies.out, dependency_relations.dump, modified version of SQLite database

use warnings;
use strict;

use Storable;
use DBI;

#use lib "/home/linguistik/tsproisl/local/lib/perl5/site_perl";
use CWB::CQP;
use CWB::CL;

die("./08_tabulate_dependencies.pl outdir corpus-name dbname") unless ( scalar(@ARGV) == 3 );
my $outdir  = shift(@ARGV);
my $corpus  = shift(@ARGV);
my $dbname  = shift(@ARGV);
die("Not a directory: $outdir") unless ( -d $outdir );

my %relation_ids;

&fill_database($outdir);

sub fill_database {
    my ($outdir) = @_;
    my %relations;
    my $cqp = new CWB::CQP;
    $cqp->set_error_handler('die');    # built-in, useful for one-off scripts
    $cqp->exec("set Registry '/localhome/Databases/CWB/registry'");
    $cqp->exec($corpus);
    $CWB::CL::Registry = '/localhome/Databases/CWB/registry';
    my $corpus_handle = new CWB::CL::Corpus $corpus;
    $cqp->exec("A = <s> [] expand to s");
    my ($size) = $cqp->exec("size A");
    $cqp->exec("tabulate A match .. matchend indep, match .. matchend outdep, match .. matchend root, match .. matchend, match s_id > \"$outdir/dependencies.out\"");
    open( TAB, "<:encoding(utf8)", "$outdir/dependencies.out" ) or die("Cannot open $outdir/dependencies.out: $!");

    while ( defined( my $match = <TAB> ) ) {
        print STDERR "$.\n" if ( $. % 10000 == 0 );
        chomp($match);
        my ($indeps) = split( /\t/, $match );
        my @indeps = split( / /, $indeps );
        foreach my $indeps (@indeps) {
            $indeps =~ s/^\|//;
            $indeps =~ s/\|$//;
            foreach my $indep ( split( /\|/, $indeps ) ) {
                if ( $indep =~ m/^(?<relation>[^(]+)\((?<offset>-?\d+)(?:&apos;)*,0(?:&apos;)*/ ) {
                    $relations{ $+{"relation"} }++;
                }
                else {
                    die("dependency relation does not match: $indep\n");
                }
            }
        }
    }
    close(TAB) or die("Cannot close $outdir/dependencies.out: $!");
    unlink("$outdir/$dbname") if ( -e "$outdir/$dbname" );
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$outdir/$dbname", "", "" ) or die("Cannot connect: $DBI::errstr");
    $dbh->do(qq{DROP TABLE IF EXISTS dependencies});
    $dbh->do(qq{CREATE TABLE dependencies (depid INTEGER PRIMARY KEY AUTOINCREMENT, relation TEXT UNIQUE, frequency INTEGER)});
    my $insert_dependency = $dbh->prepare(qq{INSERT INTO dependencies (relation, frequency) VALUES (?, ?)});
    my $get_dependency_id = $dbh->prepare(qq{SELECT depid FROM dependencies WHERE relation = ?});
    $dbh->do(qq{BEGIN TRANSACTION});

    foreach my $key ( sort keys %relations ) {
        $insert_dependency->execute( $key, $relations{$key} );
        $get_dependency_id->execute($key);
        ( $relation_ids{$key} ) = $get_dependency_id->fetchrow_array;
    }
    $dbh->do(qq{COMMIT});
    undef($dbh);
    Storable::nstore( \%relation_ids, "$outdir/dependency_relations.dump" );
}
