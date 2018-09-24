#!/usr/bin/perl
# -*- tab-width: 8; indent-tabs-mode: t; cperl-indent-level: 4 -*-
# vim:set ai sts=4 ts=8 tw=80:

# uscan: This program looks for watch files and checks upstream ftp sites
# for later versions of the software.
#
# Originally written by Christoph Lameter <clameter@debian.org> (I believe)
# Modified by Julian Gilbey <jdg@debian.org>
# HTTP support added by Piotr Roszatycki <dexter@debian.org>
# Rewritten in Perl, Copyright 2002-2006, Julian Gilbey
# Rewritten in Object Oriented Perl, copyright 2018, Xavier Guimard
# <yadd@debian.org>
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

#######################################################################
# {{{ code 0: POD for manpage
#######################################################################

=pod

=head1 NAME

uscan - scan/watch upstream sources for new releases of software

=head1 SYNOPSIS

B<uscan> [I<options>] [I<path>]

=head1 DESCRIPTION

For basic usage, B<uscan> is executed without any arguments from the root
of the Debianized source tree where you see the F<debian/> directory.  Then
typically the following happens:

=over

=item * B<uscan> reads the first entry in F<debian/changelog> to determine the
source package name I<< <spkg> >> and the last upstream version.

=item * B<uscan> process the watch lines F<debian/watch> from the top to the
bottom in a single pass.

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

=item * For a multiple upstream tarball (MUT) package, the secondary upstream
tarball will instead be named I<< ../<spkg>_<oversion>.orig-<component>.tar.gz >>.

=back

=item * Repeat until all lines in F<debian/watch> are processed.

=back

