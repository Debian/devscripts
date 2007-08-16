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

# TODO add a couple of options -a/-l. The former will make debcheckout work in
#      "authenticated mode"; for repositories with known prefixes (basically:
#      alioth's) that would rewrite the checkout URL so that commits are
#      possible. The latter implies the former, but also permits to specify the
#      alioth login name to be used for authenticated actions.

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

=item B<-h>, B<--help>

print a detailed help message and exit

=item B<-p>, B<--print>

only print information about the package repository, without checking it out;
the output format is TAB-separated with two fields: repository type, repository
URL

=item B<-t> I<TYPE>, B<--type> I<TYPE>

set the repository type (defaults to "svn"), should be one of the currently
supported repository types

=back

=head1 SEE ALSO

apt-cache(8), Section 4.10.4 of the Debian Developer's Reference (for more
information about Vcs-* fields)

=head1 AUTHOR

debcheckout and this manpage have been written by Stefano Zacchiroli
<zack@debian.org>

=cut

use strict;
use Switch;
use Getopt::Long;
use Pod::Usage;

sub find_repo($) {
  my ($pkg) = @_;
  my @repo = (0, "");

  open(APT, "apt-cache showsrc $pkg |");
  while (my $line = <APT>) {
    chomp($line);
    if ($line =~ /^(x-)?vcs-(\w+):\s*(.*)$/i) {
      next if lc($2) eq "browser";
      @repo = (lc($2), $3);
      last;
    }
  }
  close(APT);

  return @repo;
}

sub set_destdir(@$$) {
  my ($repo_type, $destdir, @cmd) = @_;

  switch ($repo_type) {
    case "bzr"    { push @cmd, $destdir; }
    case "cvs"    { my $module = pop @cmd; push @cmd, ("-d", $destdir, $module); }
    case "darcs"  { push @cmd, $destdir; }
    case "git"    { push @cmd, $destdir; }
    case "hg"     { push @cmd, $destdir; }
    case "svn"    { push @cmd, $destdir; }
    else          { die "sorry, but I don't know how to set the destination directory for '$repo_type' repositories\n"; }
  }
  return @cmd;
}

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
    else          { die "unsupported version control system '$repo_type'.\n"; }
  }
  @cmd = set_destdir($repo_type, $destdir, @cmd) if $destdir;
  print "@cmd ...\n";
  system @cmd;
  return ($? >> 8);
}

sub print_repo($$) {
  my ($repo_type, $repo_url) = @_;

  print "$repo_type\t$repo_url\n";
  exit(0);
}

sub is_repo($) {
  my ($arg) = @_;

  return ($arg !~ /^[a-z0-9.+-]+$/);  # lexical rule for package names
}

sub main() {
  my $print_only = 0;
  my $repo_type = "svn";  # default repo typo, overridden by '-t'
  my $repo_url = "";
  my $pkg = "";
  my $destdir = "";
  GetOptions(
      "print|p" => \$print_only,
      "type|t=s" => \$repo_type,
      "help|h" => sub { pod2usage({-exitval => 0, -verbose => 1}); })
    or pod2usage({-exitval => 3});
  pod2usage({-exitval => 3}) if ($#ARGV < 0 or $#ARGV > 1);

  $destdir = $ARGV[1] if $#ARGV > 0;
  if (is_repo($ARGV[0])) {  # repo-url passed on the command line
    $repo_url = $ARGV[0];
  } else {  # package name passed on the command line
    $pkg = $ARGV[0];
    ($repo_type, $repo_url) = find_repo($pkg);
    unless ($repo_type) {
      print <<EOF;
No repository found for package '$pkg', a Vcs-* field is missing in its source record.
If you know that the package is maintained via a Version Control System consider asking the maintainer to expose such information.
EOF
      exit(1);
    }
  }

  print_repo($repo_type, $repo_url) if $print_only;
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

