# Copyright (C) 1998,2002 Julian Gilbey <jdg@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# For a copy of the GNU General Public License write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

# The functions in this Perl module are versort and deb_versort.  They
# each take as input an array of elements of the form [version, data, ...]
# and sort them into decreasing order according to dpkg's
# understanding of version sorting.  The output is a sorted array.  In
# versort, "version" is assumed to be an upstream version number only,
# whereas in deb_versort, "version" is assumed to be a Debian version
# number, possibly including an epoch and/or a Debian revision.
# 
# The sorting order of upstream version numbers is described in
# chapter 4 of the Debian Policy Manual:
#
#   The strings are compared from left to right.
#
#   First the initial part of each string consisting entirely of non-digit
#   characters is determined. These two parts (one of which may be empty)
#   are compared lexically. If a difference is found it is returned. The
#   lexical comparison is a comparison of ASCII values modified so that
#   all the letters sort earlier than all the non-letters.
#
#   Then the initial part of the remainder of each string which consists
#   entirely of digit characters is determined. The numerical values of
#   these two parts are compared, and any difference found is returned as
#   the result of the comparison. For these purposes an empty string
#   (which can only occur at the end of one or both version strings being
#   compared) counts as zero.
#
#   These two steps are repeated (chopping initial non-digit strings and
#   initial digit strings off from the start) until a difference is found
#   or both strings are exhausted.
#
# The program works like this.  In order that letters (defined by the
# isalpha() function) sort before non-letters, we initially modify all
# the strings as follows: every letter x is replaced by ax, every
# non-alphanumeric x is replaced by bx, and digits are left
# untouched.  In this way, the letters will all sort before
# non-letters in alphabetical sorting.  At the end, we simply undo the
# changes.  We use "no locale" since the dpkg program clears the locale
# before comparing things (or at least it should do), so we should do
# the same in order to match it.  We must also use [A-Za-z] rather than
# \w to distinguish between letters and digits.
#
# We read all of the strings into an array.  We then split each string
# by blocks of digits, and sort this array of arrays.  In this way, we
# need only perform the splitting etc. once.  We also note that some
# of our strings might end in a digit, in which case the split array
# would not have the null non-digit string at the end.  We make our
# lives easier by insisting that they do.  Thus we will always have an
# array of the form ("\D*","\d+","\D+","\d+",...,"\d+","\D*"), that
# is, it has odd length, always ending with a non-digit string.
# 
# The returned array has the greatest version as the 0th array element.

package Devscripts::Versort;

sub versort (@)
{
    my @namever_pairs = @_;

    my @sorted = sort { _vercmp($$a[0], $$b[0]) } @namever_pairs;
    return reverse @sorted;
}

sub _vercmp {
    my ($v1, $v2) = @_;

    return 0 if $v1 eq $v2;
    # assume dpkg works - not really worth checking every single call here
    return -1 if system("dpkg", "--compare-versions", $v1, "lt", $v2) == 0;
    return 1;
}

1;

__END__

# This was the old version.  It didn't handle ~, incidentally

no locale;

sub versort (@)
{
    my @namever_pairs = @_;

    foreach my $pair (@namever_pairs) {
	my $ver = $$pair[0];
	$ver =~ s/([A-Za-z])/a$1/g;
	$ver =~ s/([^A-Za-z0-9])/b$1/g;

	my @split_ver = split /(\d+)/, $ver, -1;
	unshift @$pair, \@split_ver;
    }

    @namever_pairs = sort _vercmp @namever_pairs;

    foreach my $pair (@namever_pairs) {
	shift @$pair;
    }

    return reverse @namever_pairs;
}


# The following subroutine compares two split strings, passed within
# references to anonymous arrays, $a and $b.  We remember that we must
# not alter the things $a and $b refer to.  We also remember that the
# arrays @{$$a[0]} and @{$$b[0]} will always have an odd length as
# explained above.

