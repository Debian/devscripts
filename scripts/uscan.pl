#!/usr/bin/perl
# -*- tab-width: 8; indent-tabs-mode: t; cperl-indent-level: 4 -*-

# uscan: This program looks for watchfiles and checks upstream ftp sites
# for later versions of the software.
#
# Originally written by Christoph Lameter <clameter@debian.org> (I believe)
# Modified by Julian Gilbey <jdg@debian.org>
# HTTP support added by Piotr Roszatycki <dexter@debian.org>
# Rewritten in Perl, Copyright 2002-2006, Julian Gilbey
#
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
# along with this program. If not, see <https://www.gnu.org/licenses/>.

=pod

=head1 NAME

uscan - scan/watch upstream sources for new releases of software

=head1 SYNOPSIS

B<uscan> [I<options>] [I<path>]

=head1 DESCRIPTION

For the basic usage, B<uscan> is executed without any arguments from the root
of the Debianized source tree where you see the F<debian/> directory.  Then
typically the following happens:

=over

=item * B<uscan> reads the first entry in F<debian/changelog> to determine the
source package name I<< <spkg> >> and the last upstream version.

=item * B<uscan> process the watch lines F<debian/watch> from the top to the
bottom in 1 pass.

=over

=item * B<uscan> downloads a web page from the specified I<URL> in
F<debian/watch>.

=item * B<uscan> extracts hrefs pointing to the upstream tarball(s) from the
web page using the specified I<matching-pattern> in F<debian/watch>.

=item * B<uscan> downloads the upstream tarball with the highest version newer
than the last upstream version.

=item * B<uscan> saves the downloaded tarball to the parent B<../> directory:
I<< ../<upkg>-<uversion>.tar.gz >>

=item * B<uscan> invokes B<mk-origtargz> to create the source tarball: I<<
../<spkg>_<oversion>.orig.tar.gz >>

=over

=item * Here, I<< ../<spkg>_<oversion>.orig-<component>.tar.gz >> instead for
the secondary upstream tarball of the multiple upstream tarball (MUT) package.

=back

=item * Repeat until all lines in F<debian/watch> are processed.

=back

