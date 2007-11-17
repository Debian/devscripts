#!/usr/bin/perl -w
#
# debcheckout: checkout the development repository of a Debian package
# Copyright (C) 2007  Stefano Zacchiroli <zack@debian.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Created: Tue, 14 Aug 2007 10:20:55 +0200
# Last-Modified: $Date$ 

=head1 NAME

debcheckout - checkout the development repository of a Debian package

=head1 SYNOPSIS

=over

=item B<debcheckout> [I<OPTIONS>] I<PACKAGE> [I<DESTDIR>]

=item B<debcheckout> [I<OPTIONS>] I<REPOSITORY_URL> [I<DESTDIR>]

=item B<debcheckout> B<--help>

=back

=head1 DESCRIPTION

B<debcheckout> retrieves the information about the Version Control System used
to maintain a given Debian package (the I<PACKAGE> argument), and then checks
out the latest (potentially unreleased) version of the package from its
repository.  By default the repository is checked out to the I<PACKAGE>
directory; it can be overridden providing the I<DESTDIR> argument.

The information about where the repository is available is expected to be found
in B<Vcs-*> fields available in the source package record. For example, the vim
package exposes such an information with a field like S<Vcs-Svn:
svn://svn.debian.org/svn/pkg-vim/trunk/packages/vim>, you can see it grepping
through C<apt-cache showsrc vim>.

If you already know the URL of a given repository you can invoke debcheckout
directly on it, but you will probably need to pass the appropriate B<-t> flag.

The currently supported version control systems are: arch, bzr, cvs, darcs, git,
hg, svn.

=head1 OPTIONS

=over

=item B<-a>, B<--auth>

work in authenticated mode; this means that for known repositories (mainly those
hosted on S<http://alioth.debian.org>) URL rewriting is attempted before
checking out, to ensure that the repository can be committed to. For example,
for subversion repositories hosted on alioth this means that
S<svn+ssh://svn.debian.org/...> will be used instead of
S<svn://svn.debian.org/...>

=item B<-h>, B<--help>

print a detailed help message and exit

=item B<-p>, B<--print>

only print information about the package repository, without checking it out;
the output format is TAB-separated with two fields: repository type, repository
URL

=item B<-t> I<TYPE>, B<--type> I<TYPE>

set the repository type (defaults to "svn"), should be one of the currently
supported repository types

=item B<-u> I<USERNAME>, B<--user> I<USERNAME>

specify the login name to be used in authenticated mode (see B<-a>). This option
implies B<-a>: you don't need to specify both

=back

=head1 SEE ALSO

apt-cache(8), Section 4.10.4 of the Debian Developer's Reference and/or
Bug#391023 in the Debian Bug Tracking System (for more information about Vcs-*
fields)

=head1 AUTHOR

debcheckout and this manpage have been written by Stefano Zacchiroli
<zack@debian.org>

=cut

use strict;
use Switch;
use Getopt::Long;
use Pod::Usage;

# Find the repository URL (and type) for a given package name, parsing Vcs-*
# fields.
sub find_repo($) {
  my ($pkg) = @_;
  my @repo = (0, "");
  my $found = 0;

  open(APT, "apt-cache showsrc $pkg |");
  while (my $line = <APT>) {
    $found = 1;
    chomp($line);
    if ($line =~ /^(x-)?vcs-(\w+):\s*(.*)$/i) {
      next if lc($2) eq "browser";
      @repo = (lc($2), $3);
      last;
    }
  }
  close(APT);
  die "unknown package '$pkg'\n" unless $found;
  return @repo;
}

# Patch the cmdline invocation of a VCS to ensure the repository is checkout to
# a given target directory.
sub set_destdir(@$$) {
  my ($repo_type, $destdir, @cmd) = @_;

  switch ($repo_type) {
    case "cvs"	{ my $module = pop @cmd; push @cmd, ("-d", $destdir, $module); }
    case /^(bzr|darcs|git|hg|svn)$/
		{ push @cmd, $destdir; }
    else { die "sorry, don't know how to set the destination directory for $repo_type repositories (patches welcome!)\n"; }
  }
  return @cmd;
}

