package statistics;

use strict;
use warnings;
use Math::BigInt; #lib => 'GMP';
use Math::BigRat; #lib => 'GMP';
use Math::BigFloat; #lib => 'GMP';

my $case1;

#       | n-gram | !n-gram |
# ------+--------+---------+----
#  word |  O11   |   O12   | R1
# ------+--------+---------+----
# !word |  O21   |   O22   | R2
# ------+--------+---------+----
#       |   C1   |    C2   | N

# Easily observable: O11, R1, C1, N

# str = FET(o11, r1, c1, n)
sub FET($$$$){
    my ($o11, $r1, $c1, $n);
    my ($min, $max, $r2, $fisher);
    ($o11, $r1, $c1, $n) = @_;
    $min = $o11;
    $max = $r1 < $c1 ? $r1 : $c1;
    $r2 = Math::BigRat->new($n - $r1);
    $r1 = Math::BigRat->new($r1);
    $c1 = Math::BigRat->new($c1);
    $n = Math::BigRat->new($n);
    $fisher = Math::BigRat->bzero();
    &_FET($r1, $r2, $c1, $n, $min, $max, $fisher);
    return &_rat2scifloat($fisher);
}

# bigr = _FET(r1, r2, c1, n, min, max, fisher)
sub _FET($$$$$$$){
    my ($r1, $r2, $c1, $n, $min, $max, $fisher);
    my ($p, $cum_p);
    ($r1, $r2, $c1, $n, $min, $max, $fisher) = @_;
    print "r1: ", $r1->bstr(), "\n";
    print "r2: ", $r2->bstr(), "\n";
    print "c1: ", $c1->bstr(), "\n";
    print "n: ", $n->bstr(), "\n";
    $p = &_hypergeom($min, $r1, $r2, $c1, $n);
    $fisher->badd($p);
    for(my $k = $min; $k < $max; $k++){
	#$p->bmul((($r1-$k)*($c1-$k))/(($k+1)*($r2-$c1+$k+1)));
	$p->bmul((($r1-$k)/($k+1))*(($c1-$k)/($r2-$c1+$k+1)));
	$fisher->badd($p);
    }
}

# bigr = _hypergeom(k, r1, r2, c1, n)
sub _hypergeom($$$$$){
    my ($k, $r1, $r2, $c1, $n);
    my ($p);
    ($k, $r1, $r2, $c1, $n) = @_;
    my $a = &_binom($r1, $k);
    print "a\n";
    my $b = &_binom($r2, $c1-$k);
    print "b\n";
    my $c = &_binom($n, $c1);
    print "c\n";
    $p = ($a)->bmul($b)->bdiv($c);
    return $p;
}

# str = binom(nr, nr)
sub binom($$){
   my ($n, $k);
   ($n, $k) = @_;
   $n = Math::BigRat->new("$n");
   $k = Math::BigRat->new("$k");
   return (&_binom($n, $k))->bstr();
}

# bigf = _binom(bigf, bigf)
sub _binom($$){
    my ($n, $k);
    my $nc;
    ($n, $k) = @_;
    $nc = $n->copy();
    return $nc->bnok($k);
}


# str = G(o11, r1, c1, n)
sub G($$$$){
    my ($o11, $r1, $c1, $n);
    my ($o, $e, $r, $c, $G);
    ($o11, $r1, $c1, $n) = @_;
    $G = Math::BigFloat->bzero;
    ($o, $e, $r, $c, $n) = &_Contintable($o11, $r1-$o11, $c1-$o11, $n-$r1-($c1-$o11));
    for(my $i=1; $i<=2; $i++){
	for(my $j=1; $j<=2; $j++){
	    #print "o$i$j: " . $o->[$i]->[$j]->bstr() . "\n";
	    #print "e$i$j: " . $e->[$i]->[$j]->bstr() . "\n";
	    my $orig = $o->[$i]->[$j]->bstr();
	    next if($orig == 0);
	    $o->[$i]->[$j]->bdiv($e->[$i]->[$j]);
	    $o->[$i]->[$j]->blog(0);
	    $o->[$i]->[$j]->bmul($orig);
	    $G->badd($o->[$i]->[$j]);
	}
    }
    return $G->bmul(2)->bround(6)->bstr();
}

