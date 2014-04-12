#!/usr/bin/perl
#
# mk-origtargz: Rename upstream tarball, optionally changing the compression
# and removing unwanted files.
# Copyright (C) 2014 Joachim Breitner <nomeata@debian.org>
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


=head1 NAME

mk-origtargz - Rename upstream tarball, optionally changing the compression and removing unwanted files.

=head1 SYNOPSIS

=over

=item B<mk-origtargz> [I<OPTIONS>] F<foo-1.0.tar.gz>

=item B<mk-origtargz> B<--help>

=back

=head1 DESCRIPTION

B<mk-origtargz> renames the given file to match what is expected by
B<dpkg-buildpackage>, based on the source package name and version in
F<debian/changelog>. It can convert B<zip> to B<tar>, optionally change the
compression scheme and remove files according to B<Files-Excluded> in
F<debian/copyright>. The resulting file is placed in F<debian/../..>.

If the package name is given via the B<--package> option, no information is
read from F<debian/>, and the result file is placed in the current directory.

B<mk-origtargz> is commonly called via B<uscan>, which first obtains the
upstream tarball.

=head1 OPTIONS

=head2 Metadata options

The following options extend or replace information taken from F<debian/>.

=over

=item B<--package> I<package>

Use I<package> as the name of the Debian source package, and do not require or
use a F<debian/> directory. This option can only be used together with
B<--version>.

The default is to use the package name of the first entry in F<debian/changelog>.

=item B<-v>, B<--version> I<version>

Use I<version> as the version of the package. If I<version> is a full Debian
version, i.e. contains a dash, the upstream component is used.

The default is to use the version of the first entry in F<debian/changelog>.

=item B<--exclude-file> I<glob>

Remove files matching the given glob from the tarball, as if it was listed in
B<Fiels-Excluded>.

This option amends the list of patterns found if F<debian/copyright>. If you do
not want to read that file, you will have to use B<--package>.

=back

=head2 Action options

These options specify what exactly B<mk-origtargz> should do. The options
B<--copy>, B<--rename> and B<--symlink> are mutually exclusive.

=over

=item B<--symlink>

Make the resulting file a symlink to the given original file. (This is the
default behaviour.)

If the file has to be modified (because it is a B<zip> file, because of
B<--repack> or B<Files-Excluded>), this option behaves like B<--copy>.

=item B<--copy>

Make the resulting file a copy of the original file (unless it has to be modified, of course).

=item B<--rename>

Rename the original file (This is the default behaviour.)

If the file has to be modified (because it is a B<zip> file, because of B<--repack> or B<Files-Excluded>), this implies that the original file is deleted afterwards.

=item B<--repack>

If the given file is not in compressed using the desired format (see
B<--compression>), recompress it.

=item B<--compression> [ B<gz> | B<bzip2> | B<lzma> | B<xz> ]

If B<--repack> is used, or if the given file is a B<zip> file, ensure that the resulting file is compressed using the given scheme. The default is B<gz>.

=item B<-C>, B<--directory> I<directory>

Put the resulting file in the given directory.

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

B<uscan>(1), B<uupdate>(1)

=head1 AUTHOR

B<mk-origtargz> and this manpage have been written by Joachim Breitner
<I<nomeata@debian.org>>.

=cut

exit 0;
