#! /usr/bin/perl -w

# Copyright Bill Allombert <ballombe@debian.org> 2001.

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

package Devscripts::Symlinks;

BEGIN{
    use Exporter   ();
    use vars       qw(@EXPORT @ISA %EXPORT_TAGS);
    @EXPORT=qw(ListSymlinks);
    @ISA=qw(Exporter);
    %EXPORT_TAGS=();
}

# The purpose here is to find out all the symlinks crossed
# by a file access.

# input: file, pwd
# output: if symlink found: (path to symlink, readlink-replaced file, prefix)
#         if not: (file, file, '')

sub NextSymlink ($$)
{
    my @dirs=split /\//, $_[0];

    # If the path is relative prepend current path.
    unshift @dirs, split(/\//,$_[1]) if $dirs[0] ne '';

    my @dirprefix=();
    while (scalar @dirs) {
	my $dircomp = shift @dirs;
	next if $dircomp eq '.' or $dircomp eq '';
	if ($dircomp eq '..') {
	    pop @dirprefix if @dirprefix;
	    next;
	}
	push @dirprefix, $dircomp;
	last if -l join('/', '', @dirprefix);
    }

    my $path = join('/', '', @dirprefix);

    if (@dirs == 0 and ! -l $path) {
	return ($path, $path, '');
    } else {
	# There was a symlink...
	my $parent = $path;
	$parent =~ s%/[^/]+$%%;

	return ($path, (readlink $path) . '/' . join('/',@dirs), $parent);
    }
}


# input: file, pwd
# output: list of symlinks encountered en route

sub ListSymlinks ($$)
{
    my ($file,$path)=@_;
    my ($link,@links);

    @links=();
    do {
	($link,$file,$path)=NextSymlink($file,$path);
	push @links, $link;
    } until($path eq '');

    return @links;
}

1;