# str = g(o11, r1, c1, n)
sub g($$$$){
    my ($o11, $r1, $c1, $n);
    my ($o, $e, $r, $c, $G);
    ($o11, $r1, $c1, $n) = @_;
    return $case1 if(defined($case1) and $o11 == 1 and $c1 == 1);
    $G = 0;
    ($o, $e, $r, $c, $n) = &_contintable($o11, $r1-$o11, $c1-$o11, ($n-$r1)-($c1-$o11));
    for(my $i=1; $i<=2; $i++){
	for(my $j=1; $j<=2; $j++){
	    next if($o->[$i]->[$j] == 0);
	    my $im = $o->[$i]->[$j] * log($o->[$i]->[$j] / $e->[$i]->[$j]);
	    #print sprintf("%.2f\t", $im);
	    $G += $im;
	}
    }
    $G *= 2;
    $case1 = $G if($o11 == 1 and $c1 == 1);
    #print sprintf("--> %.2f (%.2f)\n", $G, ($n*$o11**2)/($r1*$c1));
    #return sprintf("%.5f", $G);
    return $G;
}


sub dice($$$$){
    my ($o11, $r1, $c1, $n);
    my ($o, $e, $r, $c, $dice);
    ($o11, $r1, $c1, $n) = @_;
    ($o, $e, $r, $c, $n) = &_contintable($o11, $r1-$o11, $c1-$o11, $n-$r1-($c1-$o11));
    $dice = (2 * $o->[1]->[1]) / ($r1 + $c1);
    return sprintf("%.5f", $dice);
}


sub _Contintable{
    my ($o11, $o12, $o21, $o22);
    my $n;
    my (@o, @e, @r, @c);
    ($o11, $o12, $o21, $o22) = @_;
    $r[1] = $o11 + $o12;
    $r[2] = $o21 + $o22;
    $c[1] = $o11 + $o21;
    $c[2] = $o12 + $o22;
    $n = $c[1] + $c[2];
    $o[1]->[1] = Math::BigFloat->new($o11);
    $o[1]->[2] = Math::BigFloat->new($o12);
    $o[2]->[1] = Math::BigFloat->new($o21);
    $o[2]->[2] = Math::BigFloat->new($o22);
    $e[1]->[1] = Math::BigFloat->new($r[1]*$c[1]/$n);
    $e[1]->[2] = Math::BigFloat->new($r[1]*$c[2]/$n);
    $e[2]->[1] = Math::BigFloat->new($r[2]*$c[1]/$n);
    $e[2]->[2] = Math::BigFloat->new($r[2]*$c[2]/$n);
    return (\@o, \@e, \@r, \@c, $n);
}

sub _contintable{
    my ($o11, $o12, $o21, $o22);
    my $n;
    my (@o, @e, @r, @c);
    ($o11, $o12, $o21, $o22) = @_;
    $r[1] = $o11 + $o12;
    $r[2] = $o21 + $o22;
    $c[1] = $o11 + $o21;
    $c[2] = $o12 + $o22;
    $n = $c[1] + $c[2];
    $o[1]->[1] = $o11;
    $o[1]->[2] = $o12;
    $o[2]->[1] = $o21;
    $o[2]->[2] = $o22;
    $e[1]->[1] = $r[1]*$c[1]/$n;
    $e[1]->[2] = $r[1]*$c[2]/$n;
    $e[2]->[1] = $r[2]*$c[1]/$n;
    $e[2]->[2] = $r[2]*$c[2]/$n;
    return (\@o, \@e, \@r, \@c, $n);
}

sub _rat2scifloat{
    my ($bigrat);
    my ($bigfloat, $mant, $exp, $bigstr);
    ($bigrat) = @_;
    $bigfloat = Math::BigFloat->new($bigrat->numerator());
    $bigfloat->bdiv($bigrat->denominator(), 7);
    #$bigfloat->bfround(6, 6);
    $mant = $bigfloat->mantissa()->bstr();
    $exp = $bigfloat->exponent()->bstr();
    $exp +=  length($mant) - 1;
    $mant = substr($mant, 0, 1) . "." . substr($mant, 1);
    $bigstr = "${mant}e$exp";
    return $bigstr;
}

1;