# Patch a given repository URL to ensure that the checkoud out repository can be
# committed to. Only works for well known repositories (mainly Alioth's).
sub set_auth($$$) {
  my ($repo_type, $url, $user) = @_;

  my $old_url = $url;
  $user .= "@" if length $user;
  switch ($repo_type) {
    case "bzr"	  { $url =~ s|^\w+://(bzr\.debian\.org)/(.*)|sftp://$user$1/bzr/$2|;
		    $url =~ s[^\w+://(?:bazaar|code)(\.launchpad\.net/.*)][bzr+ssh://${user}bazaar$1]; }
    case "git"    { $url =~ s|^\w+://(git\.debian\.org/.*)|git+ssh://$user$1|; }
    case "hg"     { $url =~ s|^\w+://(hg\.debian\.org/.*)|ssh://$user$1|; }
    case "svn"	  { $url =~ s|^\w+://(svn\.debian\.org)/(.*)|svn+ssh://$user$1/svn/$2|; }
    else { die "sorry, don't know how to enable authentication for $repo_type repositories (patches welcome!)\n"; }
  }
  die "can't use authenticated mode on repository '$url' since it is not a known repository (e.g. alioth)\n"
    if $url eq $old_url;
  return $url;
}

# Checkout a given repository in a given destination directory.
sub checkout_repo($$$) {
  my ($repo_type, $repo_url, $destdir) = @_;
  my @cmd;

  switch ($repo_type) {
    case "arch"	  { @cmd = ("tla", "grab", $repo_url); }  # XXX ???
    case "bzr"    { @cmd = ("bzr", "branch", $repo_url); }
    case "cvs"    { my ($root, $module) = split /\s+/, $repo_url;
                    @cmd = ("cvs", "-d", $root, "checkout", $module); }
    case "darcs"  { @cmd = ("darcs", "get", $repo_url); }
    case "git"    { @cmd = ("git", "clone", $repo_url); }
    case "hg"     { @cmd = ("hg", "clone", $repo_url); }
    case "svn"    { @cmd = ("svn", "co", $repo_url); }
    else { die "unsupported version control system '$repo_type'.\n"; }
  }
  @cmd = set_destdir($repo_type, $destdir, @cmd) if $destdir;
  print "@cmd ...\n";
  system @cmd;
  return ($? >> 8);
}

# Print information about a repository and quit.
sub print_repo($$) {
  my ($repo_type, $repo_url) = @_;

  print "$repo_type\t$repo_url\n";
  exit(0);
}

# Does a given string match the lexical rules for package names?
sub is_package($) {
  my ($arg) = @_;

  return ($arg =~ /^[a-z0-9.+-]+$/);  # lexical rule for package names
}

sub main() {
  my $auth = 0;		  # authenticated mode
  my $destdir = "";	  # destination directory
  my $pkg = "";		  # package name
  my $print_only = 0;	  # print only mode
  my $repo_type = "svn";  # default repo typo, overridden by '-t'
  my $repo_url = "";	  # repository URL
  my $user = "";	  # login name (authenticated mode only)
  GetOptions(
      "auth|a" => \$auth,
      "help|h" => sub { pod2usage({-exitval => 0, -verbose => 1}); },
      "print|p" => \$print_only,
      "type|t=s" => \$repo_type,
      "user|u=s" => \$user,
    ) or pod2usage({-exitval => 3});
  pod2usage({-exitval => 3}) if ($#ARGV < 0 or $#ARGV > 1);

  # -u|--user implies -a|--auth
  $auth = 1 if $user;

  $destdir = $ARGV[1] if $#ARGV > 0;
  if (not is_package($ARGV[0])) {  # repo-url passed on the command line
    $repo_url = $ARGV[0];
  } else {  # package name passed on the command line
    $pkg = $ARGV[0];
    ($repo_type, $repo_url) = find_repo($pkg);
    unless ($repo_type) {
      print <<EOF;
No repository found for package '$pkg', a Vcs-* field is missing in its source
record (see Debian Developer's Reference 4.10.4 and/or Bug#391023).
If you know that the package is maintained via a Version Control System consider
asking the maintainer to expose such information.
EOF
      exit(1);
    }
  }

  $repo_url = set_auth($repo_type, $repo_url, $user) if $auth;
  print_repo($repo_type, $repo_url) if $print_only; # ... then quit
  if (length $pkg) {
    print "declared $repo_type repository at $repo_url\n";
    $destdir = $pkg unless length $destdir;
  }
  my $rc = checkout_repo($repo_type, $repo_url, $destdir);
  if ($rc != 0) {
    print STDERR
      "checkout failed (the command shown above returned non-zero exit code)\n";
  }
  exit($rc);
}

main();