sub _vercmp {
    $vera=$$a[0];
    $verb=$$b[0];
    $lengtha = @$vera;
    $lengthb = @$verb;

    $i=0;
    for (;;) {
	$nondiga = $vera->[$i];
	$nondigb = $verb->[$i];

	if ($nondiga lt $nondigb) { return -1; }
	if ($nondiga gt $nondigb) { return +1; }

	$i++;

	if ($lengtha == $i) {   # Nothing left in array @$vera
	    if ($lengthb == $i) { return 0; }  # @$vera = @$verb
	    else { return -1; }          # @$vera is an initial part of @$verb
	}
	elsif ($lengthb == $i) { return +1; }  # vice versa

	# Now for the next term, which is a numeric part

	if ( $vera->[$i] < $verb->[$i] ) { return -1; }
	if ( $vera->[$i] > $verb->[$i] ) { return +1; }

	$i++;
    }
}

# Now the Debian variants

sub deb_versort (@)
{
    my @namever_pairs = @_;

    foreach my $pair (@namever_pairs) {
	my ($ver, $epoch, $rev);
	$ver = $$pair[0];
	if ($ver =~ s/^(\d+)://) { $epoch = $1; } else { $epoch = 0; }
	if ($ver =~ s/-([^-]+)$//) { $rev = $1; } else { $rev = ''; }
	$ver =~ s/([A-Za-z])/a$1/g;
	$ver =~ s/([^A-Za-z0-9])/b$1/g;
	$rev =~ s/([A-Za-z])/a$1/g;
	$rev =~ s/([^A-Za-z0-9])/b$1/g;

	my @split_ver = split /(\d+)/, $ver, -1;
	my @split_rev = split /(\d+)/, $rev, -1;
	unshift @$pair, $epoch, \@split_ver, \@split_rev;
    }

    @namever_pairs = sort _deb_vercmp @namever_pairs;

    # Undo the unshifts
    foreach my $pair (@namever_pairs) {
	shift @$pair;
	shift @$pair;
	shift @$pair;
    }

    return reverse @namever_pairs;
}


# The following subroutine compares two Debian version numbers in
# split strings format, passed within references to anonymous arrays,
# $a and $b, as above.  We remember that we must not alter the things
# $a and $b refer to.  We also remember that the arrays @{$$a[1,2]}
# and @{$$b[1,2]} (using sloppy notation ;-) will always have an odd
# length as explained above.

sub _deb_vercmp {
    $epocha=$$a[0];
    $epochb=$$b[0];
    $vera=$$a[1];
    $verb=$$b[1];
    $reva=$$a[2];
    $revb=$$b[2];

    # epochs first
    if ( $epocha < $epochb ) { return -1; }
    if ( $epocha > $epochb ) { return +1; }

    # if we're still going, the epochs are the same, so we now handle
    # the upstream version numbers

    $lengtha = @$vera;
    $lengthb = @$verb;

    $i=0;
    for (;;) {
	$nondiga = $vera->[$i];
	$nondigb = $verb->[$i];

	if ($nondiga lt $nondigb) { return -1; }
	if ($nondiga gt $nondigb) { return +1; }

	$i++;

	if ($lengtha == $i) {   # Nothing left in array @$vera
	    if ($lengthb == $i) { last; }  # @$vera = @$verb
	    else { return -1; }          # @$vera is an initial part of @$verb
	}
	elsif ($lengthb == $i) { return +1; }  # vice versa

	# Now for the next term, which is a numeric part

	if ( $vera->[$i] < $verb->[$i] ) { return -1; }
	if ( $vera->[$i] > $verb->[$i] ) { return +1; }

	$i++;
    }

    # if we're still going, the upstream version numbers are the same,
    # so we now handle the Debian revision numbers

    $lengtha = @$reva;
    $lengthb = @$revb;

    if ($lengtha == 0 && $lengthb == 0) {
        return 0;       # both lack Debian versions - #236344
    }

    $i=0;
    for (;;) {
	$nondiga = $reva->[$i];
	$nondigb = $revb->[$i];

	if ($nondiga lt $nondigb) { return -1; }
	if ($nondiga gt $nondigb) { return +1; }

	$i++;

	if ($lengtha == $i) {   # Nothing left in array @$reva
	    if ($lengthb == $i) { return 0; }  # @$reva = @$revb
	    else { return -1; }          # @$reva is an initial part of @$revb
	}
	elsif ($lengthb == $i) { return +1; }  # vice versa

	# Now for the next term, which is a numeric part

	if ( $reva->[$i] < $revb->[$i] ) { return -1; }
	if ( $reva->[$i] > $revb->[$i] ) { return +1; }

	$i++;
    }
}

1;