=item * B<uscan> invokes B<uupdate> to create the Debianized source tree: I<<
../<spkg>-<oversion>/* >>

=back

Please note the following.

=over

=item * For simplicity, the compression method used in examples is B<gzip> with
B<.gz> suffix.  Other methods such as B<xz>, B<bzip2>, and B<lzma> with
corresponding B<xz>, B<bz2>, and B<lzma> suffixes may also be used.

=item * The new B<version=4> enables handling of multiple upstream tarball
(MUT) packages but this is a rare case for Debian packaging.  For a single
upstream tarball package, there is only one watch line and no I<<
../<spkg>_<oversion>.orig-<component>.tar.gz >> .

=item * B<uscan> with the B<--verbose> option produces a human readable report
of B<uscan>'s execution.

=item * B<uscan> with the B<--debug> option produces a human readable report of
B<uscan>'s execution including internal variable states.

=item * B<uscan> with the B<--dehs> option produces an upstream package status
report in XML format for other programs such as the Debian External Health
System.

=item * The primary objective of B<uscan> is to help identify if the latest
version upstream tarball is used or not; and to download the latest upstream
tarball.  The ordering of versions is decided by B<dpkg --compare-versions>.

=item * B<uscan> with the B<--safe> option limits the functionality of B<uscan>
to its primary objective.  Both the repacking of downloaded files and
updating of the source tree are skipped to avoid running unsafe scripts.
This also changes the default to B<--no-download> and B<--skip-signature>.

=back

=head1 FORMAT OF THE WATCH FILE

The current version 4 format of F<debian/watch> can be summarized as follows:

=over

=item * Leading spaces and tabs are dropped.

=item * Empty lines are dropped.

=item * A line started by B<#> (hash) is a comment line and dropped.

=item * A single B<\> (back slash) at the end of a line is dropped and the
next line is concatenated after removing leading spaces and tabs. The
concatenated line is parsed as a single line. (The existence or non-existence
of the space before the tailing single B<\> is significant.)

=item * The first non-comment line is:

=over

=item B<version=4>

=back

This is a required line and the recommended version number.

If you use "B<version=3>" instead here, some features may not work as
documented here.  See L<HISTORY AND UPGRADING>.

=item * The following non-comment lines (watch lines) specify the rules for the
selection of the candidate upstream tarball URLs and are in one of the
following three formats:

=over

=item * B<opts="> I<...> B<"> B<http://>I<URL> I<matching-pattern> [I<version> [I<script>]]

=item * B<http://>I<URL> I<matching-pattern> [I<version> [I<script>]]

=item * B<opts="> I<...> B<">

=back

Here,

=over

=item * B<opts="> I<...> B<"> specifies the behavior of B<uscan>.  See L<WATCH
FILE OPTIONS>.

=item * B<http://>I<URL> specifies the web page where upstream publishes
the link to the latest source archive.

=over

=item * B<https://>I<URL> may also be used, as may

=item * B<ftp://>I<URL>

=item * Some parts of I<URL> may be in the regex match pattern surrounded
between B<(> and B<)> such as B</foo/bar-([\.\d]+)/>.  (If multiple
directories match, the highest version is picked.) Otherwise, the I<URL>
is taken as verbatim.

=back

=item * I<matching-pattern> specifies the full string matching pattern for
hrefs in the web page.  See L<WATCH FILE EXAMPLES>.

=over

=item * All matching parts in B<(> and B<)> are concatenated with B<.> (period)
to form the upstream version.

=item * If the hrefs do not contain directories, you can combine this with the
previous entry. I.e., B<http://>I<URL>B</>I<matching-pattern> .

=back

=item * I<version> restricts the upstream tarball which may be downloaded.
The newest available version is chosen in each case.

=over

=item * B<debian> requires the downloading upstream tarball to be newer than the
version obtained from F<debian/changelog>.

=item * I<version-number> such as B<12.5> requires the upstream
tarball to be newer than the I<version-number>.

=item * B<same> requires the downloaded version of the secondary tarballs to be
exactly the same as the one for the first upstream tarball downloaded. (Useful
only for MUT)

=item * B<previous> restricts the version of the signature
file. (Used with pgpmode=previous)

=item * B<ignore> does not restrict the version of the secondary
tarballs. (Maybe useful for MUT)

=back

=item * I<script> is executed at the end of B<uscan> execution with appropriate
arguments provided by B<uscan>.

=over

=item * The typical Debian package is a non-native package made from one
upstream tarball.  Only a single line of the watch line in one of the first two
formats is usually used with its I<version> set to B<debian> and I<script>
set to B<uupdate>.

=item * A native package should not specify I<script>.

=item * A multiple upstream tarball (MUT) package should specify B<uupdate>
as I<script> in the last watch line and should skip specifying I<script> in the
rest of the watch lines.

=back

=item * The last format of the watch line is useful to set the persistent
parameters: B<user-agent>, B<compression>.  If this format is used, this must
be followed by the I<URL> defining watch line(s).

=item * [ and ] in the above format are there to mark the optional parts and
should not be typed.

=back

=back

There are a few special strings which are substituted by B<uscan> to make it easy
to write the watch file.

=over

=item B<@PACKAGE@>

This is substituted with the source package name found in the first line of the
F<debian/changelog> file.

=item B<@ANY_VERSION@>

This is substituted by the legal upstream version regex (capturing).

  [-_]?(\d[\-+\.:\~\da-zA-Z]*)

=item B<@ARCHIVE_EXT@>

This is substituted by the typical archive file extension regex (non-capturing).

  (?i)\.(?:tar\.xz|tar\.bz2|tar\.gz|zip|tgz|tbz|txz)

=item B<@SIGNATURE_EXT@>

This is substituted by the typical signature file extension regex (non-capturing).

  (?i)\.(?:tar\.xz|tar\.bz2|tar\.gz|zip|tgz|tbz|txz)\.(?:asc|pgp|gpg|sig|sign)

=item B<@DEB_EXT@>

This is substituted by the typical Debian extension regexp (capturing).

  \+(debian|dfsg|ds|deb)(\.)?(\d+)?$

=back

Some file extensions are not included in the above intentionally to avoid false
positives.  You can still set such file extension patterns manually.

=head1 WATCH FILE OPTIONS

B<uscan> reads the watch options specified in B<opts="> I<...> B<"> to
customize its behavior. Multiple options I<option1>, I<option2>, I<option3>,
... can be set as B<opts=">I<option1>B<,> I<option2>B<,> I<option3>B<,> I< ...
>B<"> .  The double quotes are necessary if options contain any spaces.

Unless otherwise noted as persistent, most options are valid only within their
containing watch line.

The available watch options are:

=over

=item B<component=>I<component>

Set the name of the secondary source tarball as I<<
<spkg>_<oversion>.orig-<component>.tar.gz >> for a MUT package.

=item B<compression=>I<method>

Set the compression I<method> when the tarball is repacked (persistent).

Available I<method> values are B<xz>, B<gzip> (alias B<gz>), B<bzip2> (alias
B<bz2>), and B<lzma>.  The default is B<gzip> for normal tarballs, and B<xz>
for tarballs generated directly from a git repository.

If the debian source format is not 1.0, setting this to B<xz> should
help reduce the package size when the package is repacked.

Please note the repacking of the upstream tarballs by B<mk-origtargz> happens
only if one of the following conditions is satisfied:

=over

=item * B<USCAN_REPACK> is set in the devscript configuration.  See L<DEVSCRIPT
CONFIGURATION VARIABLES>.

=item * B<--repack> is set on the commandline.  See <COMMANDLINE OPTIONS>.

=item * B<repack> is set in the watch line as B<opts="repack,>I<...>B<">.

=item * The upstream archive is of B<zip> type including B<jar>, B<xpi>, ...

=item * B<Files-Excluded> or B<Files-Excluded->I<component> stanzas are set in
F<debian/copyright> to make B<mk-origtargz> invoked from B<uscan> remove
files from the upstream tarball and repack it.  See L<COPYRIGHT FILE
EXAMPLES> and mk-origtargz(1).

=back

=item B<repack>

Force repacking of the upstream tarball using the compression I<method>.

=item B<repacksuffix=>I<suffix>

Add I<suffix> to the Debian package upstream version only when the
source tarball is repackaged.  This rule should be used only for a single
upstream tarball package.

=item B<mode=>I<mode>

Set the archive download I<mode>.

=over

=item B<LWP>

This mode is the default one which downloads the specified tarball from the
archive URL on the web.  Automatically internal B<mode> value is updated to
either B<http> or B<ftp> by URL.

=item B<git>

This mode accesses the upstream git archive directly with the B<git> command
and packs the source tree with the specified tag via I<matching-pattern> into
I<spkg-version>B<.tar.xz>.

If the upstream publishes the released tarball via its web interface, please
use it instead of using this mode.  This mode is the last resort method.

For git mode, I<matching-pattern> specifies the full string matching pattern for
tags instead of hrefs. If I<matching-pattern> is set to
B<refs/tags/>I<tag-matching-pattern>, B<uscan> downloads source from the
B<refs/tags/>I<matched-tag> of the git repository.  The upstream version is
extracted from concatenating the matched parts in B<(> ... B<)> with B<.> .  See
L<WATCH FILE EXAMPLES>.

If I<matching-pattern> is set to B<HEAD>, B<uscan> downloads source from the
B<HEAD> of the git repository and the pertinent I<version> is automatically
generated with the date and hush of the B<HEAD> of the git repository.

If I<matching-pattern> is set to B<heads/>I<branch>, B<uscan> downloads source
from the named I<branch> of the git repository.

The local repository is temporarily created as a bare git repository directory
under the destination directory where the downloaded archive is generated.  This
is normally erased after the B<uscan> execution.  This local repository is kept
if B<--debug> option is used.

=back

=item B<pretty=>I<rule>

Set the upstream version string to an arbitrary format as an optional B<opts>
argument when the I<matching-pattern> is B<HEAD> or B<heads/>I<branch> for
B<git> mode.  For the exact syntax, see the B<get-log> manpage under B<tformat>.
The default is B<pretty=0.0~git%cd.%h>.  No B<uversionmangle> rules is
applicable for this case.

When B<pretty=describe> is used, the upstream version string is the output of
the "B<git describe --tags | sed s/-/./g>" command instead. For example, if the
commit is the B<5>-th after the last tag B<v2.17.12> and its short hash is
B<ged992511>, then the string is B<v2.17.12.5.ged992511> .  For this case, it is
good idea to add B<uversionmangle=s/^/0.0~/> or B<uversionmangle=s/^v//> to make
the upstream version string compatible with Debian.  B<uversionmangle=s/^v//>
may work as well.  Please note that in order for B<pretty=describe> to function
well, upstream need to avoid tagging with random alphabetic tags.

The B<pretty=describe> forces to set B<gitmode=full> to make a full local clone
of the repository automatically.

=item B<date=>I<rule>

Set the date string used by the B<pretty> option to an arbitrary format as an
optional B<opts> argument when the I<matching-pattern> is B<HEAD> or
B<heads/>I<branch> for B<git> mode.  For the exact syntax, see the
B<strftime> manpage.  The default is B<date=%Y%m%d>.

=item B<gitmode=>I<mode>

Set the git clone operation I<mode>. The default is B<gitmode=shallow>.  For
some dumb git server, you may need to manually set B<gitmode=full> to force full
clone operation.

=item B<pgpmode=>I<mode>

Set the PGP/GPG signature verification I<mode>.

=over

=item B<auto>

B<uscan> checks possible URLs for the signature file and autogenerates a
B<pgpsigurlmangle> rule to use it.

=item B<default>

Use B<pgpsigurlmangle=>I<rules> to generate the candidate upstream signature
file URL string from the upstream tarball URL. (default)

If the specified B<pgpsigurlmangle> is missing, B<uscan> checks possible URLs
for the signature file and suggests adding a B<pgpsigurlmangle> rule.

=item B<mangle>

Use B<pgpsigurlmangle=>I<rules> to generate the candidate upstream signature
file URL string from the upstream tarball URL.

=item B<next>

Verify this downloaded tarball file with the signature file specified in the
next watch line.  The next watch line must be B<pgpmode=previous>.  Otherwise,
no verification occurs.

=item B<previous>

Verify the downloaded tarball file specified in the previous watch line with
this signature file.  The previous watch line must be B<pgpmode=next>.

=item B<self>

Verify the downloaded file I<foo.ext> with its self signature and extract its
content tarball file as I<foo>.

=item B<none>

No signature available. (No warning.)

=back

=item B<decompress>

Decompress compressed archive before the pgp/gpg signature verification.

=item B<bare>

Disable all site specific special case code such as URL redirector uses and
page content alterations. (persistent)

=item B<user-agent=>I<user-agent-string>

Set the user-agent string used to contact the HTTP(S) server as
I<user-agent-string>. (persistent)

B<user-agent> option should be specified by itself in the watch line without
I<URL>, to allow using semicolons and commas in it.

=item B<pasv>, B<passive>

Use PASV mode for the FTP connection.

If PASV mode is required due to the client side network environment, set
B<uscan> to use PASV mode via L<COMMANDLINE OPTIONS> or L<DEVSCRIPT
CONFIGURATION VARIABLES> instead.

=item B<active>, B<nopasv>

Don't use PASV mode for the FTP connection.

=item B<unzipopt=>I<options>

Add the extra options to use with the B<unzip> command, such as B<-a>, B<-aa>,
and B<-b>, when executed by B<mk-origtargz>.

=item B<dversionmangle=>I<rules>

Normalize the last upstream version string found in F<debian/changelog> to
compare it to the available upstream tarball version.  Removal of the Debian
specific suffix such as B<s/@DEB_EXT@//> is usually done here.

You can also use B<dversionmangle=auto>, this is exactly the same than
B<dversionmangle=s/@DEB_EXT@//>

=item B<dirversionmangle=>I<rules>

Normalize the directory path string matching the regex in a set of parentheses
of B<http://>I<URL> as the sortable version index string.  This is used as the
directory path sorting index only.

Substitution such as B<s/PRE/~pre/; s/RC/~rc/> may help.

=item B<pagemangle=>I<rules>

Normalize the downloaded web page string.  (Don't use this unless this is
absolutely needed.  Generally, B<g> flag is required for these I<rules>.)

This is handy if you wish to access Amazon AWS or Subversion repositories in
which <a href="..."> is not used.

=item B<uversionmangle=>I<rules>

Normalize the candidate upstream version strings extracted from hrefs in the
source of the web page.  This is used as the version sorting index when
selecting the latest upstream version.

Substitution such as B<s/PRE/~pre/; s/RC/~rc/> may help.

=item B<versionmangle=>I<rules>

Syntactic shorthand for B<uversionmangle=>I<rules>B<, dversionmangle=>I<rules>

=item B<hrefdecode=percent-encoding>

Convert the selected upstream tarball href string from the percent-encoded
hexadecimal string to the decoded normal URL string for obfuscated web sites.
Only B<percent-encoding> is available and it is decoded with
B<s/%([A-Fa-f\d]{2})/chr hex $1/eg>.

=item B<downloadurlmangle=>I<rules>

Convert the selected upstream tarball href string into the accessible URL for
obfuscated web sites.  This is run after B<hrefdecode>.

=item B<filenamemangle=>I<rules>

Generate the upstream tarball filename from the selected href string if
I<matching-pattern> can extract the latest upstream version I<< <uversion> >>
from the selected href string.  Otherwise, generate the upstream tarball
filename from its full URL string and set the missing I<< <uversion> >> from
the generated upstream tarball filename.

Without this option, the default upstream tarball filename is generated by
taking the last component of the URL and removing everything after any '?' or
'#'.

=item B<pgpsigurlmangle=>I<rules>

Generate the candidate upstream signature file URL string from the upstream
tarball URL.

=item B<oversionmangle=>I<rules>

Generate the version string I<< <oversion> >> of the source tarball I<<
<spkg>_<oversion>.orig.tar.gz >> from I<< <uversion> >>.  This should be used
to add a suffix such as B<+dfsg1> to a MUT package.

=back

Here, the mangling rules apply the I<rules> to the pertinent string.  Multiple
rules can be specified in a mangling rule string by making a concatenated
string of each mangling I<rule> separated by B<;> (semicolon).

Each mangling I<rule> cannot contain B<;> (semicolon), B<,> (comma), or B<">
(double quote).

Each mangling I<rule> behaves as if a Perl command "I<$string> B<=~> I<rule>"
is executed.  There are some notable details.

=over

=item * I<rule> may only use the B<s>, B<tr>, and B<y> operations.

=over

=item B<s/>I<regex>B</>I<replacement>B</>I<options>

Regex pattern match and replace the target string.  Only the B<g>, B<i> and
B<x> flags are available.  Use the B<$1> syntax for back references (No
B<\1> syntax).  Code execution is not allowed (i.e. no B<(?{})> or B<(??{})>
constructs).

=item B<y/>I<source>B</>I<dest>B</> or B<tr/>I<source>B</>I<dest>B</>

Transliterate the characters in the target string.

=back

=back

=head1 EXAMPLE OF EXECUTION

B<uscan> reads the first entry in F<debian/changelog> to determine the source
package name and the last upstream version.

For example, if the first entry of F<debian/changelog> is:

=over

=item * I<< bar >> (B<3:2.03+dfsg1-4>) unstable; urgency=low

=back

then, the source package name is I<< bar >> and the last Debian package version
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
the newest version.  If the B<dirversionmangle> rule exists, the generated
sorting index is used to find the newest version.  If a specific version is
specified for the download, the matching version string has priority over the
newest version.

=back

For example, this B<http://>I<URL> may be specified as:

=over

=item * B<http://www.example.org/([\d\.]+)/>

=back

Please note the trailing B</> in the above to make B<([\d\.]+)> as the
directory.

If the B<pagemangle> rule exists, the whole downloaded web page as a string is
normalized by applying this rule to it.  This is very powerful tool and needs
to be used with caution.  If other mangling rules can be used to address your
objective, do not use this rule.

The downloaded web page is scanned for hrefs defined in the B<< <a href=" >>
I<...> B<< "> >> tag to locate the candidate upstream tarball hrefs.  These
candidate upstream tarball hrefs are matched by the Perl regex pattern
I<matching-pattern> such as B<< DL-(?:[\d\.]+?)/foo-(.+)\.tar\.gz >> to narrow
down the candidates.  This pattern match needs to be anchored at the beginning
and the end.  For example, candidate hrefs may be:

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

The downloaded tarball filename is basically set to the same as the filename in
the remote URL of the selected href.

If the B<uversionmangle> rule exists, the candidate upstream versions are
normalized by applying this rule to them. (This rule may be useful if the
upstream version scheme doesn't sort correctly to identify the newest version.)

The upstream tarball href corresponding to the newest (uversionmangled)
candidate upstream version newer than the (dversionmangled) last upstream
version is selected.

If multiple upstream tarball hrefs corresponding to a single version with
different extensions exist, the highest compression one is chosen. (Priority:
B<< tar.xz > tar.lzma > tar.bz2 > tar.gz >>.)

If the selected upstream tarball href is the relative URL, it is converted to
the absolute URL using the base URL of the web page.  If the B<< <base href="
>> I< ... > B<< "> >> tag exists in the web page, the selected upstream tarball
href is converted to the absolute URL using the specified base URL in the base
tag, instead.

If the B<downloadurlmangle> rule exists, the selected upstream tarball href is
normalized by applying this rule to it. (This is useful for some sites with the
obfuscated download URL.)

If the B<filenamemangle> rule exists, the downloaded tarball filename is
generated by applying this rule to the selected href if I<matching-pattern> can
extract the latest upstream version I<< <uversion> >> from the selected href
string. Otherwise, generate the upstream tarball filename from its full URL
string and set the missing I<< <uversion> >> from the generated upstream
tarball filename.

Without the B<filenamemangle> rule, the default upstream tarball filename is
generated by taking the last component of the URL and removing everything after
any '?' or '#'.

B<uscan> downloads the selected upstream tarball to the parent B<../>
directory.  For example, the downloaded file may be:

=over

=item * F<../foo-2.04.tar.gz>

=back

Let's call this downloaded version B<2.04> in the above example generically as
I<< <uversion> >> in the following.

If the B<pgpsigurlmangle> rule exists, the upstream signature file URL is
generated by applying this rule to the (downloadurlmangled) selected upstream
tarball href and the signature file is tried to be downloaded from it.

If the B<pgpsigurlmangle> rule doesn't exist, B<uscan> warns user if the
matching upstream signature file is available from the same URL with their
filename being suffixed by the 5 common suffix B<asc>, B<gpg>, B<pgp>, B<sig>
and B<sign>. (You can avoid this warning by setting B<pgpmode=none>.)

If the signature file is downloaded, the downloaded upstream tarball is checked
for its authenticity against the downloaded signature file using the armored keyring
F<debian/upstream/signing-key.asc>  (see L<KEYRING FILE EXAMPLES>).  If its
signature is not valid, or not made by one of the listed keys, B<uscan> will
report an error.

If the B<oversionmangle> rule exists, the source tarball version I<oversion> is
generated from the downloaded upstream version I<uversion> by applying this
rule. This rule is useful to add suffix such as B<+dfsg1> to the version of all
the source packages of the MUT package for which the repacksuffix mechanism
doesn't work.

B<uscan> invokes B<mk-origtargz> to create the source tarball properly named
for the source package with B<.orig.> (or B<< .orig-<component>. >> for the
secondary tarballs) in its filename.

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

B<uscan> normally invokes "B<uupdate> B<--find --upstream-version> I<oversion>
" for the version=4 watch file.

Please note that B<--find> option is used here since B<mk-origtargz> has been
invoked to make B<*.orig.tar.gz> file already.  B<uscan> picks I<< bar >> from
F<debian/changelog>.

It creates the new upstream source tree under the I<< ../bar-<oversion> >>
directory and Debianize it leveraging the last package contents.

=head1 WATCH FILE EXAMPLES

When writing the watch file, you should rely on the latest upstream source
announcement web page.  You should not try to second guess the upstream archive
structure if possible.  Here are the typical F<debian/watch> files.

Please note that executing B<uscan> with B<-v> or B<-vv> reveals what exactly
happens internally.

The existence and non-existence of a space the before tailing B<\> (back slash)
are significant.

Some undocumented shorter configuration strings are used in the below EXAMPLES
to help you with typing.  These are intentional ones.  B<uscan> is written to
accept such common sense abbreviations but don't push the limit.

=head2 HTTP site (basic)

Here is an example for the basic single upstream tarball.

  version=4
  http://example.com/~user/release/foo.html \
      files/foo-([\d\.]+)\.tar\.gz debian uupdate

Or using the special strings:

  version=4
  http://example.com/~user/release/@PACKAGE@.html \
      files/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian uupdate

For the upstream source package B<foo-2.0.tar.gz>, this watch file downloads
and creates the Debian B<orig.tar> file B<foo_2.0.orig.tar.gz>.

=head2 HTTP site (pgpsigurlmangle)

Here is an example for the basic single upstream tarball with the matching
signature file in the same file path.

  version=4
  opts="pgpsigurlmangle=s%$%.asc%" http://example.com/release/@PACKAGE@.html \
      files/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian uupdate

For the upstream source package B<foo-2.0.tar.gz> and the upstream signature
file B<foo-2.0.tar.gz.asc>, this watch file downloads these files, verifies the
authenticity using the keyring F<debian/upstream/signing-key.asc> and creates the
Debian B<orig.tar> file B<foo_2.0.orig.tar.gz>.

Here is another example for the basic single upstream tarball with the matching
signature file on decompressed tarball in the same file path.

  version=4
  opts="pgpsigurlmangle=s%@ARCHIVE_EXT@$%.asc%,decompress" \
      http://example.com/release/@PACKAGE@.html \
      files/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian uupdate

For the upstream source package B<foo-2.0.tar.gz> and the upstream signature
file B<foo-2.0.tar.asc>, this watch file downloads these files, verifies the
authenticity using the keyring F<debian/upstream/signing-key.asc> and creates the
Debian B<orig.tar> file B<foo_2.0.orig.tar.gz>.

=head2 HTTP site (pgpmode=next/previous)

Here is an example for the basic single upstream tarball with the matching
signature file in the unrelated file path.

  version=4
  opts="pgpmode=next" http://example.com/release/@PACKAGE@.html \
      files/(?:\d+)/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian
  opts="pgpmode=previous" http://example.com/release/@PACKAGE@.html \
      files/(?:\d+)/@PACKAGE@@ANY_VERSION@@SIGNATURE_EXT@ previous uupdate

B<(?:\d+)> part can be any random value.  The tarball file can have B<53>,
while the signature file can have B<33>.

B<([\d\.]+)> part for the signature file has a strict requirement to match that
for the upstream tarball specified in the previous line by having B<previous>
as I<version> in the watch line.

=head2 HTTP site (flexible)

Here is an example for the maximum flexibility of upstream tarball and
signature file extensions.

  version=4
  opts="pgpmode=next" http://example.com/DL/ \
      files/(?:\d+)/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian
  opts="pgpmode=previous" http://example.com/DL/ \
      files/(?:\d+)/@PACKAGE@@ANY_VERSION@@SIGNATURE_EXT@ \
      previous uupdate

=head2 HTTP site (basic MUT)

Here is an example for the basic multiple upstream tarballs.

  version=4
  opts="pgpsigurlmangle=s%$%.sig%" \
      http://example.com/release/foo.html \
      files/foo-([\d\.]+)\.tar\.gz debian
  opts="pgpsigurlmangle=s%$%.sig%, component=bar" \
      http://example.com/release/foo.html \
      files/foobar-([\d\.]+)\.tar\.gz same
  opts="pgpsigurlmangle=s%$%.sig%, component=baz" \
      http://example.com/release/foo.html \
      files/foobaz-([\d\.]+)\.tar\.gz same uupdate

For the main upstream source package B<foo-2.0.tar.gz> and the secondary
upstream source packages B<foobar-2.0.tar.gz> and B<foobaz-2.0.tar.gz> which
install under F<bar/> and F<baz/>, this watch file downloads and creates the
Debian B<orig.tar> file B<foo_2.0.orig.tar.gz>, B<foo_2.0.orig-bar.tar.gz> and
B<foo_2.0.orig-baz.tar.gz>.  Also, these upstream tarballs are verified by
their signature files.

=head2 HTTP site (recursive directory scanning)

Here is an example with the recursive directory scanning for the upstream tarball
and its signature files released in a directory named
after their version.

  version=4
  opts="pgpsigurlmangle=s%$%.sig%, dirversionmangle=s/-PRE/~pre/;s/-RC/~rc/" \
      http://tmrc.mit.edu/mirror/twisted/Twisted/([\d+\.]+)/ \
      Twisted-([\d\.]+)\.tar\.xz debian uupdate

Here, the web site should be accessible at the following URL:

  http://tmrc.mit.edu/mirror/twisted/Twisted/

Here, B<dirversionmangle> option is used to normalize the sorting order of the
directory names.

=head2 HTTP site (alternative shorthand)

For the bare HTTP site where you can directly see archive filenames, the normal
watch file:

  version=4
  opts="pgpsigurlmangle=s%$%.sig%" \
      http://www.cpan.org/modules/by-module/Text/ \
      Text-CSV_XS-(.+)\.tar\.gz \
      debian uupdate

can be rewritten in an alternative shorthand form only with a single string
covering URL and filename:

  version=4
  opts="pgpsigurlmangle=s%$%.sig%" \
      http://www.cpan.org/modules/by-module/Text/Text-CSV_XS-(.+)\.tar\.gz \
      debian uupdate

In version=4, initial white spaces are dropped.  Thus, this alternative
shorthand form can also be written as:

  version=4
  opts="pgpsigurlmangle=s%$%.sig%" \
      http://www.cpan.org/modules/by-module/Text/\
      Text-CSV_XS-(.+)\.tar\.gz \
      debian uupdate

Please note the subtle difference of a space before the tailing B<\>
between the first and the last examples.

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
and removing everything after any '?' or '#'.

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

If the href string has no version using <I>matching-pattern>, the version can
be obtained from the full URL using B<filenamemangle>.

  version=4
  opts=filenamemangle=s&.*/dl/(.*)/foo\.tar\.gz&foo-$1\.tar\.gz& \
  http://foo.bar.org/dl/([\.\d]+)/ foo.tar.gz \
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
  files/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian uupdate

