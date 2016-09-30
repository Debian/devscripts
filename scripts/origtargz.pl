#!/usr/bin/perl
#
# origtargz: fetch the orig tarball of a Debian package from various sources,
# and unpack it
# Copyright (C) 2012-2016  Christoph Berg <myon@debian.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

=head1 NAME

origtargz - fetch the orig tarball of a Debian package from various sources, and unpack it

=head1 SYNOPSIS

=over

=item B<origtargz> [I<OPTIONS>] [B<--unpack>[=B<no>|B<once>|B<yes>]]

=item B<origtargz> B<--help>

=back

=head1 DESCRIPTION

B<origtargz> downloads the orig tarball of a Debian package, and also unpacks
it into the current directory, if it just contains a F<debian> directory. The
main use for B<origtargz> is with debian-dir-only repository checkouts, but it
is useful as a general tarball download wrapper. The version number for the
tarball to be downloaded is determined from F<debian/changelog>. It should be
invoked from the top level directory of an unpacked Debian source package.

Various download locations are tried:

=over 4

=item *

First, an existing file is looked for.

=item *

Directories given with B<--path> are searched.

=item *

B<pristine-tar> is tried.

=item *

B<apt-get source> is tried when B<apt-cache showsrc> reports a matching version.

=item *

Finally, B<uscan --download-current-version> is tried.

=back

When asked to unpack the orig tarball, B<origtargz> will remove all files and
directories from the current directory, except the debian directory, and the
VCS repository directories. Some files outside F<debian/> which are often stored
in VCS even for debian-dir-only repositories are also preserved (F<.bzr-builddeb>,
F<.gitignore>, F<.hgignore>). I<Note that this will drop all non-committed changes>
for the patch system in use (e.g. source format "3.0 (quilt)"), and will even
remove all patches from the package when no patch system is in use (the
original "1.0" source format).

The default behavior is to unpack the orig tarball if the current directory
is empty except for a F<debian> directory and the VCS files mentioned above.

=head1 NOTES

Despite B<origtargz> being called "targz", it will work with any compression
scheme used for the tarball.

A similar tool to unpack orig tarballs is B<uupdate>(1). B<uupdate> creates a
new working directory, unpacks the tarball, and applies the Debian F<.diff.gz>
changes. In contrast, B<origtargz> uses the current directory, keeping VCS
metadata.

For Debian package repositories that keep the full upstream source, other tools
should be used to upgrade the repository from the new tarball. See
B<gbp-import-orig>(1) and B<svn-upgrade>(1) for examples. B<origtargz> is still
useful for downloading the current tarball.

=head1 OPTIONS

=over

=item B<-p>, B<--path> I<directory>

Add I<directory> to the list of locations to search for an existing tarball.
When found, a hardlink is created if possible, otherwise a symlink.

=item B<-u>, B<--unpack>[=B<no>|B<once>|B<yes>]

Unpack the downloaded orig tarball to the current directory, replacing
everything except the debian directory. Existing files are removed, except for
F<debian/> and VCS files. Preserved are: F<.bzr>, F<.bzrignore>,
F<.bzr-builddeb>, F<.git>, F<.gitignore>, F<.hg>, F<.hgignore>, F<_darcs> and
F<.svn>.

=over

=item B<no>

Do not unpack the orig tarball.

=item B<once> (default when B<--unpack> is not used)

If the current directory contains only a F<debian> directory (and possibly some
dotfiles), unpack the orig tarball. This is the default behavior.

=item B<yes> (default for B<--unpack> without argument)

Always unpack the orig tarball.

=back

=item B<-d>, B<--download-only>

Alias for B<--unpack=no>.

=item B<-t>, B<--tar-only>

When using B<apt-get source>, pass B<--tar-only> to it. The default is to
download the full source package including F<.dsc> and F<.diff.gz> or
F<.debian.tar.gz> components so B<debdiff> can be used to diff the last upload
to the next one. With B<--tar-only>, only download the F<.orig.tar.*> file.

=item B<--clean>

Remove existing files as with B<--unpack>. Note that like B<--unpack>, this
will remove upstream files even if they are stored in VCS.

=back

=cut

#=head1 CONFIGURATION VARIABLES
#
#The two configuration files F</etc/devscripts.conf> and
#F<~/.devscripts> are sourced by a shell in that order to set
#configuration variables. Command line options can be used to override
#configuration file settings. Environment variable settings are ignored
#for this purpose. The currently recognised variables are:

=head1 SEE ALSO

B<debcheckout>(1), B<gbp-import-orig>(1), B<pristine-tar>(1), B<svn-upgrade>(1), B<uupdate>(1)

=head1 AUTHOR

B<origtargz> and this manpage have been written by Christoph Berg
<I<myon@debian.org>>.

=cut

# option parsing

use strict;
use warnings;
use File::Temp qw/tempdir/;
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use Pod::Usage;

my @dirs = ();
my $tar_only = 0;
my $unpack = 'once'; # default when --unpack is not used
my $clean = 0;

GetOptions(
	"path|p=s" => \@dirs,
	"download-only|d" => sub { $unpack = 'no' },
	"help|h" => sub { pod2usage({-exitval => 0, -verbose => 1}); },
	"tar-only|t" => \$tar_only,
	"unpack|u:s" => \$unpack,
	"clean" => \$clean,
) or pod2usage({-exitval => 3});

$unpack = 'yes' if (defined $unpack and $unpack eq ''); # default for --unpack without argument
pod2usage({-exitval => 3}) if (@ARGV > 0 or $unpack !~ /^(no|once|yes)$/);

# get package name and version number

