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

    my @sorted = map { [$_->[0], $_->[1]] }
                 sort { $a->[2] <=> $b->[2] }
                 map { [$_->[0], $_->[1], Dpkg::Version->new($_->[0], check => $check)] }
                 @namever_pairs;

    return reverse @sorted;
}

1;