Please note the use of B<g> here to replace all occurrences.

If F<foo.html> uses B<< <Key> >> I<< ... >> B<< </Key> >>, this can be
converted to the standard page format with:

  version=4
  opts="pagemangle=s%<Key>([^<]*)</Key>%<Key><a href="$1">$1</a></Key>%g" \
  http://example.com/release/foo.html \
  (?:.*)/@PACKAGE@@ANY_VERSION@@ARCHIVE_EXT@ debian uupdate

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

=head2 sf.net

For SourceForge based projects, qa.debian.org runs a redirector which allows a
simpler form of URL. The format below will automatically be rewritten to use
the redirector with the watch file:

  version=4
  https://sf.net/<project>/ <tar-name>-(.+)\.tar\.gz debian uupdate

For B<audacity>, set the watch file as:

  version=4
  https://sf.net/audacity/ audacity-minsrc-(.+)\.tar\.gz debian uupdate

Please note, you can still use normal functionalities of B<uscan> to set up a
watch file for this site without using the redirector.

  version=4
  opts="uversionmangle=s/-pre/~pre/, \
	filenamemangle=s%(?:.*)audacity-minsrc-(.+)\.tar\.xz/download%\
                         audacity-$1.tar.xz%" \
	http://sourceforge.net/projects/audacity/files/audacity/(\d[\d\.]+)/ \
	(?:.*)audacity-minsrc-([\d\.]+)\.tar\.xz/download debian uupdate

