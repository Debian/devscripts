#!/usr/bin/perl
# vim: set ai shiftwidth=4 tabstop=4 expandtab:
#
# mk-origtargz: Rename upstream tarball, optionally changing the compression
# and removing unwanted files.
# Copyright (C) 2014 Joachim Breitner <nomeata@debian.org>
# Copyright (C) 2015 James McCoy <jamessan@debian.org>
#
# It contains code formerly found in uscan.
# Copyright (C) 2002-2006, Julian Gilbey
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

mk-origtargz - rename upstream tarball, optionally changing the compression and removing unwanted files

=head1 SYNOPSIS

=over

=item B<mk-origtargz> [I<options>] F<foo-1.0.tar.gz>

=item B<mk-origtargz> B<--help>

=back

=head1 DESCRIPTION

B<mk-origtargz> renames the given file to match what is expected by
B<dpkg-buildpackage>, based on the source package name and version in
F<debian/changelog>. It can convert B<zip> to B<tar>, optionally change the
compression scheme and remove files according to B<Files-Excluded> and
B<Files-Excluded->I<component> in F<debian/copyright>. The resulting file is
placed in F<debian/../..>. (In F<debian/copyright>, the B<Files-Excluded> and
B<Files-Excluded->I<component> stanzas are a part of the first paragraph and
there is a blank line before the following paragraphs which contain B<Files>
and other stanzas.  See B<uscan>(1) "COPYRIGHT FILE EXAMPLE".)

The archive type for B<zip> is detected by "B<file --dereference --brief
--mime-type>" command.  So any B<zip> type archives such as B<jar> are treated
in the same way.  The B<xpi> archive is detected by its extension and is
handled properly using the B<xpi-unpack> command.

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

Use I<version> as the version of the package. This needs to be the upstream
version portion of a full Debian version, i.e. no Debian revision, no epoch.

The default is to use the upstream portion of the version of the first entry in
F<debian/changelog>.

=item B<--exclude-file> I<glob>

Remove files matching the given I<glob> from the tarball, as if it was listed in
B<Files-Excluded>.

=item B<--copyright-file> I<filename>

Remove files matching the patterns found in I<filename>, which should have the
format of a Debian F<copyright> file 
(B<Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/>
to be precise). Errors parsing that file are silently ignored, exactly as is
the case with F<debian/copyright>.

Unmatched patterns will emit a warning so the user can verify whether it is
correct.  If there are multiple patterns which match a file, only the last one
will count as being matched.

Both the B<--exclude-file> and B<--copyright-file> options amend the list of
patterns found in F<debian/copyright>. If you do not want to read that file,
you will have to use B<--package>.

=item B<--signature> I<signature-mode>

Set I<signature-mode>:

=over

=item 0 for no signature

=item 1 for normal detached signature

=item 2 for signature on decompressed

=item 3 for self signature

=back

=item B<--signature-file> I<signature-file>

Use I<signature-file> as the signature file corresponding to the Debian source
package to create a B<dpkg-source> (post-stretch) compatible signature file.
(optional)

=back

=head2 Action options

These options specify what exactly B<mk-origtargz> should do. The options
B<--copy>, B<--rename> and B<--symlink> are mutually exclusive.

=over

=item B<--symlink>

Make the resulting file a symlink to the given original file. (This is the
default behaviour.)

If the file has to be modified (because it is a B<zip>, or B<xpi> file, because
of B<--repack> or B<Files-Excluded>), this option behaves like B<--copy>.

=item B<--copy>

Make the resulting file a copy of the original file (unless it has to be
modified, of course).

=item B<--rename>

Rename the original file.

If the file has to be modified (because it is a B<zip>, or B<xpi> file, because
of B<--repack> or B<Files-Excluded>), this implies that the original file is
deleted afterwards.

=item B<--repack>

If the given file is not compressed using the desired format (see
B<--compression>), recompress it.

=item B<-S>, B<--repack-suffix> I<suffix>

If the file has to be modified, because of B<Files-Excluded>, append I<suffix>
to the upstream version.

=item B<-c>, B<--component> I<componentname>

Use <componentname> as the component name for the secondary upstream tarball.
Set I<componentname> as the component name.  This is used only for the 
secondary upstream tarball of the Debian source package.  
Then I<packagename_version.orig-componentname.tar.gz> is created.

=item B<--compression> [ B<gzip> | B<bzip2> | B<lzma> | B<xz> | B<default> ]

The default method is B<xz>. When mk-origtargz is launched in a debian source
repository which format is "1.0" or undefined, the method switches to B<gzip>.

=item B<-C>, B<--directory> I<directory>

Put the resulting file in the given directory.

=item B<--unzipopt> I<options>

Add the extra options to use with the B<unzip> command such as B<-a>, B<-aa>,
and B<-b>.

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

use Devscripts::MkOrigtargz;

exit Devscripts::MkOrigtargz->new->do;
