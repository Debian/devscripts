# Copyright Bill Allombert <ballombe@debian.org> 2001.
# Modifications copyright 2002 Julian Gilbey <jdg@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package Devscripts::Set;

use strict;

BEGIN{
  use Exporter   ();
  use vars       qw(@EXPORT @ISA %EXPORT_TAGS);
  @EXPORT=qw(SetMinus SetInter SetUnion);
  @ISA=qw(Exporter);
  %EXPORT_TAGS=();
}

# Several routines to work with arrays whose elements are unique
# (here called sets)

=head1 NAME

Devscripts::Set - Functions for handling sets.

=head1 SYNOPSIS

use Devscripts::Set;

@set=ListToSet(@list);

@setdiff=SetMinus(\@set1,\@set2);

@setinter=SetInter(\@set1,\@set2);

@setunion=SetUnion(\@set1,\@set2);

=head1 DESCRIPTION

ListToSet: Make a set (array with duplicates removed) from a list of
items given by an array.

SetMinus, SetInter, SetUnion: Compute the set theoretic difference,
intersection, union of two sets given as arrays.

=cut

# Transforms a list to a set, removing duplicates
# input:  list
# output: set

sub ListToSet (@)
{
    my %items;

    grep $items{$_}++, @_;

    return keys %items;
}


# Compute the set-theoretic difference of two sets.
# input: ref to Set 1, ref to Set 2
# output: set

sub SetMinus ($$)
{
    my ($set1,$set2)=@_;
    my %items;

    grep $items{$_}++, @$set1;
    grep $items{$_}--, @$set2;

    return grep $items{$_}>0, keys %items;
}


# Compute the set-theoretic intersection of two sets.
# input: ref to Set 1, ref to Set 2
# output: set

sub SetInter ($$)
{
    my ($set1,$set2)=@_;
    my %items;

    grep $items{$_}++, @$set1;
    grep $items{$_}++, @$set2;

    return grep $items{$_}==2, keys %items;
}


#Compute the set-theoretic union of two sets.
#input: ref to Set 1, ref to Set 2
#output: set

sub SetUnion ($$)
{
    my ($set1,$set2)=@_;
    my %items;

    grep $items{$_}++, @$set1;
    grep $items{$_}++, @$set2;

    return grep $items{$_}>0, keys %items;
}

1;

=head1 AUTHOR

Bill Allombert <ballombe@debian.org>

=head1 COPYING

Copyright 2001 Bill Allombert <ballombe@debian.org>
Modifications Copyright 2002 Julian Gilbey <jdg@debian.org>
dpkg-depcheck is free software, covered by the GNU General Public License, and
you are welcome to change it and/or distribute copies of it under
certain conditions.  There is absolutely no warranty for dpkg-depcheck.

=cut