Here, B<%> is used as the separator instead of the standard B</>.

=head2 github.com

For GitHub based projects, you can use the tags or releases page.  The archive
URL uses only the version as the filename.  You can rename the downloaded
upstream tarball from into the standard F<< <project>-<version>.tar.gz >> using
B<filenamemangle>:

  version=4
  opts="filenamemangle=s%(?:.*?)?v?(\d[\d.]*)\.tar\.gz%<project>-$1.tar.gz%" \
      https://github.com/<user>/<project>/tags \
      (?:.*?/)?v?(\d[\d.]*)\.tar\.gz debian uupdate

=head2 PyPI

For PyPI based projects, pypi.debian.net runs a redirector which allows a
simpler form of URL. The format below will automatically be rewritten to use
the redirector with the watch file:

  version=4
  https://pypi.python.org/packages/source/<initial>/<project>/ \
      <tar-name>-(.+)\.tar\.gz debian uupdate

For B<cfn-sphere>, set the watch file as:

  version=4
  https://pypi.python.org/packages/source/c/cfn-sphere/ \
      cfn-sphere-([\d\.]+).tar.gz debian uupdate

Please note, you can still use normal functionalities of B<uscan> to set up a
watch file for this site without using the redirector.

  version=4
  opts="pgpmode=none" \
      https://pypi.python.org/pypi/cfn-sphere/ \
      https://pypi.python.org/packages/.*/.*/.*/\
      cfn-sphere-([\d\.]+).tar.gz#.* debian uupdate

