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
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# The functions in this Perl module are versort and deb_versort.  They
# each take as input an array of elements of the form [version, data, ...]
# and sort them into decreasing order according to dpkg's
# understanding of version sorting.  The output is a sorted array.  In
# versort, "version" is assumed to be an upstream version number only,
# whereas in deb_versort, "version" is assumed to be a Debian version
# number, possibly including an epoch and/or a Debian revision.
#
# The returned array has the greatest version as the 0th array element.

package Devscripts::Versort;
use Dpkg::Version;

sub versort (@)
{
    return _versort(0, @_);
}

sub deb_versort (@)
{
    return _versort(1, @_);
}

sub _versort ($@)
{
    my ($check, @namever_pairs) = @_;

    foreach my $pair (@namever_pairs) {
	unshift(@$pair, Dpkg::Version->new($pair->[0], check => $check));
    }

    my @sorted = sort { $b->[0] <=> $a->[0] } @namever_pairs;

    foreach my $pair (@sorted) {
	shift @$pair;
    }

    return @sorted;
}

1;