=item * B<uscan> invokes B<uupdate> to create the Debianized source tree: I<<
../<spkg>-<oversion>/* >>

=back

Please note the following.

=over

=item * For simplicity, the compression method used in examples is B<gzip> with
B<.gz> suffix.  Other methods such as B<xz>, B<bzip2>, and B<lzma> may also be
used.

=item * The new B<version=4> enables to handle the MUT package but it is a rare
case for the Debian packaging.  For the single upstream tarball package, there
is only one watch line and no I<< ../<spkg>_<oversion>.orig-<component>.tar.gz
>> .

=item * B<uscan> with the B<--report> option produces a human readable report
without downloading the upstream tarball.

=item * B<uscan> with the B<--verbose> option produces a human readable report
of the B<uscan> execution.

=item * B<uscan> with the B<--debug> option produces a human readable report of
the B<uscan> execution with the internal variable states.

=item * B<uscan> with the B<--dehs> option produces the upstream package status
report without downloading the upstream tarball in an XML format for other
programs such as the Debian External Health System.

=back

=head1 FORMAT OF THE WATCH FILE

The current version 4 format of F<debian/watch> can be summarized as follows:

=over

=item * Leading spaces and tabs are dropped.

=item * Empty lines are dropped.

=item * A line started by B<#> (hash) is a comment line and dropped.

=item * Single B<\> (back slash) at the end of a line is dropped and the
next line is concatenated after removing leading spaces and tabs. The
concatenated line is parsed as a single line. (The existence and non-existence
of the space before the tailing single B<\> is significant.)

=item * The first non-comment line is:

=over

=item B<version=4>

=back

This is required.

=item * The following non-comment lines (watch lines) specify the rule for the
selection of the candidate upstream tarball URLs and are in one of the
following 3 formats:

=over

=item * B<opts="> I<...> B<"> B<http://>I<URL> I<matching-pattern> [I<version> [I<script>]]

=item * B<http://>I<URL> I<matching-pattern> [I<version> [I<script>]]

=item * B<opts="> I<...> B<">

=back

Here,

=over

=item * B<opts="> I<...> B<"> specifies the behavior of B<uscan>.  See L<WATCH
FILE OPTIONS>.

=item * B<http://>I<URL> specifies the web page where the upstream publishes
the link to the latest upstream source archive.

=over

=item * B<https://>I<URL> instead may be used, too.

=item * B<ftp://>I<URL> pointing to the archive directory instead may be used,
too.

=item * Some parts of I<URL> may be in the regex match pattern surrounded
between B<(> and B<)> such as B</foo/bar-([\.\d]+)/>.  (If multiple
directories match, the highest version one is picked.) Otherwise, the I<URL>
is taken as verbatim.

=back

=item * I<matching-pattern> specifies the full string matching pattern for
hrefs in the web page.  See L<WATCH FILE EXAMPLES>.

=over

=item * All matching parts in B<(> and B<)> are concatenated with B<.> (period)
to form the upstream version.

=item * If the hrefs do not contain directory, you can combine this with the
previous entry. I.e., B<http://>I<URL>B</>I<matching-pattern> .

=back

=item * I<version> limits the downloading upstream tarball.  The newest
available version is chosen for the download.

=over

=item * B<debian> limits the downloading upstream tarball to be newer than the
version obtained from F<debian/changelog>.

=item * I<version-number> such as B<12.5> limits the downloading upstream
tarball to be newer than the I<version-number>.

=item * B<same> limits the downloading version of the secondary tarballs to be
exactly the same as the one for the first upstream tarball downloaded. (useful
only for MUT)

=item * B<previous> limits the downloading version of the signature
file. (used with pgpmode=previous)

=item * B<ignore> does not limit the downloading version of the secondary
tarballs. (maybe useful for MUT)

=back

=item * I<script> is executed at the end of B<uscan> execution with appropriate
arguments provided by the B<uscan>.

=over

=item * The typical Debian package is the non-native package made from one
upstream tarball.  Only a single line of the watch line in one of the first 2
formats is usually used with its I<version> set to B<debian> and I<script>
set to B<uupdate>.

=item * The native package should skip specifying I<script>.

=item * The multiple upstream tarball package should specify B<uupdate> as
I<script> at the last watch line and should skip specifying I<script> at
the rest of the watch lines.

=back

=item * The last format of the watch line is useful to set the persistent
parameters.  If this is used, this must be followed by the I<URL> defining
watch line(s).

=item * [ and ] in the above format are there to mark the optional parts and
should not be typed.

=back

=back

=head1 WATCH FILE OPTIONS

B<uscan> reads the watch options specified in B<opts="> I<...> B<"> to
customize its behavior. Multiple options I<option1>, I<option2>, I<option3>,
... can be set as B<opts=">I<option1>B<,> I<option2>B<,> I<option3>B<,> I< ...
>B<"> .  The double quotes are necessary if options contain any spaces.

Unless otherwise noted as persistent, most options are valid only within the
watch line.

The available watch options are:

=over

=item B<component=>I<component>

Set the name of the secondary source tarball as I<<
<spkg>_<oversion>.orig-<component>.tar.gz >> for the MUT package

=item B<compression=>I<method>

Set the compression I<method> when it is repacked. (persistent)

Available I<method> values are B<xz>, B<gzip> (alias B<gz>), B<bzip2> (alias
B<bz2>), and B<lzma>.

Please note the repack of the upstream tarballs happen only if one of the
following condition satisfied:

=over

=item * B<USCAN_REPACK> is set in the devscript configuration.  See L<DEVSCRIPT
CONFIGURATION VARIABLES>.

=item * B<--repack> is set in the commandline.  See <COMMANDLINE OPTIONS>.

=item * B<repack> is set in the watch line as B<opts=>I<...>.

=item * The upstream tarballs contain files listed under the B<Files-Excluded>
and B<Files-Excluded->I<component> stanza of F<debian/copyright>.  See
mk-origtargz(1).

=back

=item B<repack>

Force to repack the upstream tarball using the compression I<mathod>.

=item B<repacksuffix=>I<suffix>

Add I<suffix> to the version as suffix when the source tarball is repackaged.
This rule should be used only for the single upstream package.

=item B<pgpmode=>I<mode>

Set the pgp/gpg signature verification I<mode>.

=over

=item B<mangle>

Use B<pgpsigurlmangle=>I<rules> to generate the candidate upstream signature
file URL string from the upstream tarball URL. (default)

=item B<next>

Verify this downloaded file by the next downloaded signature file.  The next watch line must be B<previous>.  Otherwise, no verification.

=item B<previous>

Verify the previous downloaded file by this signature file.  The previous watch line must be B<next>.

=item B<self>

Verify the file by the self signature

=item B<none>

No signature available. (No warning.)

=back

=item B<decompress>

Decompress compressed archive before the pgp/gpg signature verification.

=item B<user-agent=>I<user-agent-string>

Set the user-agent string used to contact the HTTP(S) server as
I<user-agent-string>. (persistent)

B<user-agent> option should be specified by itself in the watch line without
I<URL> and other options to allow using semicolons and commas in it.

=item B<pasv>, B<passsive>

Use PASV mode for the FTP connection.

If the PASV mode is required due to the client side network environment, set
B<uscan> to use PASV mode via L<COMMANDLINE OPTIONS> or L<DEVSCRIPT
CONFIGURATION VARIABLES> instead.

=item B<active>, B<nopasv>

Don't use PASV mode for the FTP connection.

=item B<dversionmangle=>I<rules>

Normalize the last upstream version string found in F<debian/changelog>.  Removal of upstream repackage mark by B<+s/dfsg\d+$//> is usually done here.

=item B<dirversionmangle=>I<rules>

Normalize the directory path string matching the regex in a set of parentheses
of B<http::/>I<URL> as the sortable version string.  This is used as the
sorting index only.

=item B<pagemangle=>I<rules>

Normalize the downloaded web page string.  (Do not use this unless this is absolutely needed.  B<s> rules should be appled with B<g> option.)

=item B<uversionmangle=>I<rules>

Normalize the candidate upstream version strings extracted from hrefs in the
source of the web page.  This is used as the sorting index when selecting the
latest upstream version.

=item B<versionmangle=>I<rules>

Syntactic shorthand for B<uversionmangle=>I<rules>B<,dversionmangle=>I<rules>

=item B<oversionmangle=>I<rules>

Generate the version string I<< <oversion> >> of the source tarball I<<
<spkg>_<oversion>.orig.tar.gz >> from I<< <uversion> >>.

=item B<filenamemangle=>I<rules>

Normalize the downloaded tarball filename string I<< <upkg>-<uversion>.tar.gz
>>.

=item B<downloadurlmangle=>I<rules>

Normalize the candidate upstream tarball URL string.

=item B<pgpsigurlmangle=>I<rules>

Generate the candidate upstream signature file URL string from the upstream
tarball URL.

=back

Here, the mangling rules apply the I<rules> to the pertinent string.  Multiple
rules can be specified in a mangling rule by making a concatenated string of
each mangling I<rule> separated by B<;> (semicolon).

Each mangling I<rule> can not contain B<;> (semicolon) nor B<,> (comma).

Each mangling I<rule> behaves as if a Perl command "I<$string> B<~=>
I<rule>" is executed.  There are some notable details.

=over

=item * I<rule> may only use the B<s>, B<tr>, and B<y> operations.

=over

=item B<s/>I<regex>B</>I<replacement>B</>I<options>

Regex pattern match and replace the target string.  Only the B<g>, B<i> and
B<x> flags are available.  Use the B<$1> syntax for the back reference (No
B<\1> syntax).  Code execution is not allowed (i.e. No B<(?{})> nor B<(??{})>
constructs).

=item B<y/>I<source>B</>I<dest>B</> or B<tr/>I<source>B</>I<dest>B</>

Transliterate the characters in the target string.

=back

=back

=head1 EXAMPLE OF EXECUTION

B<uscan> reads the first entry in F<debian/changelog> to determine the source
package name and the last upstream version.

For example, if the first entry of F<debian/changelog> may be:

=over

=item * I<< bar >> (B<3:2.03+dfsg1-4>) unstable; urgency=low

=back

then, the source package name is I<< bar >> and the last upstream version
is B<3:2.03+dfsg1-4>.

The last upstream version is normalized to B<2.03+dfsg1> by removing the epoch
and the Debian revision.

If the B<dversionmangle> rule exists, the last upstream version is further
normalized by applying this rule to it.  For example, if the last upstream
version is B<2.03+dfsg1> indicating the source tarball is repackaged, the
suffix B<+dfsg1> is removed by the string substitution B<s/\+dfsg\d*$//> to
make the (dversionmangled) last upstream version B<2.03> and it is compared to
the candidate upstream tarball versions such as B<2.03>, B<2.04>, ... found in
the remote site.  Thus, set this rule as:

=over

=item * B<opts="dversionmangle=s/\+dfsg\d*$//">

=back

B<uscan> downloads a web page from B<http://>I<URL> specified in
F<debian/watch>.

=over

=item * If the directory name part of I<URL> has no parentheses, B<(> and B<)>,
it is taken as verbatim.

=item * If the directory name part of I<URL> has parentheses, B<(> and B<)>,
then B<uscan> recursively searches all possible directories to find a page for
the newest version.

=back

For example, this B<http://>I<URL> may be specified as:

=over

=item * B<http://www.example.org/DL(.+)/>

=back

Please note the trailing B</> in the above.

If the B<pagemangle> rule exists, the whole downloaded web page as a string is
normalized by applying this rule to it.  This is very powerful tool and needs to
be used with caution.  If other mangling rules can be used to address your
objective, do not use this rule.

The downloaded web page is scanned for hrefs defined in the B<< <a href=" >>
I<...> B<< "> >> tag to locate the candidate upstream tarball URLs.  These
candidate upstream tarball URLs are matched by the Perl regex pattern
I<matching-pattern> such as B<< DL-(?:[\d\.]+?)/foo-(.+)\.tar\.gz >> to
narrow down the candidates.  This pattern match needs to be anchored at the
beginning and the end.  For example, candidate URLs may be:

=over

=item * B<< DL-2.02/foo-2.02.tar.gz >>

=item * B<< DL-2.03/foo-2.03.tar.gz >>

=item * B<< DL-2.04/foo-2.04.tar.gz >>

=back

Here the matching string of B<(.+)> in I<matching-pattern> is considered as the
candidate upstream version.  If there are multiple matching strings of
capturing patterns in I<matching-pattern>, they are all concatenated with B<.>
(period) to form the candidate upstream version.  Make sure to use the
non-capturing regex such as B<(?:[\d\.]+?)> instead for the variable text
matching part unrelated to the version.

Then, the candidate upstream versions are:

=over

=item * B<2.02>

=item * B<2.03>

=item * B<2.04>

=back

The downloaded tarball filename is basically set to the same as its filename in
the remote URL.

If the B<uversionmangle> rule exists, the candidate upstream versions are
normalized by applying this rule to them. (This rule may be useful if the
upstream version scheme doesn't sort correctly to identify the newest
version.)

The upstream tarball URL corresponding to the newest (uversionmangled) candidate
upstream version newer than the (dversionmangled) last upstream version is
selected to be the candidate upstream tarball URL.

Here, the order of the version is decided by B<dpkg --compare-versions>.

If the B<filenamemangle> rule exists, the downloaded tarball filename is
normalized by applying this rule to it. (This rule may not be as significant
for modern use cases.  B<mk-origtargz> takes care the proper renaming of the
source tarballs into <spkg>_<oversion>.orig.tar.gz based on the source package
name in F<debian/changelog> without relying on the filename of the remote URL.
Now, B<uupdate> is invoked by B<uscan> with B<--find> option and is not
expected to rename the downloaded tarball anymore.)

If the candidate upstream tarball URL is a relative URL, it is converted to a
absolute URL using the base URL of the web page.  If the B<< <base href=" >> I<
... > B<< "> >> tag exists in the web page, the candidate upstream tarball URL
is converted to the absolute URL using the specified base URL in the base tag,
instead.

If the B<downloadurlmangle> rule exists, the candidate upstream tarball URL is
normalized by applying this rule to it. (This is useful for some sites with the
obfuscated download URL.)

B<uscan> downloads the candidate upstream tarball to the parent B<../>
directory.  For example, the downloaded file may be:

=over

=item * F<../foo-2.04.tar.gz>

=back

Let's call this downloaded version B<2.04> in the above example generically as
I<< <uversion> >> in the following.

If the B<pgpsigurlmangle> rule exists, the upstream signature file URL is
generated by applying this rule to the (downloadurlmangled) candidate upstream
tarball URL and the signature file is tried to be downloaded.

If the B<pgpsigurlmangle> rule doesn't exist, B<uscan> warns user if the
matching upstream signature file is available from the same URL with their
filename being suffixed by the 4 common suffix B<asc>, B<gpg>, B<pgp>, and
B<sig>.

If the signature file is downloaded, the downloaded upstream tarball is checked
for its authenticity against the downloaded signature file using the keyring
F<debian/upstream/signing-key.pgp> or
the armored keyring F<debian/upstream/signing-key.asc>. If its signature is not
valid, or not made by one of the listed keys, B<uscan> will report an error.

If the B<oversionmangle> rule exists, the source tarball version I<oversion> is
generated from the downloaded upstream version I<uversion> by applying this
rule. This rule is useful to add suffix such as B<+dfsg1> to the version of all
the source packages of the MUT package for which the repacksuffix mechanism
doesn't work well.

B<uscan> invokes B<mk-origtargz> to create the source tarball properly named
for the source package with B<.orig.> in its filename.

=over

=item case A: packaging of the upstream tarball as is

B<mk-origtargz> creates a symlink I<< ../bar_<oversion>.orig.tar.gz >>
linked to the downloaded local upstream tarball. Here, I<< bar >> is the source
package name found in F<debian/changelog>. The generated symlink may be:

=over

=item * F<../bar_2.04.orig.tar.gz> -> F<foo-2.04.tar.gz> (as is)

=back

Usually, there is no need to set up B<opts="dversionmangle=> I<...> B<"> for
this case.

=item case B: packaging of the upstream tarball after removing non-DFSG files

B<mk-origtargz> checks the filename glob of the B<Files-Excluded> stanza in the
first section of F<debian/copyright>, removes matching files to create a
repacked upstream tarball.  Normally, the repacked upstream tarball is renamed
with I<suffix> to I<< ../bar_<oversion><suffix>.orig.tar.gz >> using
the B<repacksuffix> option for the single upstream package.    Here I<< <oversion> >>
is updated to be I<< <oversion><suffix> >>.

The removal of files is required if files are not DFSG-compliant.  For such
case, B<+dfsg1> is used as I<suffix>.

So the combined options are set as
B<opts="dversionmangle=s/\+dfsg\d*$// ,repacksuffix=+dfsg1">, instead.

For example, the repacked upstream tarball may be:

=over

=item * F<../bar_2.04+dfsg1.orig.tar.gz> (repackaged)

=back

=back

B<uscan> normally invokes "B<uupdate> B<--find --upstream-version>
I<oversion> " for the version=4 watch file.

Please note that B<--find> option is used here since B<mk-origtargz> has been
invoked to make B<*.orig.tar.gz> file already.  B<uscan> picks I<< bar >> from
F<debian/changelog>.

It creates the new upstream source tree under the
I<< ../bar-<oversion> >> directory and Debianize it leveraging the
last package contents.

=head1 WATCH FILE EXAMPLES

When writing the watch file, you should rely on the latest upstream source
announcement web page.  You should not try to second guess the upstream archive
structure if possible.  Here are the typical F<debian/watch> files.

The existence and non-existence of a space before tailing B<\> (back slash) are
significant.

=head2 HTTP site (basic)

For the basic single upstream tarball case:

  version=4
  http://example.com/~user/release/foo.html \
  files/foo-([\d\.]*).tar.gz debian uupdate

For the upstream source package is B<foo-2.0.tar.gz>, this watch file downloads
and creates the Debian orig.tar file B<foo_2.0.orig.tar.gz>.

=head2 HTTP site (pgpsigurlmangle)

For the basic single upstream tarball with the matching signature file in the
same file path case:

  version=4
  opts="pgpsigurlmangle=s%(.*)%$1.asc%" \
  http://example.com/~user/release/foo.html \
  files/foo-([\d\.]*).tar.gz debian uupdate

For the upstream source package B<foo-2.0.tar.gz> and the upstream signature
file B<foo-2.0.tar.gz.asc>, this watch file downloads files, verify its
authenticity using F<debian/upstream-key.pgp> and creates the Debian orig.tar
file B<foo_2.0.orig.tar.gz>.

=head2 HTTP site (pgpmode)

For the basic single upstream tarball with the matching signature file not in
the same file path case:

  version=4
  opts="pgpmode=next" \
  http://example.com/~user/release/foo.html \
  files/(?:\d*)/foo-([\d\.]*).tar.gz debian
  opts="pgpmode=previous" \
  http://example.com/~user/release/foo.html \
  files/(?:\d+)/foo-([\d\.]*).tar.gz.asc previous uupdate

Please note the upstream tarball and the signature file share the same version
number.

=head2 HTTP site (basic MUT)

For the basic 2 upstream tarball case:

  version=4
  http://example.com/~user/release/foo.html \
  files/foo-([\d\.]*).tar.gz debian true
  opts=component=baz \
  http://example.com/~user/release/foo.html \
  files/baz-([\d\.]*).tar.gz same uupdate

For the main upstream source package B<foo-2.0.tar.gz> and the secondary
upstream source package B<bar-2.0.tar.gz> which installs under F<baz/>, this
watch file downloads and creates the Debian orig.tar file
B<foo_2.0.orig.tar.gz> and B<foo_2.0.orig-baz.tar.gz>.


=head2 HTTP site (flexible)

For the maximum flexibility of upstream tarball and signature file extensions:

  version=4
  opts="pgpmode=next" http://example.com/DL/ \
  files/(?:\d*)/example-(\d[\d.]*)\.\
  (?:zip|tgz|tbz2|txz|tar\.(?:gz|bz2|xz)) debian
  opts="pgpmode=prevous" http://example.com/DL/ \
  files/(?:\d*)/example-(\d[\d.]*)\.\
  (?:zip|tgz|tbz2|txz|tar\.(?:gz|bz2|xz)\.(?:asc|pgp|gpg|sig)) \
  previous uupdate

=head2 HTTP site (recursive directory scanning)

For recursive directory scanning:

  version=4
  http://tmrc.mit.edu/mirror/twisted/Twisted/(\d\.\d)/ \
  Twisted-([\d\.]*)\.tar\.xz debian uupdate

or in one string style variant

  version=4
  http://tmrc.mit.edu/mirror/twisted/\
  Twisted/(\d\.\d)/Twisted-([\d\.]*)\.tar\.xz debian uupdate

Here, the web site should be able to handle requests to:

  http://tmrc.mit.edu/mirror/twisted/Twisted/

=head2 HTTP site (alternative)

For one string style:

  version=4
  http://www.cpan.org/modules/by-module/Text/Text-CSV_XS-(.+)\.tar\.gz \
  debian uupdate

This is the same as

  version=4
  http://www.cpan.org/modules/by-module/Text Text-CSV_XS-(.+)\.tar\.gz \
  debian uupdate

=head2 HTTP site (sf.net)

For SourceForge based projects, qa.debian.org runs a redirector which allows a
simpler form of URL. The format below will automatically be rewritten to use
the redirector.

  version=4
  http://sf.net/audacity/audacity-src-(.+)\.tar\.gz uupdate

=head2 HTTP site (github.com)

For GitHub projects, you can use the tags or releases page.  The archive URLs
use only the version as the filename.  You can rename the downloaded upstream
tarball into standard I<project>B<->I<version>B<.tar.gz> using
B<filenamemangle>:

  version=4
  opts="filenamemangle=\
  s/(?:.*?)?v?(\d[\d.]*)\.tar\.gz/<project>-$1.tar.gz/" \
  https://github.com/<user>/<project>/tags \
  (?:.*?/)?v?(\d[\d.]*)\.tar\.gz debian uupdate

=head2 HTTP site (code.google.com)

Sites which used to be hosted on the Google Code service should have migrated
to elsewhere (github?).  Please look for the newer upstream site.

=head2 HTTP site (funny version)

For a site which has funny version numbers, the parenthesized groups will be
joined with B<.> (period) to make a sanitized version number.

  version=4
  http://www.site.com/pub/foobar/foobar_v(\d+)_(\d+)\.tar\.gz \
  debian uupdate

=head2 HTTP site (DFSG)

The upstream part of the Debian version number can be mangled to indicate the
source package was repackaged to clean up non-DFSG files:

  version=4
  opts="dversionmangle=s/\+dfsg\d*$//,repacksuffix=+dfsg1" \
  http://some.site.org/some/path/foobar-(.+)\.tar\.gz debian uupdate

See L<COPYRIGHT FILE EXAMPLES>.

=head2 HTTP site (filenamemangle)

The upstream tarball filename is found by taking the last component of the URL
and removing everything after any '?'.  If that leaves nothing for filename,
B<uscan> generate filename using the source package name in
B<debian/changelog>, the new version, and suffix B<.download> .

If this does not fit to you, use B<filenamemangle>.  For example, F<< <A
href="http://foo.bar.org/dl/?path=&dl=foo-0.1.1.tar.gz"> >> could be handled
as:

  version=4
  opts=filenamemangle=s/.*=(.*)/$1/ \
  http://foo.bar.org/dl/\?path=&dl=foo-(.+)\.tar\.gz \
  debian uupdate

F<< <A href="http://foo.bar.org/dl/?path=&dl_version=0.1.1"> >>
could be handled as:

  version=4
  opts=filenamemangle=s/.*=(.*)/foo-$1\.tar\.gz/ \
  http://foo.bar.org/dl/\?path=&dl_version=(.+) \
  debian uupdate

=head2 HTTP site (downloadurlmangle)

The option B<downloadurlmangle> can be used to mangle the URL of the file
to download.  This can only be used with B<http://> URLs.  This may be
necessary if the link given on the web page needs to be transformed in
some way into one which will work automatically, for example:

  version=4
  opts=downloadurlmangle=s/prdownload/download/ \
  http://developer.berlios.de/project/showfiles.php?group_id=2051 \
  http://prdownload.berlios.de/softdevice/vdr-softdevice-(.+).tgz \
  debian uupdate

=head2 HTTP site (oversionmangle, MUT)

The option B<oversionmangle> can be used to mangle the version of the source
tarball (B<.orig.tar.gz> and B<.orig-bar.tar.gz>).  For example, B<+dfsg1> can
be added to the upstream version as:

  version=4
  opts=oversionmangle=s/(.*)/$1+dfsg1/ \
  http://example.com/~user/release/foo.html \
  files/foo-([\d\.]*).tar.gz debian
  opts="component=bar" \
  http://example.com/~user/release/foo.html \
  files/bar-([\d\.]*).tar.gz same uupdate

See L<COPYRIGHT FILE EXAMPLES>.

=head2 HTTP site (pagemangle)

The option B<pagemangle> can be used to mangle the downloaded web page before
applying other rules.  The non-standard web page without proper B<< <a href="
>> << ... >> B<< "> >> entries can be converted.  For example, if F<foo.html>
uses B<< <a bogus=" >> I<< ... >> B<< "> >>, this can be converted to the
standard page format with:

  version=4
  opts=pagemangle="s/<a\s+bogus=/<a href=/g" \
  http://example.com/release/foo.html \
  files/foo-([\d\.]*).tar.gz debian uupdate

Please note the use of B<g> here to replace all occurrences.

If F<foo.html> uses B<< <Key> >> I<< ... >> B<< </Key> >>, this can be
converted to the standard page format with:

  version=4
  opts="pagemangle=s%<Key>([^<]*)</Key>%<Key><a href="$1">$1</a></Key>%g" \\
  http://localhost:$PORT/ \
  (?:.*)/$PKG-([\d\.]+).tar.gz debian uupdate

=head2 FTP site (basic):

  version=4
  ftp://ftp.tex.ac.uk/tex-archive/web/c_cpp/cweb/cweb-(.+)\.tar\.gz \
  debian uupdate

=head2 FTP site (regex special characters):

  version=4
  ftp://ftp.worldforge.org/pub/worldforge/libs/\
  Atlas-C++/transitional/Atlas-C\+\+-(.+)\.tar\.gz debian uupdate

Please note that this URL is connected to be I< ... >B<libs/Atlas-C++/>I< ... >
. For B<++>, the first one in the directory path is verbatim while the one in
the filename is escaped by B<\>.

=head2 FTP site (funny version)

This is another way of handling site with funny version numbers,
this time using mangling.  (Note that multiple groups will be
concatenated before mangling is performed, and that mangling will
only be performed on the basename version number, not any path
version numbers.)

  version=4
  opts="uversionmangle=s/^/0.0./" \
  ftp://ftp.ibiblio.org/pub/Linux/ALPHA/wine/\
  development/Wine-(.+)\.tar\.gz debian uupdate


=head1 COPYRIGHT FILE EXAMPLES

Here is an example for the F<debian/copyright> file which initiates automatic repackaging of the upstream tarball into I<< <spkg>_<oversion>.orig.tar.gz >>:

  Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
  Files-Excluded: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js

   ...

Here is another example for the F<debian/copyright> file which initiates automatic repackaging of the multiple upstream tarballs into I<< <spkg>_<oversion>.orig.tar.gz >> and I<< <spkg>_<oversion>.orig-bar.tar.gz >>:

  Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
  Files-Excluded: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js
  Files-Excluded-bar: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js

   ...

See mk-origtargz(1).

=head1 COMMANDLINE OPTIONS

For the basic usage, B<uscan> does not require to set these options.

=over

=item B<--report>, B<--no-download>

Only report about available newer versions but do not download
anything.

=item B<--report-status>

Report on the status of all packages, even those which are up-to-date,
but do not download anything.

=item B<--download>

Report and download. (This is the default behavior.)

=item B<--destdir>

Path of directory to which to download. If the specified path is not absolute,
it will be relative to one of the current directory or, if directory scanning
is enabled, the package's
source directory.

=item B<--force-download>

Download upstream even if up-to-date (will not overwrite local files, however)

=item B<--pasv>

Force PASV mode for FTP connections.

=item B<--no-pasv>

Do not use PASV mode for FTP connections.

=item B<--timeout> I<N>

Set timeout to I<N> seconds (default 20 seconds).

=item B<--no-symlink>

Do not call B<mk-origtargz>.

=item B<--dehs>

Use an XML format for output, as required by the DEHS system.

=item B<--no-dehs>

Use the traditional uscan output format. (This is the default behavior.)

=item B<--package> I<package>

Specify the name of the package to check for rather than examining
F<debian/changelog>; this requires the B<--upstream-version> (unless a version
is specified in the F<watch> file) and B<--watchfile> options as well.
Furthermore, no directory scanning will be done and nothing will be downloaded.
This option is probably most useful in conjunction with the DEHS system (and
B<--dehs>).

=item B<--upstream-version> I<upstream-version>

Specify the current upstream version rather than examine F<debian/watch> or
F<debian/changelog> to determine it. This is ignored if a directory scan is being
performed and more than one F<debian/watch> file is found.

=item B<--watchfile> I<watchfile>

Specify the I<watchfile> rather than perform a directory scan to
determine it. If this option is used without B<--package>, then
B<uscan> must be called from within the Debian package source tree
(so that F<debian/changelog> can be found simply by stepping up
through the tree).

=item B<--download-version> I<version>

Specify the I<version> which the upstream release must match in order to be
considered, rather than using the release with the highest version.

=item B<--download-current-version>

Download the currently packaged version

=item B<--verbose>

Give verbose output.

=item B<--no-verbose>

Don't give verbose output.  (This is the default behavior.)

=item B<--no-exclusion>

Do not automatically exclude files mentioned in F<debian/copyright> field B<Files-Excluded>

=item B<--debug>

Dump the downloaded web pages to stdout for debugging your F<watch> file.

=item B<--check-dirname-level> I<N>

See the below section L<Directory name checking> for an explanation of this option.

=item B<--check-dirname-regex> I<regex>

See the below section L<Directory name checking> for an explanation of this option.

=item B<--user-agent>, B<--useragent>

Override the default user agent header.

=item B<--no-conf>, B<--noconf>

Do not read any configuration files. This can only be used as the first option
given on the command-line.

=item B<--help>

Give brief usage information.

=item B<--version>

Display version information.

=back

B<uscan> also accepts following options and passes them to B<mk-origtargz>:

=over

=item B<--symlink>

Make B<orig.tar.gz> (with the appropriate extension) symlink to the downloaded
files. (This is the default behavior.)

=item B<--copy>

Instead of symlinking as described above, copy the downloaded files.

=item B<--rename>

Instead of symlinking as described above, rename the downloaded files.

=item B<--repack>

After having downloaded an lzma tar, xz tar, bzip tar or zip archive, repack it
to a gzip tar archive, if required. The unzip package must be installed in
order to repack .zip archives, the xz-utils package must be installed to repack
lzma or xz tar archives.

=item B<--compression> [ B<gzip> | B<bzip2> | B<lzma> | B<xz> ]

In the case where the upstream sources are repacked (either because B<--repack>
option is given or F<debian/copyright> contains the field B<Files-Excluded>), it is
possible to control the compression method via the parameter (defaults to
B<gzip>).

=item B<--copyright-file> I<copyright-file>

Exclude files mentioned in B<Files-Excluded> in the given I<copyright-file>.
This is useful when running B<uscan> not within a source package directory.

=back

=head1 DEVSCRIPT CONFIGURATION VARIABLES

For the basic usage, B<uscan> does not require to set these configuration
variables.

The two configuration files F</etc/devscripts.conf> and F<~/.devscripts> are
sourced by a shell in that order to set configuration variables. These
may be overridden by command line options. Environment variable settings are
ignored for this purpose. If the first command line option given is
B<--noconf>, then these files will not be read. The currently recognized
variables are:

=over

=item B<USCAN_DOWNLOAD>

If this is set to B<no>, then newer upstream files will not be downloaded; this
is equivalent to the B<--report> or B<--no-download> options.

=item B<USCAN_PASV>

If this is set to yes or no, this will force FTP connections to use PASV mode
or not to, respectively. If this is set to default, then B<Net::FTP(3)> makes
the choice (primarily based on the B<FTP_PASSIVE> environment variable).

=item B<USCAN_TIMEOUT>

If set to a number I<N>, then set the timeout to I<N> seconds. This is
equivalent to the B<--timeout> option.

=item B<USCAN_SYMLINK>

If this is set to no, then a I<pkg>_I<version>B<.orig.tar.{gz|bz2|lzma|xz}>
symlink will not be made (equivalent to the B<--no-symlink> option). If it is
set to B<yes> or B<symlink>, then the symlinks will be made. If it is set to
rename, then the files are renamed (equivalent to the B<--rename> option).

=item B<USCAN_DEHS_OUTPUT>

If this is set to B<yes>, then DEHS-style output will be used. This is
equivalent to the B<--dehs> option.

=item B<USCAN_VERBOSE>

If this is set to B<yes>, then verbose output will be given.  This is
equivalent to the B<--verbose> option.

=item B<USCAN_USER_AGENT>

If set, the specified user agent string will be used in place of the default.
This is equivalent to the B<--user-agent> option.

=item B<USCAN_DESTDIR>

If set, the downloaded files will be placed in this  directory.  This is
equivalent to the B<--destdir> option.

=item B<USCAN_REPACK>

If this is set to yes, then after having downloaded a bzip tar, lzma tar, xz
tar, or zip archive, uscan will repack it to a gzip tar. This is equivalent to
the B<--repack> option.

=item B<USCAN_EXCLUSION>

If this is set to no, files mentioned in the field B<Files-Excluded> of
F<debian/copyright> will be ignored and no exclusion of files will be tried.
This is equivalent to the B<--no-exclusion> option.

=back

=head1 EXIT STATUS

The exit status gives some indication of whether a newer version was found or
not; one is advised to read the output to determine exactly what happened and
whether there were any warnings to be noted.

=over

=item B<0>

Either B<--help> or B<--version> was used, or for some F<watch> file which was
examined, a newer upstream version was located.

=item B<1>

No newer upstream versions were located for any of the F<watch> files examined.

=back

=head1 ADVANCED FEATURES

B<uscan> has many other enhanced features which are skipped in the above
section for the simplicity.  Let's check their highlights.

B<uscan> actually scans not just the current directory but all its
subdirectories looking for F<debian/watch> to process them all.
See L<Directory name checking>.

B<uscan> can be executed with I<path> as its argument to change the starting
directory of search from the current directory to I<path> .

See L<COMMANDLINE OPTIONS> and L<DEVSCRIPT CONFIGURATION VARIABLES> for other
variations.

=head2 Custom script

The optional I<script> parameter F<debian/watch> means to execute I<script>
with options after processing this line if specified.  You can customize this 
by specifying F<debian/myuupdate> as I<script> and create an executable file
F<debian/myuupdate> with the following content.

  #!/bin/sh -e
  # called with --upstream-version <version>
  uupdate --find "$@"
  package=`dpkg-parsechangelog | sed -n 's/^Source: //p'`
  cd ../$package-$2
  debuild

Then B<uscan> invokes "I<debian/myuupdate> B<--upstream-version> I<version>" to
perform a fully automatic upstream update of Debian binary packages.

Note that we don't call B<dupload> or B<dput> automatically, as the maintainer
should perform sanity checks on the software before uploading it to Debian.

Also, for compatibility with other tools such as B<git-buildpackage>, it may not
be wise to create this kind of custom scripts.  In general, B<uupdate> is
the best choice for the non-native package.

=head2 Directory name checking

Similarly to several other scripts in the B<devscripts> package, B<uscan>
explores the requested directory trees looking for F<debian/changelog> and
F<debian/watch> files. As a safeguard against stray files causing potential
problems, and in order to promote efficiency, it will examine the name of the
parent directory once it finds the F<debian/changelog> file, and check that the
directory name corresponds to the package name. It will only attempt to
download newer versions of the package and then perform any requested action if
the directory name matches the package name. Precisely how it does this is
controlled by two configuration file variables
B<DEVSCRIPTS_CHECK_DIRNAME_LEVEL> and B<DEVSCRIPTS_CHECK_DIRNAME_REGEX>, and
their corresponding command-line options B<--check-dirname-level> and
B<--check-dirname-regex>.

B<DEVSCRIPTS_CHECK_DIRNAME_LEVEL> can take the following values:

=over

=item B<0>

Never check the directory name.

=item B<1>

Only check the directory name if we have had to  change  directory in
our search for F<debian/changelog>, that is, the directory containing
F<debian/changelog> is not  the  directory  from  which B<uscan> was invoked.  This
is the default behavior.

=item B<2>

Always check the directory name.

=back

The directory name is checked by testing whether the current directory name (as
determined by pwd(1)) matches the regex given by the configuration file
option B<DEVSCRIPTS_CHECK_DIRNAME_REGEX> or by the command line option
B<--check-dirname-regex> I<regex>. Here regex is a Perl regex (see
perlre(3perl)), which will be anchored at the beginning and the end. If regex
contains a B</>, then it must match the full directory path. If not, then
it must match the full directory name. If regex contains the string I<package>,
this will be replaced by the source package name, as determined from the
F<debian/changelog>. The default value for the regex is: I<package>B<(-.+)?>, thus matching
directory names such as I<package> and I<package>-I<version>.

=head1 HISTORY AND UPGRADING

This section briefly describes the backwards-incompatible F<watch> file features
which have been added in each F<watch> file version, and the first version of the
B<devscripts> package which understood them.

=over

=item Pre-version 2

The F<watch> file syntax was significantly different in those days. Don't use it.
If you are upgrading from a pre-version 2 F<watch> file, you are advised to read
this manpage and to start from scratch.

=item Version 2

B<devscripts> version 2.6.90: The first incarnation of the current style of
F<watch> files.

=item Version 3

B<devscripts> version 2.8.12: Introduced the following: correct handling of
regex special characters in the path part, directory/path pattern matching,
version number in several parts, version number mangling. Later versions
have also introduced URL mangling.

If you are upgrading from version 2, the key incompatibility is if you have
multiple groups in the pattern part; whereas only the first one would be used
in version 2, they will all be used in version 3. To avoid this behavior,
change the non-version-number groups to be B<(?:> I< ...> B<)> instead of a
plain B<(> I< ... > B<)> group.

B<uscan> invokes the custom I<script> as "I<script> B<--upstream-version>
I<version> B<../>I<spkg>B<_>I<version>B<.orig.tar.gz>".

B<uscan> invokes the standard B<uupdate> as "B<uupdate> B<--no-symlink
--upstream-version> I<version> B<../>I<spkg>B<_>I<version>B<.orig.tar.gz>".

=item Version 4

Although you can have multiple watch lines with different URLs to keep your eyes
on a single tarball under the version 3, it is not allowed under the version 4.
This is to ensure the proper function of B<uupdate>.

If you have custom script in place of B<uupdate>, you may also encounter
problems.

B<uscan> invokes the custom I<script> as "I<script> B<--upstream-version>
I<version>".

B<uscan> invokes the standard B<uupdate> as "B<uupdate> B<--find>
B<--upstream-version> I<version>".

=back

=head1 SEE ALSO

dpkg(1), mk-origtargz(1), perlre(1), uupdate(1), devscripts.conf(5)

=head1 AUTHOR

The original version of uscan was written by Christoph Lameter
<clameter@debian.org>. Significant improvements, changes and bugfixes were
made by Julian Gilbey <jdg@debian.org>. HTTP support was added by Piotr
Roszatycki <dexter@debian.org>. The program was rewritten in Perl by Julian
Gilbey.

=cut

use 5.010;  # defined-or (//)
use strict;
use warnings;
use Cwd;
use Cwd 'abs_path';
use Dpkg::Changelog::Parse qw(changelog_parse);
use Dpkg::IPC;
use File::Basename;
use File::Copy;
use File::Temp qw/tempfile tempdir/;
use List::Util qw/first/;
use filetest 'access';
use Getopt::Long qw(:config gnu_getopt);
use Devscripts::Versort;
use Text::ParseWords;
BEGIN {
    eval { require LWP::UserAgent; };
    if ($@) {
	my $progname = basename($0);
	if ($@ =~ /^Can\'t locate LWP\/UserAgent\.pm/) {
	    die "$progname: you must have the libwww-perl package installed\nto use this script\n";
	} else {
	    die "$progname: problem loading the LWP::UserAgent module:\n  $@\nHave you installed the libwww-perl package?\n";
	}
    }
}
use Dpkg::Control::Hash;

my $CURRENT_WATCHFILE_VERSION = 4;

my $progname = basename($0);
my $modified_conf_msg;
my $opwd = cwd();

my $haveSSL = 1;
eval { require LWP::Protocol::https; };
if ($@) {
    $haveSSL = 0;
}
my $havegpgv = first { -x $_ } qw(/usr/bin/gpgv2 /usr/bin/gpgv);
my $havegpg = first { -x $_ } qw(/usr/bin/gpg2 /usr/bin/gpg);

# Did we find any new upstream versions on our wanderings?
our $found = 0;

sub process_watchline ($$$$$$);
sub process_watchfile ($$$$);
sub check_compression ($);
sub recursive_regex_dir ($$$);
sub newest_dir ($$$$$);
sub dehs_msg ($);
sub uscan_warn (@);
sub uscan_die (@);
sub dehs_output ();
sub quoted_regex_replace ($);
sub safe_replace ($$);

sub usage {
    print <<"EOF";
Usage: $progname [options] [dir ...]
  Process watchfiles in all .../debian/ subdirs of those listed (or the
  current directory if none listed) to check for upstream releases.
Options:
    --report       Only report on newer or absent versions, do not download
    --report-status
                   Report status of packages, but do not download
    --debug        Dump the downloaded web pages to stdout for debugging
                   your watch file.
    --destdir      Path of directory to which to download.
    --download     Report on newer and absent versions, and download (default)
    --force-download
                   Always download the upstream release, even if up to date
    --no-download  Report on newer and absent versions, but don\'t download
    --pasv         Use PASV mode for FTP connections
    --no-pasv      Do not use PASV mode for FTP connections (default)
    --timeout N    Specifies how much time, in seconds, we give remote
                   servers to respond (default 20 seconds)
    --no-symlink   Do not call mk-origtargz
    --verbose      Give verbose output
    --no-verbose   Don\'t give verbose output (default)
    --check-dirname-level N
                   How much to check directory names:
                   N=0   never
                   N=1   only when program changes directory (default)
                   N=2   always
    --check-dirname-regex REGEX
                   What constitutes a matching directory name; REGEX is
                   a Perl regular expression; the string \`PACKAGE\' will
                   be replaced by the package name; see manpage for details
                   (default: 'PACKAGE(-.+)?')
    --watchfile FILE
                   Specify the watchfile rather than using debian/watch;
                   no directory traversing will be done in this case
    --upstream-version VERSION
                   Specify the current upstream version in use rather than
                   parsing debian/changelog to determine this
    --download-version VERSION
                   Specify the version which the upstream release must
                   match in order to be considered, rather than using the
                   release with the highest version
    --download-debversion VERSION
		   Specify the Debian package version to download the
		   corresponding upstream release version.  The
		   dversionmangle and uversionmangle rules are
		   considered.
    --download-current-version
                   Download the currently packaged version
    --package PACKAGE
                   Specify the package name rather than examining
                   debian/changelog; must use --upstream-version and
                   --watchfile with this option, no directory traversing
                   will be performed, no actions (even downloading) will be
                   carried out
    --no-dehs      Use traditional uscan output format (default)
    --dehs         Use DEHS style output (XML-type)
    --user-agent, --useragent
                   Override the default user agent
    --no-conf, --noconf
                   Don\'t read devscripts config files;
                   must be the first option given
    --no-exclusion no automatic exclusion of files mentioned in
                   debian/copyright field Files-Excluded
    --help         Show this message
    --version      Show version information

Options passed on to mk-origtargz:
    --symlink      Create a correctly named symlink to downloaded file (default)
    --rename       Rename instead of symlinking
    --repack       Repack downloaded archives to change compression
    --compression [ gzip | bzip2 | lzma | xz ]
                   When the upstream sources are repacked, use compression COMP
                   for the resulting tarball (default: gzip)
    --copyright-file FILE
                   Remove files matching the patterns found in FILE

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999-2006 by Julian Gilbey, all rights reserved.
Original code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

# What is the default setting of $ENV{'FTP_PASSIVE'}?
our $passive = 'default';

# Now start by reading configuration files and then command line
# The next stuff is boilerplate

my $destdir = "..";
my $download = 1;
my $download_version;
my $force_download = 0;
my $badversion = 0;
my $report = 0; # report even on up-to-date packages?
my $repack = 0; # repack .tar.bz2, .tar.lzma, .tar.xz or .zip to .tar.gz
my $default_compression = 'gzip' ;
my $repack_compression = $default_compression;
my $copyright_file = undef;
my $symlink = 'symlink';
my $verbose = 0;
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.+)?';
my $dehs = 0;
my %dehs_tags;
my $dehs_end_output = 0;
my $dehs_start_output = 0;
my $pkg_report_header = '';
my $timeout = 20;
my $user_agent_string = 'Debian uscan ###VERSION###';
my $exclusion = 1;
my $origcount = 0;
my @components = ();
my $orig;
my $repacksuffix_used = 0;
my $uscanlog;
my $common_newversion ; # undef initially (for MUT, version=same)
my $common_mangled_newversion ; # undef initially (for MUT)
my $previous_newversion ; # undef initially (for version=prev, pgpmode=prev)
my $previousfile_base ; # undef initially (for pgpmode=prev)
my ($keyring, $gpghome); # must be persistent for MUT
my $gpgv_used = 0;
my $gpg_used = 0;

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'USCAN_TIMEOUT' => 20,
		       'USCAN_DESTDIR' => '..',
		       'USCAN_DOWNLOAD' => 'yes',
		       'USCAN_PASV' => 'default',
		       'USCAN_SYMLINK' => 'symlink',
		       'USCAN_VERBOSE' => 'no',
		       'USCAN_DEHS_OUTPUT' => 'no',
		       'USCAN_USER_AGENT' => '',
		       'USCAN_REPACK' => 'no',
		       'USCAN_EXCLUSION' => 'yes',
		       'DEVSCRIPTS_CHECK_DIRNAME_LEVEL' => 1,
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.+)?',
		       );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
	$shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'USCAN_DESTDIR'} =~ /^\s*(\S+)\s*$/
	or $config_vars{'USCAN_DESTDIR'}='..';
    $config_vars{'USCAN_DOWNLOAD'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_DOWNLOAD'}='yes';
    $config_vars{'USCAN_PASV'} =~ /^(yes|no|default)$/
	or $config_vars{'USCAN_PASV'}='default';
    $config_vars{'USCAN_TIMEOUT'} =~ m/^\d+$/
	or $config_vars{'USCAN_TIMEOUT'}=20;
    $config_vars{'USCAN_SYMLINK'} =~ /^(yes|no|symlinks?|rename)$/
	or $config_vars{'USCAN_SYMLINK'}='yes';
    $config_vars{'USCAN_SYMLINK'}='symlink'
	if $config_vars{'USCAN_SYMLINK'} eq 'yes' or
	    $config_vars{'USCAN_SYMLINK'} =~ /^symlinks?$/;
    $config_vars{'USCAN_VERBOSE'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_VERBOSE'}='no';
    $config_vars{'USCAN_DEHS_OUTPUT'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_DEHS_OUTPUT'}='no';
    $config_vars{'USCAN_REPACK'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_REPACK'}='no';
    $config_vars{'USCAN_EXCLUSION'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_EXCLUSION'}='yes';
    $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} =~ /^[012]$/
	or $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'}=1;

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $destdir = $config_vars{'USCAN_DESTDIR'}
    	if defined $config_vars{'USCAN_DESTDIR'};
    $download = $config_vars{'USCAN_DOWNLOAD'} eq 'no' ? 0 : 1;
    $passive = $config_vars{'USCAN_PASV'} eq 'yes' ? 1 :
	$config_vars{'USCAN_PASV'} eq 'no' ? 0 : 'default';
    $timeout = $config_vars{'USCAN_TIMEOUT'};
    $symlink = $config_vars{'USCAN_SYMLINK'};
    $verbose = $config_vars{'USCAN_VERBOSE'} eq 'yes' ? 1 : 0;
    $dehs = $config_vars{'USCAN_DEHS_OUTPUT'} eq 'yes' ? 1 : 0;
    $check_dirname_level = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
    $check_dirname_regex = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_REGEX'};
    $user_agent_string = $config_vars{'USCAN_USER_AGENT'}
	if $config_vars{'USCAN_USER_AGENT'};
    $repack = $config_vars{'USCAN_REPACK'} eq 'yes' ? 1 : 0;
    $exclusion = $config_vars{'USCAN_EXCLUSION'} eq 'yes' ? 1 : 0;
}

# Now read the command line arguments
my $debug = 0;
my ($opt_h, $opt_v, $opt_destdir, $opt_download, $opt_force_download,
    $opt_report, $opt_passive, $opt_symlink, $opt_repack,
    $opt_repack_compression, $opt_exclusion, $opt_copyright_file);
my ($opt_verbose, $opt_level, $opt_regex, $opt_noconf);
my ($opt_package, $opt_uversion, $opt_watchfile, $opt_dehs, $opt_timeout);
my ($opt_download_version, $opt_download_debversion);
my $opt_user_agent;
my $opt_download_current_version;

GetOptions("help" => \$opt_h,
	   "version" => \$opt_v,
	   "destdir=s" => \$opt_destdir,
	   "download!" => \$opt_download,
	   "download-version=s" => \$opt_download_version,
	   "download-debversion=s" => \$opt_download_debversion,
	   "force-download" => \$opt_force_download,
	   "report" => sub { $opt_download = 0; },
	   "report-status" => sub { $opt_download = 0; $opt_report = 1; },
	   "passive|pasv!" => \$opt_passive,
	   "timeout=i" => \$opt_timeout,
	   "symlink!" => sub { $opt_symlink = $_[1] ? 'symlink' : 'no'; },
	   "rename" => sub { $opt_symlink = 'rename'; },
	   "repack" => sub { $opt_repack = 1; },
	   "compression=s" => \$opt_repack_compression,
	   "package=s" => \$opt_package,
	   "upstream-version=s" => \$opt_uversion,
	   "watchfile=s" => \$opt_watchfile,
	   "dehs!" => \$opt_dehs,
	   "verbose!" => \$opt_verbose,
	   "debug" => \$debug,
	   "check-dirname-level=s" => \$opt_level,
	   "check-dirname-regex=s" => \$opt_regex,
	   "user-agent=s" => \$opt_user_agent,
	   "useragent=s" => \$opt_user_agent,
	   "noconf" => \$opt_noconf,
	   "no-conf" => \$opt_noconf,
	   "exclusion!" => \$opt_exclusion,
	   "copyright-file=s" => \$opt_copyright_file,
	   "download-current-version" => \$opt_download_current_version,
	   )
    or die "Usage: $progname [options] [directories]\nRun $progname --help for more details\n";

if ($opt_noconf) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}
if ($opt_h) { usage(); exit 0; }
if ($opt_v) { version(); exit 0; }

# Now we can set the other variables according to the command line options

$destdir = $opt_destdir if defined $opt_destdir;
$download = $opt_download if defined $opt_download;
$force_download = $opt_force_download if defined $opt_force_download;
$report = $opt_report if defined $opt_report;
$repack = $opt_repack if defined $opt_repack;
$passive = $opt_passive if defined $opt_passive;
$timeout = $opt_timeout if defined $opt_timeout;
$timeout = 20 unless defined $timeout and $timeout > 0;
$symlink = $opt_symlink if defined $opt_symlink;
$verbose = $opt_verbose if defined $opt_verbose;
$repack_compression = check_compression($opt_repack_compression)
	if defined $opt_repack_compression;
$dehs = $opt_dehs if defined $opt_dehs;
$exclusion = $opt_exclusion if defined $opt_exclusion;
$copyright_file = $opt_copyright_file if defined $opt_copyright_file;
$user_agent_string = $opt_user_agent if defined $opt_user_agent;

if (defined $opt_level) {
    if ($opt_level =~ /^[012]$/) { $check_dirname_level = $opt_level; }
    else {
	uscan_die "$progname: unrecognised --check-dirname-level value (allowed are 0,1,2)\n";
    }
}

$check_dirname_regex = $opt_regex if defined $opt_regex;

if (defined $opt_package) {
    uscan_die "$progname: --package requires the use of --watchfile\nas well; run $progname --help for more details\n"
	unless defined $opt_watchfile;
    $download = -$download unless defined $opt_download;
}

uscan_die "$progname: Can't use --verbose if you're using --dehs!\n"
    if $verbose and $dehs;

uscan_die "$progname: Can't use --report-status if you're using --verbose!\n"
    if $verbose and $report;

uscan_die "$progname: Can't use --report-status if you're using --download!\n"
    if $download and $report;

uscan_warn "$progname: You're going to get strange (non-XML) output using --debug and --dehs together!\n"
    if $debug and $dehs;

# We'd better be verbose if we're debugging
$verbose |= $debug;

# Net::FTP understands this
if ($passive ne 'default') {
    $ENV{'FTP_PASSIVE'} = $passive;
}
elsif (exists $ENV{'FTP_PASSIVE'}) {
    $passive = $ENV{'FTP_PASSIVE'};
}
else { $passive = undef; }
# Now we can say
#   if (defined $passive) { $ENV{'FTP_PASSIVE'}=$passive; }
#   else { delete $ENV{'FTP_PASSIVE'}; }
# to restore $ENV{'FTP_PASSIVE'} to what it was at this point

# dummy subclass used to store all the redirections for later use
package LWP::UserAgent::UscanCatchRedirections;

use base 'LWP::UserAgent';

my @uscan_redirections;

sub redirect_ok {
    my $self = shift;
    my ($request) = @_;
    if ($self->SUPER::redirect_ok(@_)) {
	push @uscan_redirections, $request->uri;
	return 1;
    }
    return 0;
}

sub get_redirections {
    return \@uscan_redirections;
}

sub clear_redirections {
    undef @uscan_redirections;
    return;
}

package main;

my $user_agent = LWP::UserAgent::UscanCatchRedirections->new(env_proxy => 1);
$user_agent->timeout($timeout);
$user_agent->agent($user_agent_string);
# Strip Referer header for Sourceforge to avoid SF sending back a 200 OK with a
# <meta refresh=...> redirect
$user_agent->add_handler(
    'request_prepare' => sub {
	my ($request, $ua, $h) = @_;
	$request->remove_header('Referer');
    },
    m_hostname => 'sourceforge.net',
);

if (defined $opt_watchfile) {
    uscan_die "Can't have directory arguments if using --watchfile" if @ARGV;

    # no directory traversing then, and things are very simple
    if (defined $opt_package) {
	# no need to even look for a changelog!
	process_watchfile(undef, $opt_package, $opt_uversion, $opt_watchfile);
    } else {
	# Check for debian/changelog file
	until (-r 'debian/changelog') {
	    chdir '..' or uscan_die "$progname: can't chdir ..: $!\n";
	    if (cwd() eq '/') {
		uscan_die "$progname: cannot find readable debian/changelog anywhere!\nAre you in the source code tree?\n";
	    }
	}

	# Figure out package info we need
	my $changelog = eval { changelog_parse(); };
	if ($@) {
	    uscan_die "$progname: Problems parsing debian/changelog: $@\n";
	}

	my ($package, $debversion, $uversion);
	$package = $changelog->{Source};
	$debversion = $changelog->{Version};
	if (! defined $package || ! defined $debversion) {
	    uscan_die "$progname: Problems determining package name and/or version from\n  debian/changelog\n";
	}

	# Check the directory is properly named for safety
	my $good_dirname = 1;
	if ($check_dirname_level ==  2 or
	    ($check_dirname_level == 1 and cwd() ne $opwd)) {
	    my $re = $check_dirname_regex;
	    $re =~ s/PACKAGE/\Q$package\E/g;
	    if ($re =~ m%/%) {
		$good_dirname = (cwd() =~ m%^$re$%);
	    } else {
		$good_dirname = (basename(cwd()) =~ m%^$re$%);
	    }
	}
	if (! $good_dirname) {
	    uscan_die "$progname: not processing watchfile because this directory does not match the package name\n" .
		"   or the settings of the--check-dirname-level and --check-dirname-regex options if any.\n";
	}

	# Get current upstream version number
	if (defined $opt_uversion) {
	    $uversion = $opt_uversion;
	} else {
	    $uversion = $debversion;
	    $uversion =~ s/-[^-]+$//;  # revision
	    $uversion =~ s/^\d+://;    # epoch
	}

	process_watchfile(cwd(), $package, $uversion, $opt_watchfile);
    }

    # Are there any warnings to give if we're using dehs?
    $dehs_end_output=1;
    dehs_output if $dehs;
    exit ($found ? 0 : 1);
}

# Otherwise we're scanning for watchfiles
push @ARGV, '.' if ! @ARGV;
print "-- Scanning for watchfiles in @ARGV\n" if $verbose;

# Run find to find the directories.  We will handle filenames with spaces
# correctly, which makes this code a little messier than it would be
# otherwise.
my @dirs;
open FIND, '-|', 'find', @ARGV, qw(-follow -type d -name debian -print)
    or uscan_die "$progname: couldn't exec find: $!\n";

while (<FIND>) {
    chomp;
    push @dirs, $_;
}
close FIND;

uscan_die "$progname: No debian directories found\n" unless @dirs;

my @debdirs = ();

my $origdir = cwd;
for my $dir (@dirs) {
    unless (chdir $origdir) {
	uscan_warn "$progname warning: Couldn't chdir back to $origdir, skipping: $!\n";
	next;
    }
    $dir =~ s%/debian$%%;
    unless (chdir $dir) {
	uscan_warn "$progname warning: Couldn't chdir $dir, skipping: $!\n";
	next;
    }

    # Check for debian/watch file
    if (-r 'debian/watch' and -r 'debian/changelog') {
	# Figure out package info we need
	my $changelog = eval { changelog_parse(); };
	if ($@) {
	    uscan_warn "$progname warning: Problems parse debian/changelog in $dir, skipping\n";
	    next;
	}

	my ($package, $debversion, $uversion);
	$package = $changelog->{Source};
	$debversion = $changelog->{Version};
	if (! defined $package || ! defined $debversion) {
	    uscan_warn "$progname warning: Problems determining package name and/or version from\n  $dir/debian/changelog, skipping\n";
	    next;
	}

	# Check the directory is properly named for safety
	my $good_dirname = 1;
	if ($check_dirname_level ==  2 or
	    ($check_dirname_level == 1 and cwd() ne $opwd)) {
	    my $re = $check_dirname_regex;
	    $re =~ s/PACKAGE/\Q$package\E/g;
	    if ($re =~ m%/%) {
		$good_dirname = (cwd() =~ m%^$re$%);
	    } else {
		$good_dirname = (basename(cwd()) =~ m%^$re$%);
	    }
	}
	if ($good_dirname) {
	    print "-- Found watchfile in $dir/debian\n" if $verbose;
	} else {
	    print "-- Skip watchfile in $dir/debian since it does not match the package name\n" .
	        "   (or the settings of the --check-dirname-level and --check-dirname-regex options if any).\n"
	        if $verbose;
	    next;
	}

	# Get upstream version number
	$uversion = $debversion;
	$uversion =~ s/-[^-]+$//;  # revision
	$uversion =~ s/^\d+://;    # epoch

	push @debdirs, [$debversion, $dir, $package, $uversion];
    }
    elsif (-r 'debian/watch') {
	uscan_warn "$progname warning: Found watchfile in $dir,\n  but couldn't find/read changelog; skipping\n";
	next;
    }
    elsif (-f 'debian/watch') {
	uscan_warn "$progname warning: Found watchfile in $dir,\n  but it is not readable; skipping\n";
	next;
    }
}

uscan_warn "$progname: no watch file found\n" if (@debdirs == 0 and $report);

# Was there a --upstream-version option?
if (defined $opt_uversion) {
    if (@debdirs == 1) {
	$debdirs[0][3] = $opt_uversion;
    } else {
	uscan_warn "$progname warning: ignoring --upstream-version as more than one debian/watch file found\n";
    }
}

# Now sort the list of directories, so that we process the most recent
# directories first, as determined by the package version numbers
@debdirs = Devscripts::Versort::deb_versort(@debdirs);

# Now process the watchfiles in order.  If a directory d has subdirectories
# d/sd1/debian and d/sd2/debian, which each contain watchfiles corresponding
# to the same package, then we only process the watchfile in the package with
# the latest version number.
my %donepkgs;
for my $debdir (@debdirs) {
    shift @$debdir;  # don't need the Debian version number any longer
    my $dir = $$debdir[0];
    my $parentdir = dirname($dir);
    my $package = $$debdir[1];
    my $version = $$debdir[2];

    if (exists $donepkgs{$parentdir}{$package}) {
	uscan_warn "$progname warning: Skipping $dir/debian/watch\n  as this package has already been scanned successfully\n";
	next;
    }

    unless (chdir $origdir) {
	uscan_warn "$progname warning: Couldn't chdir back to $origdir, skipping: $!\n";
	next;
    }
    unless (chdir $dir) {
	uscan_warn "$progname warning: Couldn't chdir $dir, skipping: $!\n";
	next;
    }

    if (process_watchfile($dir, $package, $version, "debian/watch")
	== 0) {
	$donepkgs{$parentdir}{$package} = 1;
    }
    # Are there any warnings to give if we're using dehs?
    dehs_output if $dehs;
}

print "-- Scan finished\n" if $verbose;

$dehs_end_output=1;
dehs_output if $dehs;
exit ($found ? 0 : 1);


# This is the heart of the code: Process a single watch item
#
# watch_version=1: Lines have up to 5 parameters which are:
#
# $1 = Remote site
# $2 = Directory on site
# $3 = Pattern to match, with (...) around version number part
# $4 = Last version we have (or 'debian' for the current Debian version)
# $5 = Actions to take on successful retrieval
#
# watch_version=2:
#
# For ftp sites:
#   ftp://site.name/dir/path/pattern-(.+)\.tar\.gz [version [action]]
#
# For http sites:
#   http://site.name/dir/path/pattern-(.+)\.tar\.gz [version [action]]
# or
#   http://site.name/dir/path/base pattern-(.+)\.tar\.gz [version [action]]
#
# Lines can be prefixed with opts=<opts>.
#
# Then the patterns matched will be checked to find the one with the
# greatest version number (as determined by the (...) group), using the
# Debian version number comparison algorithm described below.
#
# watch_version=3 and 4: See POD.


sub process_watchline ($$$$$$)
{
    my ($line, $watch_version, $pkg_dir, $pkg, $pkg_version, $watchfile) = @_;
    # $line		watch line string
    # $watch_version	usually 4 (or 3)
    # $pkg_dir		usually .
    # $pkg		the source package name found in debian/changelog
    # $pkg_version	the last source package version found in debian/changelog
    # $watchfile	usually debian/watch

    my $origline = $line;
    my ($base, $site, $dir, $filepattern, $pattern, $lastversion, $action);
    my $basedir;
    my (@patterns, @sites, @redirections, @basedirs);
    my %options = (
	'repack' => $repack,
	'pgpmode' => 'mangle',
	'decompress' => 0,
	'versionmode' => 'newer'
	); # non-persistent variables
    my ($request, $response);
    my ($newfile, $newversion);
    my $style='new';
    my $urlbase;
    my $headers = HTTP::Headers->new;

    # Need to clear remembered redirection URLs so we don't try to build URLs
    # from previous watch files or watch lines
    $user_agent->clear_redirections;

    # Comma-separated list of features that sites being queried might
    # want to be aware of
    $headers->header('X-uscan-features' => 'enhanced-matching');
    $headers->header('Accept' => '*/*');
    %dehs_tags = ('package' => $pkg);

    # Start parsing the watch line
    if ($watch_version == 1) {
	($site, $dir, $filepattern, $lastversion, $action) = split ' ', $line, 5;

	if (! defined $lastversion or $site =~ /\(.*\)/ or $dir =~ /\(.*\)/) {
	    uscan_warn "$progname warning: there appears to be a version 2 format line in\n  the version 1 watchfile $watchfile;\n  Have you forgotten a 'version=2' line at the start, perhaps?\n  Skipping the line: $line\n";
	    return 1;
	}
	if ($site !~ m%\w+://%) {
	    $site = "ftp://$site";
	    if ($filepattern !~ /\(.*\)/) {
		# watch_version=1 and old style watchfile;
		# pattern uses ? and * shell wildcards; everything from the
		# first to last of these metachars is the pattern to match on
		$filepattern =~ s/(\?|\*)/($1/;
		$filepattern =~ s/(\?|\*)([^\?\*]*)$/$1)$2/;
		$filepattern =~ s/\./\\./g;
		$filepattern =~ s/\?/./g;
		$filepattern =~ s/\*/.*/g;
		$style='old';
		uscan_warn "$progname warning: Using very old style of filename pattern in $watchfile\n  (this might lead to incorrect results): $3\n";
	    }
	}

	# Merge site and dir
	$base = "$site/$dir/";
	$base =~ s%(?<!:)//%/%g;
	$base =~ m%^(\w+://[^/]+)%;
	$site = $1;
	$pattern = $filepattern;

	# Check $filepattern is OK
	if (not $filepattern or $filepattern !~ /\(.*\)/) {
	    uscan_warn "$progname warning: Filename pattern missing version delimiters ()\n  in $watchfile, skipping:\n  $line\n";
	    return 1;
	}
    } else {
	# version 2/3/4 watchfile
	if ($line =~ s/^opt(?:ion)?s\s*=\s*//) {
	    my $opts;
	    if ($line =~ s/^"(.*?)"(?:\s+|$)//) {
		$opts=$1;
	    } elsif ($line =~ s/^([^"\s]\S*)(?:\s+|$)//) {
		$opts=$1;
	    } else {
		uscan_warn "$progname warning: malformed opts=... in watchfile, skipping line:\n$origline\n";
		return 1;
	    }
	    # $opts	string extracted from the argument of opts=
	    print STDERR "$progname debug: opts: $opts\n" if $debug;
	    # $line	watch line string without opts=... part
	    print STDERR "$progname debug: line: $line\n" if $debug;
	    # user-agent strings has ,;: in it so special handling
	    if ($opts =~ /^\s*user-agent\s*=\s*(.+?)\s*$/ or
		$opts =~ /^\s*useragent\s*=\s*(.+?)\s*$/) {
		my $user_agent_string = $1;
		$user_agent_string = $opt_user_agent if defined $opt_user_agent;
		$user_agent->agent($user_agent_string);
		print STDERR "$progname debug: User-agent: $user_agent_string\n" if $debug;
		$opts='';
	    }
	    my @opts = split /,/, $opts;
	    foreach my $opt (@opts) {
		if ($opt =~ /^\s*pasv\s*$/ or $opt =~ /^\s*passive\s*$/) {
		    $options{'pasv'}=1;
		}
		elsif ($opt =~ /^\s*active\s*$/ or $opt =~ /^\s*nopasv\s*$/
		       or $opt =~ /^s*nopassive\s*$/) {
		    $options{'pasv'}=0;
		}
		elsif ($opt =~ /^\s*component\s*=\s*(.+?)\s*$/) {
			$options{'component'} = $1;
		}
		elsif ($opt =~ /^\s*pgpmode\s*=\s*(.+?)\s*$/) {
			$options{'pgpmode'} = $1;
		}
		elsif ($opt =~ /^\s*decompress\s*$/) {
		    $options{'decompress'}=1;
		}
		elsif ($opt =~ /^\s*repack\s*$/) {
		    # non-persistent $options{'repack'}
		    $options{'repack'} = 1;
		}
		elsif ($opt =~ /^\s*compression\s*=\s*(.+?)\s*$/) {
		    my $compression = check_compression($1);
		    # persistent $repack_compression
		    $repack_compression = $compression if defined $compression;
		    $repack_compression = check_compression($opt_repack_compression)
			if defined $opt_repack_compression;
		}
		elsif ($opt =~ /^\s*repacksuffix\s*=\s*(.+?)\s*$/) {
		    $options{'repacksuffix'} = $1;
		}
		elsif ($opt =~ /^\s*uversionmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'uversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*dversionmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'dversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*versionmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'uversionmangle'}} = split /;/, $1;
		    @{$options{'dversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*pagemangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'pagemangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*filenamemangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'filenamemangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*dirversionmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'dirversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*oversionmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'oversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*downloadurlmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'downloadurlmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^\s*pgpsigurlmangle\s*=\s*(.+?)\s*$/) {
		    @{$options{'pgpsigurlmangle'}} = split /;/, $1;
		}
		else {
		    uscan_warn "$progname warning: unrecognised option $opt\n";
		}
	    }
	}

	if ($line eq '') {
	    print STDERR "$progname debug: watch line only with opts=\"...\" and no URL\n" if $debug;
	    return 0;
	}
	print STDERR "$progname debug: URL ... part of watch line: $line\n" if $debug;

	# 4 parameter watch line
	($base, $filepattern, $lastversion, $action) = split ' ', $line, 4;

	# 3 parameter watch line (override)
	if ($base =~ s%/([^/]*\([^/]*\)[^/]*)$%/%) {
	    # Last component of $base has a pair of parentheses, so no
	    # separate filepattern field; we remove the filepattern from the
	    # end of $base and rescan the rest of the line
	    $filepattern = $1;
	    (undef, $lastversion, $action) = split ' ', $line, 3;
	}

	# Set $lastversion to the numeric last version
	# Update $options{'versionmode'} (its default "newer")
	if (! defined $lastversion or $lastversion eq 'debian') {
	    if (! defined $pkg_version) {
		uscan_warn "$progname warning: Unable to determine the current version\n  in $watchfile, skipping:\n  $line\n";
		return 1;
	    }
	    $lastversion=$pkg_version;
	} elsif ($lastversion eq 'ignore') {
	    $options{'versionmode'}='ignore';
	    $lastversion='0~0~0~0~0~0dummy';
	} elsif ($lastversion eq 'same') {
	    $options{'versionmode'}='same';
	    $lastversion='0~0~0~0~0~0dummy';
	} elsif ($lastversion =~ m/^prev/) {
	    $options{'versionmode'}='previous';
	    $lastversion='0~0~0~0~0~0dummy';
	}

	# Check $filepattern is OK
	if (not $filepattern or $filepattern !~ /\(.*\)/) {
	    uscan_warn "$progname warning: Filename pattern missing version delimiters ()\n  in $watchfile, skipping:\n  $line\n";
	    return 1;
	}

	# Check validity of options
	if ($base =~ /^ftp:/ and exists $options{'downloadurlmangle'}) {
	    uscan_warn "$progname warning: downloadurlmangle option invalid for ftp sites,\n  ignoring downloadurlmangle in $watchfile:\n  $line\n";
	}

	# Limit use of opts="repacksuffix" to the single upstream package
	if (defined $options{'repacksuffix'}) {
	    $repacksuffix_used =1;
	}
	if ($repacksuffix_used and @components) {
	    uscan_warn "$progname: repacksuffix is not compatible with the multiple upstream tarballs;  use oversionmangle\n";
	    return 1
	}

	# Allow 2 char shorthands for opts="pgpmode=..." and check
	if ($options{'pgpmode'} =~ m/^ma/) {
	    $options{'pgpmode'} = 'mangle';
	    if (defined $options{'pgpsigurlmangle'}) {
		$gpgv_used++;
	    }
	} elsif ($options{'pgpmode'} =~ m/^no/) {
	    $options{'pgpmode'} = 'none';
	} elsif ($options{'pgpmode'} =~ m/^ne/) {
	    $options{'pgpmode'} = 'next';
	} elsif ($options{'pgpmode'} =~ m/^pr/) {
	    $options{'pgpmode'} = 'previous';
	    $options{'versionmode'} = 'previous';
	    $gpgv_used++;
	} elsif ($options{'pgpmode'} =~ m/^se/) {
	    $options{'pgpmode'} = 'self';
	    $gpg_used++;
	} else {
	    uscan_warn "$progname warning: Unable to determine the signature type for $options{'pgpmode'}, use pgpmode=mangle\n";
	}

	# If PGP used, check required programs and generate files
	print STDERR "$progname debug: \$gpgv_used=$gpgv_used, \$gpg_used=$gpg_used, \$download=$download, \$force_download=$force_download\n" if $debug;
	print STDERR "$progname debug: \$options{'pgpmode'}=$options{'pgpmode'}, \$options{'pgpsigurlmangle'}=$options{'pgpsigurlmangle'}\n" if $debug and defined $options{'pgpsigurlmangle'};
	print STDERR "$progname debug: \$options{'pgpmode'}=$options{'pgpmode'}, \$options{'pgpsigurlmangle'}=undef\n" if $debug and ! defined $options{'pgpsigurlmangle'};
	if (($download or $force_download) and ($gpgv_used == 1 or $gpg_used == 1)) {
	    if ($gpgv_used == 1 and ! $havegpgv) {
		uscan_warn "$progname warning: pgpsigurlmangle option exists, please install gpgv or gpgv2.\n";
		return 1;
	    }
	    if ($gpg_used == 1 and ! $havegpg) {
		uscan_warn "$progname warning: pgpmode=self option exists, please install gnupg or gnupg2.\n";
		return 1;
	    }
	    # upstream-signing-key.pgp is deprecated
	    $keyring = first { -r $_ } qw(debian/upstream/signing-key.pgp debian/upstream/signing-key.asc debian/upstream-signing-key.pgp);
	    if (!defined $keyring) {
		uscan_warn "$progname warning: pgpsigurlmangle option exists, but the upstream keyring does not exist\n  in $watchfile, skipping:\n  $line\n";
		return 1;
	    } else {
		print STDERR "$progname debug: Found upstream signing keyring: $keyring\n" if $debug;
	    }

	    if ($keyring =~ m/\.asc$/) {
		if (!$havegpg) {
		    uscan_warn "$progname warning: $keyring is armored, please install gnupg or gnupg2.\n";
		    return 1;
		}
		# Need to convert an armored key to binary for use by gpgv
		$gpghome = tempdir(CLEANUP => 1);
		my $newkeyring = "$gpghome/trustedkeys.gpg";
		spawn(exec => [$havegpg, '--homedir', $gpghome, '--no-options', '-q', '--batch', '--no-default-keyring', '--output', $newkeyring, '--dearmor', $keyring],
		      wait_child => 1);
		$keyring = $newkeyring
	    }
	}

	# Check component for duplication and set $orig to the proper extension string
	if ($options{'pgpmode'} ne 'previous') {
	    if (defined $options{'component'}) {
		if ( grep {$_ eq $options{'component'}} @components ) {
		    uscan_warn "$progname: duplicate component name: $options{'component'}\n";
		    return 1;
		}
		push @components, $options{'component'};
		$orig = "orig-$options{'component'}";
	    } else {
		$origcount++ ;
		if ($origcount > 1) {
		    uscan_warn "$progname: too many main upstream tarballs\n";
		    return 1;
		}
		$orig = "orig";
	    }
	}

	# Handle sf.net addresses specially
	if ($base =~ m%^http://sf\.net/%) {
	    $base =~ s%^http://sf\.net/%https://qa.debian.org/watch/sf.php/%;
	    $filepattern .= '(?:\?.*)?';
	}
	# Handle pypi.python.org addresses specially
	$base =~ s%^https?://pypi\.python\.org/packages/source/./%https://pypi.debian.net/%;

    }
    # End parsing the watch line for all version=1/2/3/4
    # all options('...') variables have been set

    # Override the last version with --download-debversion
    if (defined $opt_download_debversion) {
	$lastversion = $opt_download_debversion;
	$lastversion =~ s/-[^-]+$//;  # revision
	$lastversion =~ s/^\d+://;    # epoch
	print STDERR "$progname debug: specified --download-debversion to set the last version: $lastversion\n" if $debug;
    } else {
	print STDERR "$progname debug: last orig.tar.* tarball version: $lastversion\n" if $debug;
    }

    # And mangle it if requested
    print STDERR "$progname debug: last orig.tar.* tarball version: $lastversion\n" if $debug;
    my $mangled_lastversion;
    $mangled_lastversion = $lastversion;
    foreach my $pat (@{$options{'dversionmangle'}}) {
	print STDERR "$progname debug: dversionmangle rule $pat\n" if $debug;
	if (! safe_replace(\$mangled_lastversion, $pat)) {
	    uscan_warn "$progname: In $watchfile, potentially"
	      . " unsafe or malformed dversionmangle"
	      . " pattern:\n  '$pat'"
	      . " found. Skipping watchline\n"
	      . "  $line\n";
	    return 1;
	}
    }
    print STDERR "$progname debug: Last orig.tar.* tarball version (dversionmangled): $mangled_lastversion\n" if $debug;

    # Set $download_version etc. if already known
    if($opt_download_version) {
	$download_version = $opt_download_version;
	$force_download = 1;
	$badversion = 1;
	print STDERR "$progname debug: Force to download the specified version: $download_version\n" if $debug;
    } elsif (defined $opt_download_debversion) {
	$download_version = $mangled_lastversion;
	$force_download = 1;
	$badversion = 1;
	print STDERR "$progname debug: Force to download the specified debversion (dversionmangled): $download_version\n" if $debug;
    } elsif($opt_download_current_version) {
	$download_version = $mangled_lastversion;
	$force_download = 1;
	$badversion = 1;
	print STDERR "$progname debug: Force to download the current version: $download_version\n" if $debug;
    } elsif($options{'versionmode'} eq 'same') {
	unless (defined $common_newversion) {
	    uscan_warn "$progname warning: Unable to set versionmode=prev for the line without opts=pgpmode=prev\n  in $watchfile, skipping:\n  $line\n";
	}
	$download_version = $common_newversion;
	$badversion = 1;
	print STDERR "$progname debug: Download the matching version: $download_version\n" if $debug;
    } elsif($options{'versionmode'} eq 'previous') {
	unless ($options{'pgpmode'} eq 'previous' and defined $previous_newversion) {
	    uscan_warn "$progname warning: Unable to set versionmode=prev for the line without opts=pgpmode=prev\n  in $watchfile, skipping:\n  $line\n";
	    return 1;
	}
	$download_version = $previous_newversion;
	$badversion = 1;
	print STDERR "$progname debug: Force to download the current version: $download_version\n" if $debug;
    } else {
	if (defined $download_version) {
	    uscan_die "$progname: \$download_version defined after dversionmangle ... strange\n";
	} else {
	    print STDERR "$progname debug: \$download_version undefined after dversionmangle\n" if $debug;
	}
    }

    if ($watch_version != 1) {
	if ($base =~ m%^(\w+://[^/]+)%) {
	    $site = $1;
	} else {
	    uscan_warn "$progname warning: Can't determine protocol and site in\n  $watchfile, skipping:\n  $line\n";
	    return 1;
	}

	# Find the path with the greatest version number matching the regex
	$base = recursive_regex_dir($base, \%options, $watchfile);
	if ($base eq '') { return 1; }

	# We're going to make the pattern
	# (?:(?:http://site.name)?/dir/path/)?base_pattern
	# It's fine even for ftp sites
	$basedir = $base;
	$basedir =~ s%^\w+://[^/]+/%/%;
	$pattern = "(?:(?:$site)?" . quotemeta($basedir) . ")?$filepattern";
    }

    push @patterns, $pattern;
    push @sites, $site;
    push @basedirs, $basedir;

    my $match = '';
    # Start Checking $site and look for $filepattern which is newer than $lastversion
    # What is the most recent file, based on the filenames?
    # We first have to find the candidates, then we sort them using
    # Devscripts::Versort::upstream_versort
    if ($site =~ m%^http(s)?://%) {
	# HTTP site
	if (defined($1) and !$haveSSL) {
	    uscan_die "$progname: you must have the liblwp-protocol-https-perl package installed\nto use https URLs\n";
	}
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base, $headers);
	$response = $user_agent->request($request);
	if (! $response->is_success) {
	    uscan_warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
	    return 1;
	}

	@redirections = @{$user_agent->get_redirections};

	print STDERR "$progname debug: redirections: @redirections\n" if ($debug and  @redirections);

	foreach my $_redir (@redirections) {
	    my $base_dir = $_redir;

	    $base_dir =~ s%^\w+://[^/]+/%/%;
	    if ($_redir =~ m%^(\w+://[^/]+)%) {
		my $base_site = $1;

		push @patterns, "(?:(?:$base_site)?" . quotemeta($base_dir) . ")?$filepattern";
		push @sites, $base_site;
		push @basedirs, $base_dir;

		# remove the filename, if any
		my $base_dir_orig = $base_dir;
		$base_dir =~ s%/[^/]*$%/%;
		if ($base_dir ne $base_dir_orig) {
		    push @patterns, "(?:(?:$base_site)?" . quotemeta($base_dir) . ")?$filepattern";
		    push @sites, $base_site;
		    push @basedirs, $base_dir;
		}
	    }
	}

	my $content = $response->content;
	print STDERR "$progname debug: received content:\n$content\n[End of received content]\n"
	    if $debug;

	# pagenmangle: should not abuse this slow operation
	foreach my $pat (@{$options{'pagemangle'}}) {
	    print STDERR "$progname debug: pagemangle rule $pat\n" if $debug;
	    if (! safe_replace(\$content, $pat)) {
		uscan_warn "$progname: In $watchfile, potentially"
		  . " unsafe or malformed pagemangle"
		  . " pattern:\n  '$pat'"
		  . " found. Skipping watchline\n"
		  . "  $line\n";
		return 1;
	    }
	}
	if ($content =~ m%^<[?]xml%i &&
	    $content =~ m%xmlns="http://s3.amazonaws.com/doc/2006-03-01/"% &&
	    $content !~ m%<Key><a\s+href%) {
	    # this is an S3 bucket listing.  Insert an 'a href' tag
	    # into the content for each 'Key', so that it looks like html (LP: #798293)
	    uscan_warn "*** Amazon special case code is deprecated***\nUse opts=pagemangle rule, instead\n";
	    print STDERR "$progname debug: fixing s3 listing\n" if $debug;
	    $content =~ s%<Key>([^<]*)</Key>%<Key><a href="$1">$1</a></Key>%g
	}

	# We need this horrid stuff to handle href=foo type
	# links.  OK, bad HTML, but we have to handle it nonetheless.
	# It's bug #89749.
	$content =~ s/href\s*=\s*(?=[^\"\'])([^\s>]+)/href="$1"/ig;
	# Strip comments
	$content =~ s/<!-- .*?-->//sg;
	# Is there a base URL given?
	if ($content =~ /<\s*base\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/i) {
	    # Ensure it ends with /
	    $urlbase = "$2/";
	    $urlbase =~ s%//$%/%;
	} else {
	    # May have to strip a base filename
	    ($urlbase = $base) =~ s%/[^/]*$%/%;
	}

	print STDERR "$progname debug: pagemangled content:\n$content\n[End of pagemangled content]\n"
	    if $debug;

	# search hrefs in web page to obtain a list of uversionmangled version and matching download URL
	print STDERR "$progname debug: matching pattern(s) @patterns\n" if $debug;
	my @hrefs;
	while ($content =~ m/<\s*a\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/sgi) {
	    my $href = $2;
	    my $mangled_version;
	    $href =~ s/\n//g;
	    foreach my $_pattern (@patterns) {
		if ($href =~ m&^$_pattern$&) {
		    if ($watch_version == 2) {
			# watch_version 2 only recognised one group; the code
			# below will break version 2 watchfiles with a construction
			# such as file-([\d\.]+(-\d+)?) (bug #327258)
			$mangled_version = $1;
		    } else {
			# need the map { ... } here to handle cases of (...)?
			# which may match but then return undef values
			$mangled_version =
			    join(".", map { $_ if defined($_) }
			 	$href =~ m&^$_pattern$&);
			foreach my $pat (@{$options{'uversionmangle'}}) {
			    print STDERR "$progname debug: uversionmangle rule $pat\n" if $debug;
			    if (! safe_replace(\$mangled_version, $pat)) {
				uscan_warn "$progname: In $watchfile, potentially"
			 	 . " unsafe or malformed uversionmangle"
				  . " pattern:\n  '$pat'"
				  . " found. Skipping watchline\n"
				  . "  $line\n";
				return 1;
			    }
			}
		    }
		    $match = '';
		    if (defined $download_version) {
			if ($mangled_version eq $download_version) {
			    $match = "matched with the download version";
			}
		    }
		    push @hrefs, [$mangled_version, $href, $match];
		}
	    }
	}
	if (@hrefs) {
	    @hrefs = Devscripts::Versort::upstream_versort(@hrefs);
	    if ($debug) {
		print "-- Found the following matching hrefs on the web page (newest first):\n";
		foreach my $href (@hrefs) { print "     $$href[1] ($$href[0]) $$href[2]\n"; }
	    }
	}
	if (defined $download_version) {
	    my @vhrefs = grep { $$_[2] } @hrefs;
	    if (@vhrefs) {
		($newversion, $newfile, undef) = @{$vhrefs[0]};
	    } else {
		uscan_warn "$progname warning: In $watchfile no matching hrefs for version $download_version"
		    . " in watch line\n  $line\n";
		return 1;
	    }
	} else {
	    if (@hrefs) {
	    	($newversion, $newfile, undef) = @{$hrefs[0]};
	    } else {
		uscan_warn "$progname warning: In $watchfile no matching files for watch line\n  $line\n";
		return 1;
	    }
	}
    } elsif ($site =~ m%^ftp://%) {
	# FTP site
	if (exists $options{'pasv'}) {
	    $ENV{'FTP_PASSIVE'}=$options{'pasv'};
	}
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base);
	$response = $user_agent->request($request);
	if (exists $options{'pasv'}) {
	    if (defined $passive) { $ENV{'FTP_PASSIVE'}=$passive; }
	    else { delete $ENV{'FTP_PASSIVE'}; }
	}
	if (! $response->is_success) {
	    uscan_warn "$progname warning: In watchfile $watchfile, reading FTP directory\n  $base failed: " . $response->status_line . "\n";
	    return 1;
	}

	my $content = $response->content;
	print STDERR "$progname debug: received content:\n$content\n[End of received content]\n"
	    if $debug;

	# FTP directory listings either look like:
	# info info ... info filename [ -> linkname]
	# or they're HTMLised (if they've been through an HTTP proxy)
	# so we may have to look for <a href="filename"> type patterns
	print STDERR "$progname debug: matching pattern $pattern\n" if $debug;
	my (@files);

	# We separate out HTMLised listings from standard listings, so
	# that we can target our search correctly
	if ($content =~ /<\s*a\s+[^>]*href/i) {
	    while ($content =~
		m/(?:<\s*a\s+[^>]*href\s*=\s*\")((?-i)$pattern)\"/gi) {
		my $file = $1;
		my $mangled_version = join(".", $file =~ m/^$pattern$/);
		foreach my $pat (@{$options{'uversionmangle'}}) {
		    print STDERR "$progname debug: uversionmangle rule $pat\n" if $debug;
		    if (! safe_replace(\$mangled_version, $pat)) {
			uscan_warn "$progname: In $watchfile, potentially"
			  . " unsafe or malformed uversionmangle"
			  . " pattern:\n  '$pat'"
			  . " found. Skipping watchline\n"
			  . "  $line\n";
			return 1;
		    }
		}
		$match = '';	
		if (defined $download_version) {
		    if ($mangled_version eq $download_version) {
			$match = "matched with the download version";
		    }
		}
		push @files, [$mangled_version, $file, $match];
	    }
	} else {
	    # they all look like:
	    # info info ... info filename [ -> linkname]
	    for my $ln (split(/\n/, $content)) {
		if ($ln =~ m/\s($filepattern)(\s+->\s+\S+)?$/) {
		    my $file = $1;
		    my $mangled_version = join(".", $file =~ m/^$filepattern$/);
		    foreach my $pat (@{$options{'uversionmangle'}}) {
			print STDERR "$progname debug: uversionmangle rule $pat\n" if $debug;
			if (! safe_replace(\$mangled_version, $pat)) {
			    uscan_warn "$progname: In $watchfile, potentially"
			      . " unsafe or malformed uversionmangle"
			      . " pattern:\n  '$pat'"
			      . " found. Skipping watchline\n"
			      . "  $line\n";
			    return 1;
			}
		    }
		    $match = '';	
		    if (defined $download_version) {
			if ($mangled_version eq $download_version) {
			    $match = "matched with the download version";
			}
		    }
		    push @files, [$mangled_version, $file, $match];
		}
	    }
	}
	if (@files) {
	    @files = Devscripts::Versort::upstream_versort(@files);
	    if ($verbose) {
		print "-- Found the following matching files on the web page (newest first):\n";
		foreach my $file (@files) { print "     $$file[1] ($$file[0]) $$file[2]\n"; }
	    }
	}
	if (defined $download_version) {
	    my @vfiles = grep { $$_[2] } @files;
	    if (@vfiles) {
		($newversion, $newfile, undef) = @{$vfiles[0]};
	    } else {
		uscan_warn "$progname warning: In $watchfile no matching files for version $download_version"
		    . " in watch line\n  $line\n";
		return 1;
	    }
	} else {
	    if (@files) {
	    	($newversion, $newfile, undef) = @{$files[0]};
	    } else {
		uscan_warn "$progname warning: In $watchfile no matching files for watch line\n  $line\n";
		return 1;
	    }
	}
    } else {
	# Neither HTTP nor FTP
	uscan_warn "$progname warning: Unknown protocol in $watchfile, skipping:\n  $site\n";
	return 1;
    }
    # End Checking $site and look for $filepattern which is newer than $lastversion

    # The original version of the code didn't use (...) in the watch
    # file to delimit the version number; thus if there is no (...)
    # in the pattern, we will use the old heuristics, otherwise we
    # use the new.

    if ($style eq 'old') {
        # Old-style heuristics
	if ($newversion =~ /^\D*(\d+\.(?:\d+\.)*\d+)\D*$/) {
	    $newversion = $1;
	} else {
	    uscan_warn <<"EOF";
$progname warning: In $watchfile, couldn\'t determine a
  pure numeric version number from the file name for watch line
  $line
  and file name $newfile
  Please use a new style watchfile instead!
EOF
	    return 1;
	}
    }
    # $newversion = version used for pkg-ver.tar.gz and version comparison
    print STDERR "$progname debug: newest upstream tarball version selected for download (uversionmangled): $newversion\n" if $debug;
    print STDERR "$progname debug: download filename $newfile\n" if $debug;
    unless (defined $common_newversion) {
	$common_newversion = $newversion;
    }

    my $newfile_base = basename($newfile);
    if (exists $options{'filenamemangle'}) {
        $newfile_base = $newfile;
    }
    foreach my $pat (@{$options{'filenamemangle'}}) {
	print STDERR "$progname debug: filenamemangle rule $pat\n" if $debug;
	if (! safe_replace(\$newfile_base, $pat)) {
	    uscan_warn "$progname: In $watchfile, potentially"
	      . " unsafe or malformed filenamemangle"
	      . " pattern:\n  '$pat'"
	      . " found. Skipping watchline\n"
	      . "  $line\n";
		return 1;
	}
    }
    # Remove HTTP header trash
    if ($site =~ m%^https?://%) {
        $newfile_base =~ s/\?.*$//;
	# just in case this leaves us with nothing
	if ($newfile_base eq '') {
	    $newfile_base = "$pkg-$newversion.download";
	}
    }
    print STDERR "$progname debug: new filename selected for download (filenamemangled): $newfile_base\n" if $debug;

    # So what have we got to report now?
    my $upstream_url;
    my $pgpsig_url;
    # Upstream URL?  Copying code from below - ugh.
    if ($site =~ m%^https?://%) {
	# absolute URL?
	if ($newfile =~ m%^\w+://%) {
	    $upstream_url = $newfile;
	}
	elsif ($newfile =~ m%^//%) {
	    $upstream_url = $site;
	    $upstream_url =~ s/^(https?:).*/$1/;
	    $upstream_url .= $newfile;
	}
	# absolute filename?
	elsif ($newfile =~ m%^/%) {
	    # Were there any redirections? If so try using those first
	    if ($#patterns > 0) {
		# replace $site here with the one we were redirected to
		foreach my $index (0 .. $#patterns) {
		    if ("$sites[$index]$newfile" =~ m&^$patterns[$index]$&) {
			$upstream_url = "$sites[$index]$newfile";
			last;
		    }
		}
		if (!defined($upstream_url)) {
		    if ($debug) {
			uscan_warn "$progname warning: Unable to determine upstream url from redirections,\n" .
			    "defaulting to using site specified in watchfile\n";
		    }
		    $upstream_url = "$sites[0]$newfile";
		}
	    } else {
		$upstream_url = "$sites[0]$newfile";
	    }
	}
	# relative filename, we hope
	else {
	    # Were there any redirections? If so try using those first
	    if ($#patterns > 0) {
		# replace $site here with the one we were redirected to
		foreach my $index (0 .. $#patterns) {
		    # skip unless the basedir looks like a directory
		    next unless $basedirs[$index] =~ m%/$%;
		    my $nf = "$basedirs[$index]$newfile";
		    if ("$sites[$index]$nf" =~ m&^$patterns[$index]$&) {
			$upstream_url = "$sites[$index]$nf";
			last;
		    }
		}
		if (!defined($upstream_url)) {
		    if ($debug) {
			uscan_warn "$progname warning: Unable to determine upstream url from redirections,\n" .
			    "defaulting to using site specified in watchfile\n";
		    }
		    $upstream_url = "$urlbase$newfile";
		}
	    } else {
		$upstream_url = "$urlbase$newfile";
	    }
	}

	# mangle if necessary
	$upstream_url =~ s/&amp;/&/g;
	if (exists $options{'downloadurlmangle'}) {
	    foreach my $pat (@{$options{'downloadurlmangle'}}) {
		print STDERR "$progname debug: downloadurlmangle rule $pat\n" if $debug;
		if (! safe_replace(\$upstream_url, $pat)) {
		    uscan_warn "$progname: In $watchfile, potentially"
		      . " unsafe or malformed downloadurlmangle"
		      . " pattern:\n  '$pat'"
		      . " found. Skipping watchline\n"
		      . "  $line\n";
		    return 1;
		}
	    }
	}
    }
    else {
	# FTP site
	$upstream_url = "$base$newfile";
    }
    print STDERR "$progname debug: downloadurlmangled upstream URL $upstream_url\n" if $debug;

    if ($options{'pgpmode'} eq 'mangle') {
	if (exists $options{'pgpsigurlmangle'}) {
	    $pgpsig_url = $upstream_url;
	    foreach my $pat (@{$options{'pgpsigurlmangle'}}) {
		print STDERR "$progname debug: pgpsigurlmangle rule $pat\n" if $debug;
		if (! safe_replace(\$pgpsig_url, $pat)) {
		    uscan_warn "$progname: In $watchfile, potentially"
		      . " unsafe or malformed pgpsigurlmangle"
		      . " pattern:\n  '$pat'"
		      . " found. Skipping watchline\n"
		      . "  $line\n";
		    return 1;
		}
	    }
	    print STDERR "$progname debug: pgpsigurlmangled upstream URL $pgpsig_url\n" if $debug;
	}
    }

    $dehs_tags{'debian-uversion'} = $lastversion;
    $dehs_tags{'debian-mangled-uversion'} = $mangled_lastversion;
    $dehs_tags{'upstream-version'} = $newversion;
    $dehs_tags{'upstream-url'} = $upstream_url;

    # Can't just use $mangled_lastversion eq $newversion, as then 0.01 and 0.1
    # compare different, whereas they are treated as equal by dpkg
    if (system("dpkg", "--compare-versions", "1:${mangled_lastversion}-0", "eq", "1:${newversion}-0") == 0) {
	if ($verbose or ($download == 0 and $report and ! $dehs and ($options{'versionmode'} eq 'newer'))) {
	    print $pkg_report_header;
	    $pkg_report_header = '';
	    print "Newest version on remote site is $newversion, local version is $lastversion\n" .
		($mangled_lastversion eq $lastversion ? "" : " (mangled local version number $mangled_lastversion)\n");
	    print " => Package is up to date\n";
	}
	if ($options{'versionmode'} eq 'newer') {
	    $dehs_tags{'status'} = "up to date";
	    if (! $force_download) {
		return 0;
	    } else {
		$download = 1;
	    }
	} elsif ($options{'versionmode'} eq 'same') {
	    $dehs_tags{'status'} = "same as the main tarball";
	    $download_version=$mangled_lastversion;
	} else { # ignore
	    $dehs_tags{'status'} = "unknown";
	}
    }

    # In all other cases, we'll want to report information even with --report
    if ($verbose or ($download == 0 and ! $dehs)) {
	print $pkg_report_header;
	$pkg_report_header = '';
	print "Newest version on remote site is $newversion, local version is $lastversion\n" .
	    ($mangled_lastversion eq $lastversion ? "" : " (mangled local version number $mangled_lastversion)\n");
    }

    # We use dpkg's rules to determine whether our current version
    # is newer or older than the remote version.
    if (!defined $download_version) {
	if (system("dpkg", "--compare-versions", "1:${mangled_lastversion}-0", "gt", "1:${newversion}-0") == 0) {
	    if ($verbose) {
		print " => remote site does not even have current version\n";
	    } elsif ($dehs) {
		$dehs_tags{'status'} = "Debian version newer than remote site";
	    } else {
		print "$pkg: remote site does not even have current version\n";
	    }
	    return 0;
	} else {
	    # There's a newer upstream version available, which may already
	    # be on our system or may not be
	    $found++;
	}
    } else {
	# Flag that we found a newer upstream version, so that the exit status
	# is set correctly
	$found++;
    }

    if (defined $pkg_dir) {
	if (! -d "$destdir") {
	    print "Package directory '$destdir to store downloaded file is not existing\n";
	    return 1;
	}
	if (-f "$destdir/$newfile_base") {
	    print " => $newfile_base already in package directory\n"
		if $verbose or ($download == 0 and ! $dehs);
	    return 0;
	}
	if ($options{'pgpmode'} ne 'previous') {
	    foreach my $suffix (qw(gz bz2 lzma xz)) {
		if (-f "$destdir/${pkg}_${newversion}.${orig}.tar.$suffix") {
		    print " => ${pkg}_${newversion}.${orig}.tar.$suffix already in package directory '$destdir'\n"
			if $verbose or ($download == 0 and ! $dehs);
		    return 0;
		}
	    }
	}
    }

    if ($force_download and $verbose) {
	print " => Forcing download as requested\n";
    } elsif ($verbose) {
	print " => Newer version available from\n";
	print "    $upstream_url\n";
    } elsif ($dehs) {
	$dehs_tags{'status'} = "Newer version available";
    } else {
	my $msg_header = "$pkg: ";
	$msg_header .= $force_download ? "Version" : "Newer version";
	print "$msg_header ($newversion) available on remote site:\n  $upstream_url\n  (local version is $lastversion" .
	    ($mangled_lastversion eq $lastversion ? "" : ", mangled local version number $mangled_lastversion") .
	    ")\n";
    }

    if ($download < 0) {
	my $msg = "Not downloading as --package was used.  Use --download to force downloading.";
	if ($dehs) {
	    dehs_msg($msg);
	} else {
	    print "$msg\n";
	}
	return 0;
    }
    return 0 unless $download;

    print "-- Downloading updated package $newfile_base\n" if $verbose;
    if (! -d "$destdir") {
        print "Package directory '$destdir to store downloaded file is not existing\n";
        return 1;
    }
    my $downloader = sub {
	my ($url, $fname) = @_;
	if ($url =~ m%^http(s)?://%) {
	    if (defined($1) and !$haveSSL) {
		uscan_die "$progname: you must have the liblwp-protocol-https-perl package installed\nto use https URLs\n";
	    }
	    # substitute HTML entities
	    # Is anything else than "&amp;" required?  I doubt it.
	    print STDERR "$progname debug: requesting URL $url\n" if $debug;
	    my $headers = HTTP::Headers->new;
	    $headers->header('Accept' => '*/*');
	    $headers->header('Referer' => $base);
	    $request = HTTP::Request->new('GET', $url, $headers);
	    $response = $user_agent->request($request, $fname);
	    if (! $response->is_success) {
		if (defined $pkg_dir) {
		    uscan_warn "$progname warning: In directory $pkg_dir, downloading\n  $url failed: " . $response->status_line . "\n";
		} else {
		    uscan_warn "$progname warning: Downloading\n $url failed:\n" . $response->status_line . "\n";
		}
		return 0;
	    }
	}
	else {
	    # FTP site
	    if (exists $options{'pasv'}) {
		$ENV{'FTP_PASSIVE'}=$options{'pasv'};
	    }
	    print STDERR "$progname debug: requesting URL $url\n" if $debug;
	    $request = HTTP::Request->new('GET', "$url");
	    $response = $user_agent->request($request, $fname);
	    if (exists $options{'pasv'}) {
		if (defined $passive) { $ENV{'FTP_PASSIVE'}=$passive; }
		else { delete $ENV{'FTP_PASSIVE'}; }
	    }
	    if (! $response->is_success) {
		if (defined $pkg_dir) {
		    uscan_warn "$progname warning: In directory $pkg_dir, downloading\n  $url failed: " . $response->status_line . "\n";
		} else {
		    uscan_warn "$progname warning: Downloading\n $url failed:\n" . $response->status_line . "\n";
		}
		return 0;
	    }
	}
	return 1;
    };
    # Download newer package
    if (!$downloader->($upstream_url, "$destdir/$newfile_base")) {
	return 1;
    }
    # Decompress archive if requested and applicable
    my $sigfile_base = $newfile_base;
    if ($options{'decompress'} and 
	($options{'pgpmode'} eq 'mangle' or $options{'pgpmode'} eq 'next')) {
	my $suffix = $sigfile_base;
	$suffix =~ s/.*?(\.gz|\.xz|\.bz2|\.lzma)?$/$1/;
	if ($suffix eq '.gz') {
	    if ( -x '/bin/gunzip') {
		system('/bin/gunzip', '$destdir/$sigfile_base');
		$sigfile_base =~ s/(.*?)\.gz/$1/;
	    } else {
		uscan_die("$progname: Please install gzip.\n");
	    }
	} elsif ($suffix eq '.xz') {
	    if ( -x '/usr/bin/unxz') {
		system('/usr/bin/unxz', '$destdir/$sigfile_base');
		$sigfile_base =~ s/(.*?)\.xz/$1/;
	    } else {
		uscan_die("$progname: Please install xz-utils.\n");
	    }
	} elsif ($suffix eq '.bz2') {
	    if ( -x '/bin/bunzip2') {
		system('/bin/bunzip2', '$destdir/$sigfile_base');
		$sigfile_base =~ s/(.*?)\.bz2/$1/;
	    } else {
		uscan_die("$progname: Please install bzip2.\n");
	    }
	} elsif ($suffix eq '.lzma') {
	    if ( -x '/usr/bin/unlzma') {
		system('/usr/bin/unlzma', '$destdir/$sigfile_base');
		$sigfile_base =~ s/(.*?)\.lzma/$1/;
	    } else {
		uscan_die("$progname: Please install xz-utils or lzma.\n");
	    }
	}

    }
    # Check GPG
    if ($options{'pgpmode'} eq 'mangle') {
	if (defined $pgpsig_url) {
	    print "-- Downloading OpenPGP signature for package as $sigfile_base.pgp\n" if $verbose;
	    if (!$downloader->($pgpsig_url, "$destdir/$sigfile_base.pgp")) {
		return 1;
	    }

	    print "-- Verifying OpenPGP signature $sigfile_base.pgp for $sigfile_base\n" if $verbose;
	    system($havegpgv, '--homedir', '/dev/null',
		   '--keyring', $keyring,
		   "$destdir/$sigfile_base.pgp", "$destdir/$sigfile_base") >> 8 == 0
			or uscan_die("$progname: OpenPGP signature did not verify.\n");
	} else {
	    print "-- Checking for common possible upstream OpenPGP signatures\n" if $verbose;
	    foreach my $suffix (qw(asc gpg pgp sig)) {
		my $sigrequest = HTTP::Request->new('HEAD' => "$upstream_url.$suffix");
		my $sigresponse = $user_agent->request($sigrequest);
		if ($sigresponse->is_success()) {
		    uscan_warn "$pkg: Possible OpenPGP signature found at:\n   $upstream_url.$suffix.\n  Please consider adding opts=pgpsigurlmangle=s/\$/.$suffix/\n  to debian/watch.  see uscan(1) for more details.\n";
		    last;
		}
	    }
	}
	$previousfile_base = undef;
	$previous_newversion = undef;
    } elsif ($options{'pgpmode'} eq 'next') {
	print "-- Differ checking OpenPGP signature to the next watch line\n" if $verbose;
	$previousfile_base = $sigfile_base;
	$previous_newversion = $newversion;

    } elsif ($options{'pgpmode'} eq 'previous') {
	if (defined $previousfile_base) {
	    print "-- Checking OpenPGP signatures of previously downloaded file: $previousfile_base\n" if $verbose;
	} else {
	    uscan_die "pgpmode=previous requires previous watch line to be pgpmode=next.\n";
	}
	print "-- Verifying OpenPGP signature of $previousfile_base with $newfile_base\n" if $verbose;
	system($havegpgv, '--homedir', '/dev/null',
	       '--keyring', $keyring,
	       "$destdir/$newfile_base", "$destdir/$previousfile_base") >> 8 == 0
		    or uscan_die("$progname: OpenPGP signature did not verify.\n");
	$previousfile_base = undef;
	$previous_newversion = undef;
    } elsif ($options{'pgpmode'} eq 'self') {
	$gpghome = tempdir(CLEANUP => 1);
	$newfile_base = $sigfile_base;
	$newfile_base =~ s/^(.*?)\.[^\.]+$/$1/;
	print "-- Verifying OpenPGP self signature of $sigfile_base and extract $newfile_base\n" if $verbose;
	system($havegpg, '--homedir', $gpghome,
	       '--no-options', '-q', '--batch', '--no-default-keyring',
	       '--keyring', $keyring, '--trust-model', 'always', '--decrypt', '-o',
	       "$destdir/$newfile_base", "$destdir/$sigfile_base") >> 8 == 0
		    or uscan_die("$progname: OpenPGP signature did not verify.\n");
	$previousfile_base = undef;
	$previous_newversion = undef;
    } elsif ($options{'pgpmode'} eq 'none') {
	print "-- Missing OpenPGP signatures.\n" if $verbose;
	$previousfile_base = undef;
	$previous_newversion = undef;
    } else {
	uscan_die "unknown pgpmode.\n";
    }

    my $mangled_newversion = $newversion;
    foreach my $pat (@{$options{'oversionmangle'}}) {
	print STDERR "$progname debug: Oversionmangle rule: $pat\n" if $debug;
	if (! safe_replace(\$mangled_newversion, $pat)) {
	    uscan_warn "$progname: In $watchfile, potentially"
	      . " unsafe or malformed oversionmangle"
	      . " pattern:\n  '$pat'"
	      . " found. Skipping watchline\n"
	      . "  $line\n";
		return 1;
	}
    }

    if (! defined $common_mangled_newversion) {
    	# $mangled_newversion = version used for the new orig.tar.gz (a.k.a oversion)
    	print STDERR "$progname debug: new orig.tar.gz tarball version (oversionmangled): $mangled_newversion\n" if $debug;
	# MUT package always use the same $common_mangled_newversion
	# MUT disables repacksuffix so it is safe to have this before mk-origtargz
	$common_mangled_newversion = $mangled_newversion;
    }

    # Call mk-origtargz (renames, repacks, etc.)
    my $mk_origtargz_out;
    my $path = "$destdir/$newfile_base";
    my $target = $newfile_base;
    unless ($symlink eq "no" or $options{'pgpmode'} eq 'previous') {
	my @cmd = ("mk-origtargz");
	push @cmd, "--package", $pkg;
	push @cmd, "--version", $common_mangled_newversion;
	push @cmd, '--repack-suffix', $options{repacksuffix} if defined $options{repacksuffix};
	push @cmd, "--rename" if $symlink eq "rename";
	push @cmd, "--copy"   if $symlink eq "copy";
	push @cmd, "--repack" if $options{'repack'};
	push @cmd, "--component", $options{'component'} if defined $options{'component'};
	push @cmd, "--compression", $repack_compression;
	push @cmd, "--directory", $destdir;
	push @cmd, "--copyright-file", "debian/copyright"
	    if ($exclusion && -e "debian/copyright");
	push @cmd, "--copyright-file", $copyright_file
	    if ($exclusion && defined $copyright_file);
	push @cmd, $path;

	my $actioncmd = join(" ", @cmd);
	print "-- Executing internal command\n     $actioncmd\n" if $verbose;
	spawn(exec => \@cmd,
	      to_string => \$mk_origtargz_out,
	      wait_child => 1);
	chomp($mk_origtargz_out);
	$path = $1 if $mk_origtargz_out =~ /Successfully .* (?:to|as) ([^,]+)(?:,.*)?\.$/;
	$path = $1 if $mk_origtargz_out =~ /Leaving (.*) where it is/;
	$target = basename($path);
	$common_mangled_newversion = $1 if $target =~ m/[^_]+_(.+)\.orig\.tar\.(?:gz|bz2|lzma|xz)$/;
	print STDERR "$progname debug: orig.tar.* tarball version (after mk-origtargz): $common_mangled_newversion\n" if $debug;
    }
    if (! defined $uscanlog) {
	$uscanlog = "../${pkg}_${common_mangled_newversion}.uscan.log";
	open(USCANLOG, "> $uscanlog") or uscan_die "$progname: could not open $uscanlog for write: $!\n";
	print USCANLOG "# package downloaded by uscan\n";
    } else {
	open(USCANLOG, ">> $uscanlog") or uscan_die "$progname: could not open $uscanlog for append: $!\n";
    }
    print USCANLOG "${newfile_base}\t${target}\n";
    close USCANLOG or uscan_die "$progname: could not close $uscanlog: $!\n";

    if ($dehs) {
	my $msg = "Successfully downloaded updated package $newfile_base\n";
	if (defined $mk_origtargz_out) {
	    $msg .= "$mk_origtargz_out\n";
	}
	$dehs_tags{target} = $target;
	$dehs_tags{'target-path'} = $path;
	dehs_msg($msg);
    }
    else {
	my $prefix = $verbose ? "-- " : "";
	print $prefix ."Successfully downloaded updated package $newfile_base\n";
	if (defined $mk_origtargz_out) {
	    print $prefix ."$mk_origtargz_out\n";
	}
    }

    # Do whatever the user wishes to do
    if ($action) {
	my @cmd = shellwords($action);

	# script invocation changed in $watch_version=4
	if ($watch_version > 3) {
	    if ($cmd[0] eq "uupdate") {
		push @cmd, "-f";
		if ($verbose) {
		    push @cmd, "--verbose";
		}
		if ($badversion) {
		    push @cmd, "-b";
	        }
	    }
	    push @cmd, "--upstream-version", $common_mangled_newversion;
	} elsif ($watch_version > 1) {
	    # Any symlink requests are already handled by uscan
	    if ($cmd[0] eq "uupdate") {
		push @cmd, "--no-symlink";
		if ($verbose) {
		    push @cmd, "--verbose";
		}
		if ($badversion) {
		    push @cmd, "-b";
	        }
	    }
	    push @cmd, "--upstream-version", $common_mangled_newversion, $path;
	} else {
	    push @cmd, $path, $common_mangled_newversion;
	}
	my $actioncmd = join(" ", @cmd);
	print "-- Executing user specified script\n     $actioncmd\n" if $verbose;
	if ($dehs) {
	    my $msg = "Executing user specified script: $actioncmd; output:\n";
	    $msg .= `$actioncmd 2>&1`;
	    dehs_msg($msg);
	} else {
	    system(@cmd);
	}
    }

    return 0;
}


sub recursive_regex_dir ($$$) {
    # If return '', parent code to cause return 1
    my ($base, $optref, $watchfile)=@_;

    $base =~ m%^(\w+://[^/]+)/(.*)$%;
    my $site = $1;
    my @dirs = ();
    if (defined $2) {
	@dirs = split /(\/)/, $2;
    }
    my $dir = '/';

    foreach my $dirpattern (@dirs) {
	if ($dirpattern =~ /\(.*\)/) {
	    print STDERR "$progname debug: dir=>$dir  dirpattern=>$dirpattern\n"
		if $debug;
	    my $newest_dir =
		newest_dir($site, $dir, $dirpattern, $optref, $watchfile);
	    print STDERR "$progname debug: newest_dir => '$newest_dir'\n"
		if $debug;
	    if ($newest_dir ne '') {
		$dir .= "$newest_dir";
	    }
	    else {
		return '';
	    }
	} else {
	    $dir .= "$dirpattern";
	}
    }
    return $site . $dir;
}


# very similar to code above
sub newest_dir ($$$$$) {
    # return string $newdir as success
    # return string '' if error, to cause grand parent code to return 1
    my ($site, $dir, $pattern, $optref, $watchfile) = @_;
    my $base = $site.$dir;
    my ($request, $response);
    my $newdir;

    print STDERR "$progname debug: download version requested: $download_version\n" if $debug and defined $download_version; 
    if ($site =~ m%^http(s)?://%) {
	if (defined($1) and !$haveSSL) {
	    uscan_die "$progname: you must have the liblwp-protocol-https-perl package installed\nto use https URLs\n";
	}
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base);
	$response = $user_agent->request($request);
	if (! $response->is_success) {
	    uscan_warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
	    return '';
	}

	my $content = $response->content;
	print STDERR "$progname debug: received content:\n$content\n[End of received content\]\n"
	    if $debug;
	# We need this horrid stuff to handle href=foo type
	# links.  OK, bad HTML, but we have to handle it nonetheless.
	# It's bug #89749.
	$content =~ s/href\s*=\s*(?=[^\"\'])([^\s>]+)/href="$1"/ig;
	# Strip comments
	$content =~ s/<!-- .*?-->//sg;

	my $dirpattern = "(?:(?:$site)?" . quotemeta($dir) . ")?$pattern";

	print STDERR "$progname debug: matching pattern $dirpattern\n"
	    if $debug;
	my @hrefs;
	my $match ='';
	while ($content =~ m/<\s*a\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/gi) {
	    my $href = $2;
	    if ($href =~ m&^$dirpattern/?$&) {
		my $mangled_version = join(".", map { $_ // '' } $href =~ m&^$dirpattern/?$&);
		foreach my $pat (@{$$optref{'dirversionmangle'}}) {
		    print STDERR "$progname debug: Dirversionnmangle rule: $pat\n" if $debug;
		    if (! safe_replace(\$mangled_version, $pat)) {
			uscan_warn "$progname: In $watchfile, potentially"
			. " unsafe or malformed dirversionmangle"
			. " pattern:\n  '$pat'"
			. " found.\n";
			return 1;
		    }
		}
		$match = '';
		if (defined $download_version) {
		    if ($mangled_version eq $download_version) {
			$match = "matched with the download version";
		    }
		}
		push @hrefs, [$mangled_version, $href, $match];
	    }
	}
	my @vhrefs = grep { $$_[2] } @hrefs;
	if (@vhrefs) {
	    $newdir = $vhrefs[0][1];
	}
	if (@hrefs) {
	    @hrefs = Devscripts::Versort::upstream_versort(@hrefs);
	    if ($debug) {
		print "-- Found the following matching hrefs (newest first):\n";
		foreach my $href (@hrefs) { print "     $$href[1] ($$href[0]) $$href[2]\n"; }
	    }
	    $newdir //= $hrefs[0][1];
	} else {
	    uscan_warn "$progname warning: In $watchfile,\n  no matching hrefs for pattern\n  $site$dir$pattern";
	    return '';
	}
	# just give the final directory component
	$newdir =~ s%/$%%;
	$newdir =~ s%^.*/%%;
    }
    elsif ($site =~ m%^ftp://%) {
	# FTP site
	if (exists $$optref{'pasv'}) {
	    $ENV{'FTP_PASSIVE'}=$$optref{'pasv'};
	}
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base);
	$response = $user_agent->request($request);
	if (exists $$optref{'pasv'}) {
	    if (defined $passive) { $ENV{'FTP_PASSIVE'}=$passive; }
	    else { delete $ENV{'FTP_PASSIVE'}; }
	}
	if (! $response->is_success) {
	    uscan_warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
	    return '';
	}

	my $content = $response->content;
	print STDERR "$progname debug: received content:\n$content\n[End of received content]\n"
	    if $debug;

	# FTP directory listings either look like:
	# info info ... info filename [ -> linkname]
	# or they're HTMLised (if they've been through an HTTP proxy)
	# so we may have to look for <a href="filename"> type patterns
	print STDERR "$progname debug: matching pattern $pattern\n" if $debug;
	my (@dirs);
	my $match ='';

	# We separate out HTMLised listings from standard listings, so
	# that we can target our search correctly
	if ($content =~ /<\s*a\s+[^>]*href/i) {
	    while ($content =~
		m/(?:<\s*a\s+[^>]*href\s*=\s*\")((?-i)$pattern)\"/gi) {
		my $dir = $1;
		my $mangled_version = join(".", $dir =~ m/^$pattern$/);
		foreach my $pat (@{$$optref{'dirversionmangle'}}) {
		    print STDERR "$progname debug: Dirversionnmangle rule: $pat\n" if $debug;
		    if (! safe_replace(\$mangled_version, $pat)) {
			uscan_warn "$progname: In $watchfile, potentially"
			. " unsafe or malformed dirversionmangle"
			. " pattern:\n  '$pat'"
			. " found.\n";
			return 1;
		    }
		}
		$match = '';
		if (defined $download_version) {
		    if ($mangled_version eq $download_version) {
			$match = "matched with the download version";
		    }
		}
		push @dirs, [$mangled_version, $dir, $match];
	    }
	} else {
	    # they all look like:
	    # info info ... info filename [ -> linkname]
	    foreach my $ln (split(/\n/, $content)) {
		if ($ln =~ m/($pattern)(\s+->\s+\S+)?$/) {
		    my $dir = $1;
		    my $mangled_version = join(".", $dir =~ m/^$pattern$/);
		    foreach my $pat (@{$$optref{'dirversionmangle'}}) {
			print STDERR "$progname debug: Dirversionnmangle rule: $pat\n" if $debug;
			if (! safe_replace(\$mangled_version, $pat)) {
			    uscan_warn "$progname: In $watchfile, potentially"
			    . " unsafe or malformed dirversionmangle"
			    . " pattern:\n  '$pat'"
			    . " found.\n";
			    return 1;
			}
		    }
		    $match = '';
		    if (defined $download_version) {
			if ($mangled_version eq $download_version) {
			    $match = "matched with the download version";
			}
		    }
		    push @dirs, [$mangled_version, $dir, $match];
		}
	    }
	}
	my @vdirs = grep { $$_[2] } @dirs;
	if (@vdirs) {
	    $newdir = $vdirs[0][1];
	}
	if (@dirs) {
	    @dirs = Devscripts::Versort::upstream_versort(@dirs);
	    if ($debug) {
		print STDERR "-- Found the following matching FTP dirs (newest first):\n";
		foreach my $dir (@dirs) { print STDERR "     $$dir[1] ($$dir[0]) $$dir[2]\n"; }
	    }
	    $newdir //= $dirs[0][1];
	} else {
	    uscan_warn "$progname warning: In $watchfile no matching dirs for pattern\n  $base$pattern\n";
	    $newdir = '';
	}
    }
    else {
	# Neither HTTP nor FTP site
        uscan_warn "$progname: neither HTTP nor FTP site, impossible case for newdir().\n";
	$newdir = '';
    }
    return $newdir;
}


# parameters are dir, package, upstream version, good dirname
sub process_watchfile ($$$$)
{
    my ($dir, $package, $version, $watchfile) = @_;
    my $watch_version=0;
    my $status=0;
    %dehs_tags = ();

    unless (open WATCH, $watchfile) {
	uscan_warn "$progname warning: could not open $watchfile: $!\n";
	return 1;
    }

    while (<WATCH>) {
	next if /^\s*\#/;
	next if /^\s*$/;
	s/^\s*//;

    CHOMP:
	chomp;
	if (s/(?<!\\)\\$//) {
	    if (eof(WATCH)) {
		uscan_warn "$progname warning: $watchfile ended with \\; skipping last line\n";
		$status=1;
		last;
	    }
	    $_ .= <WATCH>;
	    goto CHOMP;
	}

	if (! $watch_version) {
	    if (/^version\s*=\s*(\d+)(\s|$)/) {
		$watch_version=$1;
		if ($watch_version < 2 or
		    $watch_version > $CURRENT_WATCHFILE_VERSION) {
		    uscan_warn "$progname ERROR: $watchfile version number is unrecognised; skipping watchfile\n";
		    last;
		}
		next;
	    } else {
		uscan_warn "$progname warning: $watchfile is an obsolete version 1 watchfile;\n  please upgrade to a higher version\n  (see uscan(1) for details).\n";
		$watch_version=1;
	    }
	}

	# Are there any warnings from this part to give if we're using dehs?
	dehs_output if $dehs;

	# Handle shell \\ -> \
	s/\\\\/\\/g if $watch_version==1;
	if ($verbose) {
	    print "-- In $watchfile, processing watchfile line:\n   $_\n";
	} elsif ($download == 0 and ! $dehs) {
	    $pkg_report_header = "Processing watchfile line for package $package...\n";
	}

	$status +=
	    process_watchline($_, $watch_version, $dir, $package, $version,
			      $watchfile);
	dehs_output if $dehs;
    }

    close WATCH or
	$status=1, uscan_warn "$progname warning: problems reading $watchfile: $!\n";

    return $status;
}

# Check legal values for compression
sub check_compression ($)
{
    my $compression = $_[0];
    my $canonical_compression;
    # be liberal in what you accept...
    my %opt2comp = (
	gz => 'gzip',
	gzip => 'gzip',
	bz2 => 'bzip2',
	bzip2 => 'bzip2',
	lzma => 'lzma',
	xz => 'xz',
    );

    # Normalize compression methods to the names used by Dpkg::Compression
    if (exists $opt2comp{$compression}) {
	$canonical_compression = $opt2comp{$compression};
    } else {
        uscan_die "$progname: invalid compression $compression given.\n";
    }
    return $canonical_compression;
}
# Collect up messages for dehs output into a tag
sub dehs_msg ($)
{
    my $msg = $_[0];
    $msg =~ s/\s*$//;
    push @{$dehs_tags{'messages'}}, $msg;
}

sub uscan_warn (@)
{
    if ($dehs) {
	my $warning = $_[0];
	$warning =~ s/\s*$//;
	push @{$dehs_tags{'warnings'}}, $warning;
    }
    else {
	warn @_;
    }
}

sub uscan_die (@)
{
    if ($dehs) {
	my $msg = $_[0];
	$msg =~ s/\s*$//;
	%dehs_tags = ('errors' => "$msg");
	$dehs_end_output=1;
	dehs_output;
	exit 1;
    }
    else {
	die @_;
    }
}

sub dehs_output ()
{
    return unless $dehs;

    if (! $dehs_start_output) {
	print "<dehs>\n";
	$dehs_start_output=1;
    }

    for my $tag (qw(package debian-uversion debian-mangled-uversion
		    upstream-version upstream-url
		    status target target-path messages warnings errors)) {
	if (exists $dehs_tags{$tag}) {
	    if (ref $dehs_tags{$tag} eq "ARRAY") {
		foreach my $entry (@{$dehs_tags{$tag}}) {
		    $entry =~ s/</&lt;/g;
		    $entry =~ s/>/&gt;/g;
		    $entry =~ s/&/&amp;/g;
		    print "<$tag>$entry</$tag>\n";
		}
	    } else {
		$dehs_tags{$tag} =~ s/</&lt;/g;
		$dehs_tags{$tag} =~ s/>/&gt;/g;
		$dehs_tags{$tag} =~ s/&/&amp;/g;
		print "<$tag>$dehs_tags{$tag}</$tag>\n";
	    }
	}
    }
    if ($dehs_end_output) {
	print "</dehs>\n";
    }

    # Don't repeat output
    %dehs_tags = ();
}

sub quoted_regex_parse($) {
    my $pattern = shift;
    my %closers = ('{', '}', '[', ']', '(', ')', '<', '>');

    $pattern =~ /^(s|tr|y)(.)(.*)$/;
    my ($sep, $rest) = ($2, $3 || '');
    my $closer = $closers{$sep};

    my $parsed_ok = 1;
    my $regexp = '';
    my $replacement = '';
    my $flags = '';
    my $open = 1;
    my $last_was_escape = 0;
    my $in_replacement = 0;

    for my $char (split //, $rest) {
	if ($char eq $sep and ! $last_was_escape) {
	    $open++;
	    if ($open == 1) {
		if ($in_replacement) {
		    # Separator after end of replacement
		    $parsed_ok = 0;
		    last;
		} else {
		    $in_replacement = 1;
		}
	    } else {
		if ($open > 1) {
		    if ($in_replacement) {
			$replacement .= $char;
		    } else {
			$regexp .= $char;
		    }
		}
	    }
	} elsif ($char eq $closer and ! $last_was_escape) {
	    $open--;
	    if ($open) {
		if ($in_replacement) {
		    $replacement .= $char;
		} else {
		    $regexp .= $char;
		}
	    } elsif ($open < 0) {
		$parsed_ok = 0;
		last;
	    }
	} else {
	    if ($in_replacement) {
		if ($open) {
		    $replacement .= $char;
		} else {
		    $flags .= $char;
		}
	    } else {
		$regexp .= $char;
	    }
	}
	# Don't treat \\ as an escape
	$last_was_escape = ($char eq '\\' and ! $last_was_escape);
    }

    $parsed_ok = 0 unless $in_replacement and $open == 0;

    return ($parsed_ok, $regexp, $replacement, $flags);
}

sub safe_replace($$) {
    my ($in, $pat) = @_;
    $pat =~ s/^\s*(.*?)\s*$/$1/;

    $pat =~ /^(s|tr|y)(.)/;
    my ($op, $sep) = ($1, $2 || '');
    my $esc = "\Q$sep\E";
    my ($parsed_ok, $regexp, $replacement, $flags);

    if ($sep eq '{' or $sep eq '(' or $sep eq '[' or $sep eq '<') {
	($parsed_ok, $regexp, $replacement, $flags) = quoted_regex_parse($pat);

	return 0 unless $parsed_ok;
    } elsif ($pat !~ /^(?:s|tr|y)$esc((?:\\.|[^\\$esc])*)$esc((?:\\.|[^\\$esc])*)$esc([a-z]*)$/) {
	return 0;
    } else {
	($regexp, $replacement, $flags) = ($1, $2, $3);
    }

    my $safeflags = $flags;
    if ($op eq 'tr' or $op eq 'y') {
	$safeflags =~ tr/cds//cd;
	return 0 if $safeflags ne $flags;

	$regexp =~ s/\\(.)/$1/g;
	$replacement =~ s/\\(.)/$1/g;

	$regexp =~ s/([^-])/'\\x'  . unpack 'H*', $1/ge;
	$replacement =~ s/([^-])/'\\x'  . unpack 'H*', $1/ge;

	eval "\$\$in =~ tr<$regexp><$replacement>$flags;";

	if ($@) {
	    return 0;
	} else {
	    return 1;
	}
    } else {
	$safeflags =~ tr/gix//cd;
	return 0 if $safeflags ne $flags;

	my $global = ($flags =~ s/g//);
	$flags = "(?$flags)" if length $flags;

	my $slashg;
	if ($regexp =~ /(?<!\\)(\\\\)*\\G/) {
	    $slashg = 1;
	    # if it's not initial, it is too dangerous
	    return 0 if $regexp =~ /^.*[^\\](\\\\)*\\G/;
	}

	# Behave like Perl and treat e.g. "\." in replacement as "."
	# We allow the case escape characters to remain and
	# process them later
	$replacement =~ s/(^|[^\\])\\([^luLUE])/$1$2/g;

	# Unescape escaped separator characters
	$replacement =~ s/\\\Q$sep\E/$sep/g;
	# If bracketing quotes were used, also unescape the
	# closing version
	$replacement =~ s/\\\Q}\E/}/g if $sep eq '{';
	$replacement =~ s/\\\Q]\E/]/g if $sep eq '[';
	$replacement =~ s/\\\Q)\E/)/g if $sep eq '(';
	$replacement =~ s/\\\Q>\E/>/g if $sep eq '<';

	# The replacement below will modify $replacement so keep
	# a copy. We'll need to restore it to the current value if
	# the global flag was set on the input pattern.
	my $orig_replacement = $replacement;

	my ($first, $last, $pos, $zerowidth, $matched, @captures) = (0, -1, 0);
	while (1) {
	    eval {
		# handle errors due to unsafe constructs in $regexp
		no re 'eval';

		# restore position
		pos($$in) = $pos if $pos;

		if ($zerowidth) {
		    # previous match was a zero-width match, simulate it to set
		    # the internal flag that avoids the infinite loop
		    $$in =~ /()/g;
		}
		# Need to use /g to make it use and save pos()
		$matched = ($$in =~ /$flags$regexp/g);

		if ($matched) {
		    # save position and size of the match
		    my $oldpos = $pos;
		    $pos = pos($$in);
		    ($first, $last) = ($-[0], $+[0]);

		    if ($slashg) {
			# \G in the match, weird things can happen
			$zerowidth = ($pos == $oldpos);
			# For example, matching without a match
			$matched = 0 if (not defined $first
			    or not defined $last);
		    } else {
			$zerowidth = ($last - $first == 0);
		    }
		    for my $i (0..$#-) {
			$captures[$i] = substr $$in, $-[$i], $+[$i] - $-[$i];
		    }
		}
	    };
	    return 0 if $@;

	    # No match; leave the original string  untouched but return
	    # success as there was nothing wrong with the pattern
	    return 1 unless $matched;

	    # Replace $X
	    $replacement =~ s/[\$\\](\d)/defined $captures[$1] ? $captures[$1] : ''/ge;
	    $replacement =~ s/\$\{(\d)\}/defined $captures[$1] ? $captures[$1] : ''/ge;
	    $replacement =~ s/\$&/$captures[0]/g;

	    # Make \l etc escapes work
	    $replacement =~ s/\\l(.)/lc $1/e;
	    $replacement =~ s/\\L(.*?)(\\E|\z)/lc $1/e;
	    $replacement =~ s/\\u(.)/uc $1/e;
	    $replacement =~ s/\\U(.*?)(\\E|\z)/uc $1/e;

	    # Actually do the replacement
	    substr $$in, $first, $last - $first, $replacement;
	    # Update position
	    $pos += length($replacement) - ($last - $first);

	    if ($global) {
		$replacement = $orig_replacement;
	    } else {
		last;
	    }
	}

	return 1;
    }
}