=head2 code.google.com

Sites which used to be hosted on the Google Code service should have migrated
to elsewhere (github?).  Please look for the newer upstream site if available.

=head2 direct access to the git repository (tags)

If the upstream only publishes its code via the git repository and its code has
no web interface to obtain the release tarball, you can use B<uscan> with the
tags of the git repository to track and package the new upstream release.

  version=4
  opts="mode=git, gitmode=full, pgpmode=none" \
  http://git.ao2.it/tweeper.git \
  refs/tags/v([\d\.]+) debian uupdate

Please note "B<git ls-remote>" is used to obtain references for tags.

If a tag B<v20.5> is the newest tag, the above example downloads
I<spkg>B<-20.5.tar.xz> after making a full clone of the git repository which is
needed for dumb git server.

=head2 direct access to the git repository (HEAD)

If the upstream only publishes its code via the git repository and its code has
no web interface nor the tags to obtain the released tarball, you can use
B<uscan> with the HEAD of the git repository to track and package the new
upstream release with an automatically generated version string.

  version=4
  opts="mode=git, pgpmode=none" \
  https://github.com/Debian/dh-make-golang \
  HEAD debian uupdate

Please note that a local shallow copy of the git repository is made with "B<git
clone --bare --depth=1> ..." normally in the target directory.  B<uscan>
generates the new upstream version with "B<git log --date=format:%Y%m%d
--pretty=0.0~git%cd.%h>" on this local copy of repository as its default
behavior.

