#!/usr/bin/perl

# create a binary index for faster lookup
# input: type_ngram_position_ngfreq_freq.uniq
# output: binary index and data files (typid ngid position ngfreq freq)

use warnings;
use strict;

use common_functions;

die("./09a_compile_index.pl outdir corpus-name") unless(scalar(@ARGV) == 1);
my $dir = shift(@ARGV);
die("Not a directory: $dir") unless(-d $dir);

my $datpos = 0;
my $last = 0;
my @tail;

my $outdir = $dir; #"/opt/tmp";

open(IDX, ">$outdir/index.dat") or die("Cannot open file: $!");
open(DAT, ">$outdir/data.dat") or die("Cannot open file: $!");

open(IN, "<$dir/types2ngrams/type_ngram_position_ngfreq_freq.uniq") or die("Cannot open file: $!");

&common_functions::log("Compile dat and idx files", 1, 1);
while(defined(my $line = <IN>)){
    chomp($line);
    my @fields = split(/\t/, $line);
    die("Sortierreihenfolge stimmt nicht") if($fields[0] < $last);
    if($fields[0] != $last){
	#die("Number missing ($last+1)") unless($fields[0] == $last+1);
	while($fields[0] > $last + 1){
	    # Konvention: 1 steht für "ist nicht in den Daten"
	    # da erster Datensatz bei 0 startet und alle Datensätze größer
	    # als 1 Byte sind, kann es zu keinem Konflikt kommen
	    print IDX pack("Q", 1);
	    $last++;
	}
	$datpos = tell(DAT);
	print IDX pack("Q", $datpos);
	print DAT pack("L", $fields[0]);
    }
    print DAT pack("LCLL", @fields[1..$#fields]);
    $last = $fields[0];
}
close(IDX) or die("Cannot close file: $!");
close(DAT) or die("Cannot close file: $!");
close(IN) or die("Cannot close file: $!");
&common_functions::log("Done", 1, 1);