my ($package, $version, $origversion, $fileversion);

open F, "debian/changelog" or die "debian/changelog: $!\n";
my $line = <F>;
close F;
unless ($line =~ /^(\S+) \((\S+)\)/) {
	die "could not parse debian/changelog:1: $line";
}
($package, $version) = ($1, $2);
unless ($version =~ /-/) {
	print "Package with native version number $version, skipping orig.tar.* download\n";
	exit 0;
}
$origversion = $version;
$origversion =~ s/(.*)-.*/$1/; # strip everything from the last dash
$fileversion = $origversion;
$fileversion =~ s/^\d+://; # strip epoch

# functions

sub download_origtar ()
{
	# look for an existing file

	if (my @f = glob "../${package}_$fileversion.orig.tar.*") {
		print "Using existing $f[0]\n";
		return $f[0];
	}

	# try other directories

	foreach my $dir (@dirs) {
		$dir =~ s!/$!!;

		if (my @f = glob "$dir/${package}_$fileversion.orig.tar.*") {
			print "Using $f[0]\n";
			my $basename = $f[0];
			$basename =~ s!.*/!!;
			link $f[0], "../$basename" or
				symlink $f[0], "../$basename" or
				die "symlink: $!";
			return "../$basename";
		}
	}

	# try pristine-tar

	my @files = grep { /^\Q${package}_$fileversion.orig.tar.\E/ }
		map { chomp; $_; } # remove newlines
		`pristine-tar list 2>&1`;
	if (@files) {
		system "pristine-tar checkout ../$files[0]";
	}

	if (my @f = glob "../${package}_$fileversion.orig.tar.*") {
		return $f[0];
	}

	# try apt-get source

	open S, "apt-cache showsrc '$package' |";
	my @showsrc;
	{
		local $/ = ""; # slurp paragraphs
		@showsrc = <S>;
	}
	close S;

	my $bestsrcversion;
	foreach my $src (@showsrc) {
		$src =~ /^Package: (.*)/m or next;
		next if ($1 ne $package); ; # should never trigger, but who knows
		$src =~ /^Version: (.*)/m or next;
		my $srcversion = $1;
		my $srcorigversion = $srcversion;
		$srcorigversion =~ s/(.*)-.*/$1/; # strip everything from the last dash

		if ($srcorigversion eq $origversion) { # loop through all matching versions
			$bestsrcversion = $srcversion;
			last if ($srcversion eq $version); # break if exact match
		}
	}

	if ($bestsrcversion) {
		print "Trying apt-get source $package=$bestsrcversion ...\n";
		my $t = $tar_only ? '--tar-only' : '';
		system "cd .. && apt-get source --only-source --download-only $t '$package=$bestsrcversion'";
	}

	if (my @f = glob "../${package}_$fileversion.orig.tar.*") {
		return $f[0];
	}

	# try uscan

	if (-f "debian/watch") {
		print "Trying uscan --download-current-version ...\n";
		system "uscan --download-current-version --rename\n";
	}

	if (my @f = glob "../${package}_$fileversion.orig.tar.*") {
		return $f[0];
	}

	print "Could not find any location for ${package}_$fileversion.orig.tar.*\n";
	return undef;
}

sub clean_checkout ()
{
	# delete all files except debian/, our VCS checkout, and some files
	# often in VCS outside debian/ even in debian-dir-only repositories
	opendir DIR, '.' or die "opendir: $!";
	my @rm;
	while (my $file = readdir DIR) {
		next if ($file eq '.' or $file eq '..');
		next if ($file eq 'debian');
		next if ($file =~ /^(\.bzr|\.git|\.hg|\.svn|CVS|_darcs)$/);
		if ($file =~ /^(\.bzr(ignore|-builddeb)|\.gitignore|\.hgignore)$/) {
			print "Notice: not deleting $file (likely to come from VCS checkout)\n";
			next;
		}
		push @rm, $file;
	}
	close DIR;
	system ('rm', '-rf', '--', @rm);
}

sub unpack_tarball ($)
{
	my $origtar = shift;
	my $tmpdir = File::Temp->newdir(DIR => ".", CLEANUP => 1);

	print "Unpacking $origtar\n";

	# unpack
	system ('tar', "--directory=$tmpdir", '-xf', "$origtar");
	if ($? >> 8) {
		print STDERR "unpacking $origtar failed\n";
		return 0;
	}

	# figure out which directory was created
	my @dirs = glob "$tmpdir/*/";
	unless (@dirs) {
		print STDERR "unpacking $origtar did not create any directory\n";
		return 0;
	}
	my $directory = $dirs[0];
	chop $directory;

	# move all files over, except the debian directory
	opendir DIR, $directory or die "opendir $directory: $!";
	foreach my $file (readdir DIR) {
		if ($file eq 'debian') {
			system ('rm', '-rf', '--', "$directory/$file");
			next;
		} elsif ($file eq '.' or $file eq '..') {
			next;
		}
		unless (rename "$directory/$file", "$file") {
			print STDERR "rename $directory/$file $file: $!\n";
			return 0;
		}
	}
	closedir DIR;
	rmdir $directory;

	return 1;
}

# main

if ($clean) {
	clean_checkout;
	exit 0;
}

my $origtar = download_origtar;
exit 1 unless ($origtar);

if ($unpack eq 'once') {
	my @files = glob '*'; # ignores dotfiles
	if (@files == 1) { # this is debian/, we have already opened debian/changelog
		unpack_tarball ($origtar) or exit 1;
	}
} elsif ($unpack eq 'yes') {
	clean_checkout;
	unpack_tarball ($origtar) or exit 1;
}

exit 0;