The generation of the upstream version string may the adjusted to your taste by
adding B<pretty> and B<date> options to the B<opts> arguments.

=head1 COPYRIGHT FILE EXAMPLES

Here is an example for the F<debian/copyright> file which initiates automatic
repackaging of the upstream tarball into I<< <spkg>_<oversion>.orig.tar.gz >>
(In F<debian/copyright>, the B<Files-Excluded> and
B<Files-Excluded->I<component> stanzas are a part of the first paragraph and
there is a blank line before the following paragraphs which contain B<Files>
and other stanzas.):

  Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
  Files-Excluded: exclude-this
   exclude-dir
   */exclude-dir
   .*
   */js/jquery.js

   Files: *
   Copyright: ...
   ...

Here is another example for the F<debian/copyright> file which initiates
automatic repackaging of the multiple upstream tarballs into
I<< <spkg>_<oversion>.orig.tar.gz >> and
I<< <spkg>_<oversion>.orig-bar.tar.gz >>:

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

   Files: *
   Copyright: ...
   ...

See mk-origtargz(1).

=head1 KEYRING FILE EXAMPLES

Let's assume that the upstream "B<< uscan test key (no secret)
<none@debian.org> >>" signs its package with a secret OpenPGP key and publishes
the corresponding public OpenPGP key.  This public OpenPGP key can be
identified in 3 ways using the hexadecimal form.

=over

=item * The fingerprint as the 20 byte data calculated from the public OpenPGP
key. E.  g., 'B<CF21 8F0E 7EAB F584 B7E2 0402 C77E 2D68 7254 3FAF>'

=item * The long keyid as the last 8 byte data of the fingerprint. E. g.,
'B<C77E2D6872543FAF>'

=item * The short keyid is the last 4 byte data of the fingerprint. E. g.,
'B<72543FAF>'

=back

Considering the existence of the collision attack on the short keyid, the use
of the long keyid is recommended for receiving keys from the public key
servers.  You must verify the downloaded OpenPGP key using its full fingerprint
value which you know is the trusted one.

The armored keyring file F<debian/upstream/signing-key.asc> can be created by
using the B<gpg> (or B<gpg2>) command as follows.

  $ gpg --recv-keys "C77E2D6872543FAF"
  ...
  $ gpg --finger "C77E2D6872543FAF"
  pub   4096R/72543FAF 2015-09-02
        Key fingerprint = CF21 8F0E 7EAB F584 B7E2  0402 C77E 2D68 7254 3FAF
  uid                  uscan test key (no secret) <none@debian.org>
  sub   4096R/52C6ED39 2015-09-02
  $ cd path/to/<upkg>-<uversion>
  $ mkdir -p debian/upstream
  $ gpg --export --export-options export-minimal --armor \
        'CF21 8F0E 7EAB F584 B7E2  0402 C77E 2D68 7254 3FAF' \
        >debian/upstream/signing-key.asc

The binary keyring files, F<debian/upstream/signing-key.pgp> and
F<debian/upstream-signing-key.pgp>, are still supported but deprecated.

