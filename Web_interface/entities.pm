package entities;

use warnings;
use strict;

use Encode;
use Unicode::Normalize;

sub substitute{
    my $line = shift;
    $line =~ s/\x{0100}/A/g;
    $line =~ s/\x{0101}/a/g;
    $line =~ s/\x{0103}/a/g;
    $line =~ s/\x{0105}/a/g;
    $line =~ s/\x{0107}/c/g;
    $line =~ s/\x{0109}/c/g;
    $line =~ s/\x{010c}/C/g;
    $line =~ s/\x{010d}/c/g;
    $line =~ s/\x{010f}/d/g;
    $line =~ s/\x{0111}/d/g;
    $line =~ s/\x{0113}/e/g;
    $line =~ s/\x{0119}/e/g;
    $line =~ s/\x{011a}/E/g;
    $line =~ s/\x{011b}/e/g;
    $line =~ s/\x{0127}/h/g;
    $line =~ s/\x{012b}/i/g;
    $line =~ s/\x{0139}/L/g;
    $line =~ s/\x{013a}/l/g;
    $line =~ s/\x{0141}/L/g;
    $line =~ s/\x{0142}/l/g;
    $line =~ s/\x{0144}/n/g;
    $line =~ s/\x{0146}/n/g;
    $line =~ s/\x{0148}/n/g;
    $line =~ s/\x{014d}/o/g;
    $line =~ s/\x{0152}/OE/g;
    $line =~ s/\x{0153}/oe/g;
    $line =~ s/\x{0155}/r/g;
    $line =~ s/\x{0158}/R/g;
    $line =~ s/\x{0159}/r/g;
    $line =~ s/\x{015a}/S/g;
    $line =~ s/\x{015b}/s/g;
    $line =~ s/\x{015d}/s/g;
    $line =~ s/\x{015e}/S/g;
    $line =~ s/\x{015f}/s/g;
    $line =~ s/\x{0160}/S/g;
    $line =~ s/\x{0161}/s/g;
    $line =~ s/\x{0163}/t/g;
    $line =~ s/\x{0165}/t/g;
    $line =~ s/\x{016b}/u/g;
    $line =~ s/\x{016f}/u/g;
    $line =~ s/\x{0175}/w/g;
    $line =~ s/\x{0176}/Y/g;
    $line =~ s/\x{0177}/y/g;
    $line =~ s/\x{0178}/Y/g;
    $line =~ s/\x{017a}/z/g;
    $line =~ s/\x{017c}/z/g;
    $line =~ s/\x{017d}/Z/g;
    $line =~ s/\x{017e}/z/g;
    $line =~ s/\x{0380}/&#x0380;/g; #!!!
    $line =~ s/\x{0392}/B/g;
    $line =~ s/\x{0393}/G/g;
    $line =~ s/\x{0394}/D/g;
    $line =~ s/\x{0395}/E/g;
    $line =~ s/\x{0396}/Z/g;
    $line =~ s/\x{0398}/TH/g;
    $line =~ s/\x{039c}/M/g;
    $line =~ s/\x{039f}/O/g;
    $line =~ s/\x{03a0}/P/g;
    $line =~ s/\x{03a3}/S/g;
    $line =~ s/\x{03a5}/Y/g;
    $line =~ s/\x{03a6}/PH/g;
    $line =~ s/\x{03a8}/PS/g;
    $line =~ s/\x{03a9}/O/g;
    $line =~ s/\x{03b1}/a/g;
    $line =~ s/\x{03b2}/b/g;
    $line =~ s/\x{03b3}/g/g;
    $line =~ s/\x{03b4}/d/g;
    $line =~ s/\x{03b5}/e/g;
    $line =~ s/\x{03b6}/z/g;
    $line =~ s/\x{03b7}/e/g;
    $line =~ s/\x{03b8}/th/g;
    $line =~ s/\x{03b9}/i/g;
    $line =~ s/\x{03ba}/k/g;
    $line =~ s/\x{03bb}/l/g;
    $line =~ s/\x{03bc}/\x{00b5}/g;
    $line =~ s/\x{03bd}/n/g;
    $line =~ s/\x{03be}/x/g;
    $line =~ s/\x{03bf}/o/g;
    $line =~ s/\x{03c0}/p/g;
    $line =~ s/\x{03c1}/r/g;
    $line =~ s/\x{03c3}/s/g;
    $line =~ s/\x{03c4}/t/g;
    $line =~ s/\x{03c5}/y/g;
    $line =~ s/\x{03c6}/ph/g;
    $line =~ s/\x{03c7}/ch/g;
    $line =~ s/\x{03c8}/ps/g;
    $line =~ s/\x{03c9}/o/g;
    $line =~ s/\x{2000}/ /g;
    $line =~ s/\x{2010}/-/g;
    $line =~ s/\x{2013}/--/g;
    $line =~ s/\x{2014}/---/g;
    $line =~ s/\x{2015}/---/g;
    $line =~ s/\x{2018}/\x{0027}/g;
    $line =~ s/\x{2019}/\x{0027}/g;
    $line =~ s/\x{2022}/\x{00b7}/g;
    $line =~ s/\x{2026}/.../g;
    $line =~ s/\x{2032}/\x{0027}/g;
    $line =~ s/\x{2033}/\x{0022}/g;
    $line =~ s/\x{2122}/TM/g;
    $line =~ s/\x{2126}/O/g;
    $line =~ s/\x{2153}/1\/3/g;
    $line =~ s/\x{2154}/2\/3/g;
    $line =~ s/\x{2155}/1\/5/g;
    $line =~ s/\x{2156}/2\/5/g;
    $line =~ s/\x{2157}/3\/5/g;
    $line =~ s/\x{2158}/4\/5/g;
    $line =~ s/\x{2159}/1\/6/g;
    $line =~ s/\x{215a}/5\/6/g;
    $line =~ s/\x{215b}/1\/8/g;
    $line =~ s/\x{215c}/3\/8/g;
    $line =~ s/\x{215d}/5\/8/g;
    $line =~ s/\x{215e}/7\/8/g;
    $line =~ s/\x{2190}/<-/g;
    $line =~ s/\x{2192}/->/g;
    #$line =~ s/\x{2193}/\/downarrow\//g;
    $line =~ s/\x{2193}/&#2193x;/g;
    #$line =~ s/\x{2200}/\/forall\//g;
    $line =~ s/\x{2200}/&#x2200;/g;
    $line =~ s/\x{2217}/\x{002a}/g;
    $line =~ s/\x{2218}/\x{00b0}/g;
    #$line =~ s/\x{221a}/\/sqrt\//g;
    $line =~ s/\x{221a}/&#x221a;/g;
    #$line =~ s/\x{221e}/\/infinity\//g;
    $line =~ s/\x{221e}/&#x221e;/g;
    #$line =~ s/\x{2230}/\/volumeintegral\//g;
    $line =~ s/\x{2230}/&#x2230;/g;
    $line =~ s/\x{223c}/\x{007e}/g;
    #$line =~ s/\x{2243}/\/asympequal\//g;
    $line =~ s/\x{2243}/&#x2243;/g;
    #$line =~ s/\x{2264}/<=/g;
    $line =~ s/\x{2264}/&#x2264;/g;
    #$line =~ s/\x{2265}/>=/g;
    $line =~ s/\x{2265}/&#x2265;/g;
    #$line =~ s/\x{25be}/\/down\//g;
    $line =~ s/\x{25be}/&#x25be;/g;
    #$line =~ s/\x{25cb}/\/circle\//g;
    $line =~ s/\x{25cb}/&#x25cb;/g;
    #$line =~ s/\x{2665}/\/heart\//g;
    $line =~ s/\x{2665}/&#x2665;/g;
    #$line =~ s/\x{266d}/\/musicflat\//g;
    $line =~ s/\x{266d}/&#x266d;/g;
    #$line =~ s/\x{266e}/\/musicnatural\//g;
    $line =~ s/\x{266e}/&#x266e;/g;
    #$line =~ s/\x{266f}/\/musicsharp\//g;
    $line =~ s/\x{266f}/&#x266f;/g;
    #$line =~ s/\x{2713}/\/checkmark\//g;
    $line =~ s/\x{2713}/&#x2713;/g;
    return $line;
}

sub encode_entities{
    my $line = shift;
    my $returnstring = "";
    $line = Unicode::Normalize::NFKC($line);
    #print join(":", split(//, $line));
    foreach my $char (split(//, $line)){
	my $val = ord($char);
	if($val > 255){
	    $returnstring .=  sprintf("&#x%x;", $val);
	}else{
	    my $c = chr($val);
	    $c = "&lt;" if($c eq "<");
	    $c = "&amp;" if($c eq "&");
	    $returnstring .=  $c;
	}
    }
    return $returnstring;
}

sub decode_entities{
    my $line = shift;
    $line =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
    #$line = Unicode::Normalize::NFC($line);
    return $line;
}

sub utf8_to_latin1{
    my $line = shift;
    $line = Encode::decode("utf8", $line);
    $line = encode_entities($line);
    $line = Encode::encode("iso-8859-1", $line);
    return $line;
}

sub latin1_to_utf8{
    my $line = shift;
    $line = Encode::decode("iso-8859-1", $line);
    $line = decode_entities($line);
    #$line = Encode::encode("utf8", $line);
}

1;
