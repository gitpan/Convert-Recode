package Convert::Recode;

use Carp;
use strict;

use vars qw($VERSION $DEBUG);
$VERSION = '1.04';


sub import
{
    my $class = shift;
    my $pkg = caller;

    my $subname;
    for $subname (@_) {
	unless ($subname =~ /^(strict_)?(\w+)_to_(\w+)$/) {
	    croak("recode routine name must be on the form: xxx_to_yyy");
	}
	local(*RECODE, $_);
	my $strict = $1 ? "s" : "";  # strict mode flag
	my ($from, $to) = ($2, $3);
	open(RECODE, "recode -${strict}h $from:$to 2>&1|") or die;
	my @recode_out;
	my @codes;
	my ($too_complex, $identity) = (0, 0);
	while (<RECODE>) {
	    if (/too complex for a mere table/) {
		$too_complex = 1;
		last;
	    }
	    elsif (/Identity recoding/) {
		$identity = 1;
		last;
	    }
	    else {
		push(@recode_out, $_);
		push(@codes, /(\d+|\"[^\"]*\"),/g);
	    }
	}
	close(RECODE);

	my $sub;
	if ($too_complex) {
	    # FIXME: create a subroutine that does call recode directly
	    die "recoding $from to $to too complex, use recode directly\n";
	}
	elsif ($identity) {
	    $sub = sub { $_[0] };
	}
	else {
	    if (@codes != 256) {
		die "Can't recode $subname, output from recode was:\n"
		  . join('', @recode_out)
		    . "'recode -l' for available charsets\n";
	    }
	    $sub = codes_to_sub(\@codes, $strict);
	}

	no strict 'refs';
	*{$pkg . "::" . $subname} = $sub;
    }
}

# Take a conversion table extracted from recode's output and a
# 'strict' flag, and return a subroutine reference.
sub codes_to_sub
{
    my @codes = @{shift()}; die if @codes != 256;
    my $strict = shift;

    my $code;
    if ($strict) {
	my $c = 0;
	my $from = "";		# all chars (matching $to$del)
	my $to   = "";		# transformation
	my $del  = "";		# no tranformation available (to be deleted)
	for (@codes) {
	    my $o = sprintf("\\%03o", $c);
	    if ($_ eq "0" || $_ eq '""') {
		$del .= $o;
		next;
	    }
	    $from .= $o;
	    s/^\"//; s/\"$//;
	    $to   .= $_;
	} continue {
	    $c++;
	}
	$to =~ s,/,\\/,;
	$code = 'sub ($){ my $tmp = shift; $tmp =~ ' .
	  "tr/$from$del/$to/d; \$tmp }";
    } else {
	$code = 'sub ($) { my $tmp = shift; $tmp =~ tr/\x00-\xFF/' .
	  join("", map sprintf("\\x%02X", $_), @codes) .
	    '/; $tmp }';
    }
    
    print STDERR $code if $DEBUG;
    my $sub = eval $code;
    die if $@;
    return $sub;
}    
    
1;
    
__END__

=head1 NAME

Convert::Recode - make mapping functions between character sets

=head1 SYNOPSIS

  use Convert::Recode qw(ebcdic_to_ascii);

  while (<>) {
     print ebcdic_to_ascii($_);
  }

=head1 DESCRIPTION

The Convert::Recode module can provide mapping functions between
character sets on demand.  It depends on GNU recode to provide the raw
mapping data, i.e. GNU recode must be installed first.  The names of
the mapping functions are found by taking the name of the two charsets
and then joining them with the string "_to_".  If you want to convert
between the "mac" and the "latin1" charsets, then you just import the
mac_to_latin1() function.

If you prefix the function name with "strict_" then characters that
can not be mapped are removed during transformation.  For instance the
strict_mac_to_latin1() function will convert to a string to latin1 and
remove all mac characters that have not corresponding latin1
character.

Running the command C<recode -l> should give you the list of character
sets available.

=head1 AUTHOR

Written by and © 1997 Gisle Aas.  Small fixes © 2000 Ed Avis,
<epa98@doc.ic.ac.uk>.

=cut