If a group of developers sign the package, you need to list fingerprints of all
of them in the argument for B<gpg --export ...> to make the keyring to contain
all OpenPGP keys of them.

Sometimes you may wonder who made a signature file.  You can get the public
keyid used to create the detached signature file F<foo-2.0.tar.gz.asc> by
running B<gpg> as:

  $ gpg -vv foo-2.0.tar.gz.asc
  gpg: armor: BEGIN PGP SIGNATURE
  gpg: armor header: Version: GnuPG v1
  :signature packet: algo 1, keyid C77E2D6872543FAF
  	version 4, created 1445177469, md5len 0, sigclass 0x00
  	digest algo 2, begin of digest 7a c7
  	hashed subpkt 2 len 4 (sig created 2015-10-18)
  	subpkt 16 len 8 (issuer key ID C77E2D6872543FAF)
  	data: [4091 bits]
  gpg: assuming signed data in `foo-2.0.tar.gz'
  gpg: Signature made Sun 18 Oct 2015 11:11:09 PM JST using RSA key ID 72543FAF
  ...

=head1 COMMANDLINE OPTIONS

For the basic usage, B<uscan> does not require to set these options.

=over

=item B<--no-conf>, B<--noconf>

Don't read any configuration files. This can only be used as the first option
given on the command-line.

=item B<--no-verbose>

Don't report verbose information. (default)

=item B<--verbose>, B<-v>

Report verbose information.

=item B<--debug>, B<-vv>

Report verbose information including the downloaded
web pages as processed to STDERR for debugging.

=item B<--dehs>

Send DEHS style output (XML-type) to STDOUT, while
send all other uscan output to STDERR.

=item B<--no-dehs>

Use only traditional uscan output format. (default)

=item B<--download>, B<-d>

Download the new upstream release. (default)

=item B<--force-download>, B<-dd>

Download the new upstream release even if up-to-date. (may not overwrite the local file)

=item B<--overwrite-download>, B<-ddd>

Download the new upstream release even if up-to-date. (may overwrite the local file)

=item B<--no-download>, B<--nodownload>

Don't download and report information.

Previously downloaded tarballs may be used.

Change default to B<--skip-signature>.

=item B<--signature>

Download signature. (default)

=item B<--no-signature>

Don't download signature but verify if already downloaded.

=item B<--skip-signature>

Don't bother download signature nor verifying signature.

=item B<--safe>, B<--report>

Avoid running unsafe scripts by skipping both the repacking of the downloaded
package and the updating of the new source tree.

Change default to B<--no-download> and B<--skip-signature>.

When the objective of running B<uscan> is to gather the upstream package status
under the security conscious environment, please make sure to use this option.

=item B<--report-status>

This is equivalent of setting "B<--verbose --safe>".

=item B<--download-version> I<version>

Specify the I<version> which the upstream release must match in order to be
considered, rather than using the release with the highest version.
(a best effort feature)

=item B<--download-debversion> I<version>

Specify the Debian package version to download the corresponding upstream
release version.  The B<dversionmangle> and B<uversionmangle> rules are considered.
(a best effort feature)

=item B<--download-current-version>

Download the currently packaged version.
(a best effort feature)

=item B<--check-dirname-level> I<N>

See the below section L<Directory name checking> for an explanation of this option.

=item B<--check-dirname-regex> I<regex>

See the below section L<Directory name checking> for an explanation of this option.

=item B<--destdir> I<path>
Normally, B<uscan> changes its internal current directory to the package's
source directory where the F<debian/> is located.  Then the destination
directory for the downloaded tarball and other files is set to the parent
directory F<../> from this internal current directory.

This default destination directory can be overridden by setting B<--destdir>
option to a particular I<path>.  If this I<path> is a relative path, the
destination directory is determined in relative to the internal current
directory of B<uscan> execution. If this I<path> is a absolute path, the
destination directory is set to I<path> irrespective of the internal current
directory of B<uscan> execution.

The above is true not only for the sinple B<uscan> run in the single source tree
but also for the advanced scanning B<uscan> run with subdirectories holding
multiple source trees.

One exception is when B<--watchfile> and B<--package> are used together.  For
this case, the internal current directory of B<uscan> execution and the default
destination directory are set to the current directory F<.> where B<uscan> is
started.  The default destination directory can be overridden by setting
B<--destdir> option as well.

=item B<--package> I<package>

Specify the name of the package to check for rather than examining
F<debian/changelog>; this requires the B<--upstream-version> (unless a version
is specified in the F<watch> file) and B<--watchfile> options as well.
Furthermore, no directory scanning will be done and nothing will be downloaded.
This option automatically sets B<--no-download> and B<--skip-signature>; and
probably most useful in conjunction with the DEHS system (and B<--dehs>).

=item B<--upstream-version> I<upstream-version>

Specify the current upstream version rather than examine F<debian/watch> or
F<debian/changelog> to determine it. This is ignored if a directory scan is being
performed and more than one F<debian/watch> file is found.

=item B<--watchfile> I<watchfile>

Specify the I<watchfile> rather than perform a directory scan to determine it.
If this option is used without B<--package>, then B<uscan> must be called from
within the Debian package source tree (so that F<debian/changelog> can be found
simply by stepping up through the tree).

One exception is when B<--watchfile> and B<--package> are used together.
B<uscan> can be called from anywhare and the internal current directory of
B<uscan> execution and the default destination directory are set to the current
directory F<.> where B<uscan> is started.

See more in the B<--destdir> explanation.

=item B<--bare>

Disable all site specific special case codes to perform URL redirections and
page content alterations.

=item B<--no-exclusion>

Don't automatically exclude files mentioned in F<debian/copyright> field B<Files-Excluded>.

=item B<--pasv>

Force PASV mode for FTP connections.

=item B<--no-pasv>

Don't use PASV mode for FTP connections.

=item B<--no-symlink>

Don't rename nor repack upstream tarball.

=item B<--timeout> I<N>

Set timeout to I<N> seconds (default 20 seconds).

=item B<--user-agent>, B<--useragent>

Override the default user agent header.

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

After having downloaded an lzma tar, xz tar, bzip tar, gz tar, zip, jar, xpi
archive, repack it to the specified compression (see B<--compression>).

The unzip package must be installed in order to repack zip and jar archives,
the mozilla-devscripts package must be installed to repack xpi archives, and
the xz-utils package must be installed to repack lzma or xz tar archives.

=item B<--compression> [ B<gzip> | B<bzip2> | B<lzma> | B<xz> ]

In the case where the upstream sources are repacked (either because B<--repack>
option is given or F<debian/copyright> contains the field B<Files-Excluded>),
it is possible to control the compression method via the parameter.  The
default is B<gzip> for normal tarballs, and B<xz> for tarballs generated
directly from the git repository.

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
is equivalent to the B<--no-download> options.

=item B<USCAN_SAFE>

If this is set to B<yes>, then B<uscan> avoids running unsafe scripts by
skipping both the repacking of the downloaded package and the updating of the
new source tree; this is equivalent to the B<--safe> options; this also sets
the default to B<--no-download> and B<--skip-signature>.

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
B<rename>, then the files are renamed (equivalent to the B<--rename> option).

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
tar, or zip archive, uscan will repack it to the specified compression (see
B<--compression>). This is equivalent to the B<--repack> option.

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

If you are not sure what exactly is happening behind the scene, please enable
the B<--verbose> option.  If this is not enough, enable the B<--debug> option
too see all the internal activities.

See L<COMMANDLINE OPTIONS> and L<DEVSCRIPT CONFIGURATION VARIABLES> for other
variations.

=head2 Custom script

The optional I<script> parameter in F<debian/watch> means to execute I<script>
with options after processing this line if specified.

See L<HISTORY AND UPGRADING> for how B<uscan> invokes the custom I<script>.

For compatibility with other tools such as B<git-buildpackage>, it may not be
wise to create custom scripts with random behavior.  In general, B<uupdate> is
the best choice for the non-native package and custom scripts, if created,
should behave as if B<uupdate>.  For possible use case, see
L<http://bugs.debian.org/748474> as an example.

=head2 URL diversion

Some popular web sites changed their web page structure causing maintenance
problems to the watch file.  There are some redirection services created to
ease maintenance of the watch file.  Currently, B<uscan> makes automatic
diversion of URL requests to the following URLs to cope with this situation.

=over

=item * L<http://sf.net>

=item * L<http://pypi.python.org>

=back

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

Only check the directory name if we have had to change directory in
our search for F<debian/changelog>, that is, the directory containing
F<debian/changelog> is not the directory from which B<uscan> was invoked.
This is the default behavior.

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

=over

=item * B<uscan> invokes the custom I<script> as "I<script> B<--upstream-version>
I<version> B<../>I<spkg>B<_>I<version>B<.orig.tar.gz>".

=item * B<uscan> invokes the standard B<uupdate> as "B<uupdate> B<--no-symlink
--upstream-version> I<version> B<../>I<spkg>B<_>I<version>B<.orig.tar.gz>".

=back

=item Version 4

B<devscripts> version 2.15.10: The first incarnation of F<watch> files
supporting multiple upstream tarballs.

The syntax of the watch file is relaxed to allow more spaces for readability.

If you have a custom script in place of B<uupdate>, you may also encounter
problems updating from Version 3.

=over

=item * B<uscan> invokes the custom I<script> as "I<script> B<--upstream-version>
I<version>".

=item * B<uscan> invokes the standard B<uupdate> as "B<uupdate> B<--find>
B<--upstream-version> I<version>".

=back

Restriction for B<--dehs> is lifted by redirecting other output to STDERR when
it is activated.

=back

=head1 SEE ALSO

dpkg(1), mk-origtargz(1), perlre(1), uupdate(1), devscripts.conf(5)

=head1 AUTHOR

The original version of uscan was written by Christoph Lameter
<clameter@debian.org>. Significant improvements, changes and bugfixes were
made by Julian Gilbey <jdg@debian.org>. HTTP support was added by Piotr
Roszatycki <dexter@debian.org>. The program was rewritten in Perl by Julian
Gilbey. Xavier Guimard converted it in object-oriented Perl using L<Moo>.

=cut

#######################################################################
# }}} code 0: POD for manpage
#######################################################################
#######################################################################
# {{{ code 1: initializer, command parser, and loop over watchfiles
#######################################################################

# This code block is the start up of uscan.
# Actual processing is performed by process_watchfile in the next block
#
# This has 3 different modes to process watchfiles
#
#  * If $opt_watchfile and $opt_package are defined, test specified watchfile
#    without changelog (sanity check for $opt_uversion may be good idea)
#  * If $opt_watchfile is defined but $opt_package isn't defined, test specified
#    watchfile assuming you are in source tree and debian/changelogis used to
#    set variables
#  * If $opt_watchfile isn't defined, scan subdirectories of directories
#    specified as ARGS (if none specified, "." is scanned).
#    * Normal packaging has no ARGS and uses "."
#    * Archive status scanning tool uses many ARGS pointing to the expanded
#      source tree to be checked.
# Comments below focus on Normal packaging case and sometimes ignores first 2
# watch file testing setup.

use 5.010;    # defined-or (//)
use strict;
use warnings;
use Cwd qw/cwd/;
use Devscripts::Uscan::Config;
use Devscripts::Uscan::FindFiles;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::WatchFile;

our $uscan_version = "###VERSION###";

BEGIN {
    pop @INC if $INC[-1] eq '.';
}

my $config = Devscripts::Uscan::Config->new->parse;

# Did we find any new upstream versions on our wanderings?
our $found = 0;

my @wf = find_watch_files($config);
foreach (@wf) {
    process_watchfile(@$_);

    # Are there any warnings to give if we're using dehs?
    dehs_output if ($dehs);
}

uscan_verbose "Scan finished";

# Are there any warnings to give if we're using dehs?
$dehs_end_output = 1;
dehs_output if ($dehs);
exit( $found ? 0 : 1 );

#######################################################################
# {{{ code 2: process watchfile by looping over watchline
#######################################################################

sub process_watchfile {
    my ( $pkg_dir, $package, $version, $watchfile ) = @_;
    my $opwd = cwd();

    my $wf = Devscripts::Uscan::WatchFile->new(
        {
            config      => $config,
            package     => $package,
            pkg_dir     => $pkg_dir,
            pkg_version => $version,
            watchfile   => $watchfile,
        }
    );
    return $wf->status if ( $wf->status );

    chdir $pkg_dir;
    my $res = $wf->process_lines;
    chdir $opwd;
    return $res;
}
#######################################################################
# }}} code 2: process watchfile by looping over watchline
#######################################################################

