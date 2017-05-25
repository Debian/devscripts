#!/usr/bin/perl
#
# debcheckout: checkout the development repository of a Debian package
# Copyright (C) 2007-2009  Stefano Zacchiroli <zack@debian.org>
# Copyright (C) 2010  Christoph Berg <myon@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
directory; this can be overridden by providing the I<DESTDIR> argument.

The information about where the repository is available is expected to be found
in B<Vcs-*> fields available in the source package record. For example, the B<vim>
package exposes such information with a field like S<B<Vcs-Hg:
http://hg.debian.org/hg/pkg-vim/vim>>, you can see it by grepping through
B<apt-cache showsrc vim>.

If more than one source package record containing B<Vcs-*> fields is available,
B<debcheckout> will select the record with the highest version number.
Alternatively, a particular version may be selected from those available by
specifying the package name as I<PACKAGE>=I<VERSION>.

If you already know the URL of a given repository you can invoke
B<debcheckout> directly on it, but you will probably need to pass the
appropriate B<-t> flag. That is, some heuristics are in use to guess
the repository type from the URL; if they fail, you might want to
override the guessed type using B<-t>.

The currently supported version control systems are: Arch (arch), Bazaar (bzr), CVS (cvs),
Darcs (darcs), Git (git), Mercurial (hg) and Subversion (svn).

=head1 OPTIONS

B<GENERAL OPTIONS>

=over

=item B<-a>, B<--auth>

Work in authenticated mode; this means that for known repositories (mainly those
hosted on S<I<https://alioth.debian.org>>) URL rewriting is attempted before
checking out, to ensure that the repository can be committed to. For example,
for Subversion repositories hosted on alioth this means that
S<I<svn+ssh://svn.debian.org/...>> will be used instead of
S<I<svn://svn.debian.org/...>>.

There are built-in rules for alioth.debian.org and github.com. Other hosts
can be configured using B<DEBCHECKOUT_AUTH_URLS>.

=item B<-d>, B<--details>

Only print a list of detailed information about the package
repository, without checking it out; the output format is a list of
fields, each field being a pair of TAB-separated field name and field
value. The actual fields depend on the repository type. This action
might require a network connection to the remote repository.

Also see B<-p>. This option and B<-p> are mutually exclusive.

=item B<-h>, B<--help>

Print a detailed help message and exit.

=item B<-p>, B<--print>

Only print a summary about package repository information, without
checking it out; the output format is TAB-separated with two fields:
repository type, repository URL. This action works offline, it only
uses "static" information as known by APT's cache.

Also see B<-d>. This option and B<-d> are mutually exclusive.

=item B<-P> I<package>, B<--package> I<package>

When checking out a repository URL, instead of trying to guess the package name
from the URL, use this package name.

=item B<-t> I<TYPE>, B<--type> I<TYPE>

Override the repository type (which defaults to some heuristics based
on the URL or, in case of heuristic failure, the fallback "svn");
should be one of the currently supported repository types.

=item B<-u> I<USERNAME>, B<--user> I<USERNAME>

Specify the login name to be used in authenticated mode (see B<-a>). This option
implies B<-a>: you don't need to specify both.

=item B<-f> I<FILE>, B<--file> I<FILE>

Specify that the named file should be extracted from the repository and placed
in the destination directory. May be used more than once to extract multiple
files.

=item B<--source=never>|B<auto>|B<download-only>|B<always>

Some packages only place the F<debian> directory in version control.
B<debcheckout> can retrieve the remaining parts of the source using B<apt-get
source> and move the files into the checkout.

=over

=item B<never>

Only use the repository.

=item B<auto> (default)

If the repository only contains the F<debian> directory, retrieve the source
package, unpack it, and also place the F<.orig.tar.gz> file into the current
directory. Else, do nothing.

=item B<download-only>

Always retrieve the I<.orig.tar.gz> file, but do not unpack it.

=item B<always>

Always retrieve the I<.orig.tar.gz> file, and if the repository only contains the
F<debian> directory, unpack it.

=back

=back

B<VCS-SPECIFIC OPTIONS>

I<GIT-SPECIFIC OPTIONS>

=over

=item B<--git-track> I<BRANCHES>

Specify a list of remote branches which will be set up for tracking
(as in S<B<git branch --track>>, see B<git-branch>(1)) after the remote
Git repository has been cloned. The list should be given as a
space-separated list of branch names.

As a shorthand, the string "B<*>" can be given to require tracking of all
remote branches.

=back

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables. Command line options can be used to override
configuration file settings. Environment variable settings are ignored
for this purpose. The currently recognised variables are:

=over

=item B<DEBCHECKOUT_AUTH_URLS>

This variable should be a space separated list of Perl regular
expressions and replacement texts, which must come in pairs: I<REGEXP>
I<TEXT> I<REGEXP> I<TEXT> ... and so on. Each pair denotes a substitution which
is applied to repository URLs if other built-in means of building URLs
for authenticated mode (see B<-a>) have failed.

References to matching substrings in the replacement texts are
allowed as usual in Perl by the means of B<$1>, B<$2>, ... and so on.

This setting can be used to enable authenticated mode for most repositories
out there.  Note that the Debian repositories on S<alioth.debian.org>
(S<$vcs.debian.org>) are implicitly defined.

Here is a sample snippet suitable for the configuration files:

 DEBCHECKOUT_AUTH_URLS='
  ^\w+://(svn\.example\.com)/(.*)    svn+ssh://$1/srv/svn/$2
  ^\w+://(git\.example\.com)/(.*)    git+ssh://$1/home/git/$2
 '

Note that whitespace is not allowed in either regexps or
replacement texts. Also, given that configuration files are sourced by
a shell, you probably want to use single quotes around the value of
this variable.

=item B<DEBCHECKOUT_SOURCE>

This variable determines under what scenarios the associated orig.tar.gz for a
package will be downloaded.  See the B<--source> option for a description of
the values.

=item B<DEBCHECKOUT_USER>

This variable sets the username for authenticated mode. It can be overridden
with the B<--user> option. Setting this variable does not imply the use of
authenticated mode, it still has to be activated with B<--auth>.

=back

=head1 SEE ALSO

B<apt-cache>(8), Section 6.2.5 of the Debian Developer's Reference (for
more information about B<Vcs-*> fields): S<I<https://www.debian.org/doc/developers-reference/best-pkging-practices.html#bpp-vcs>>.

=head1 AUTHOR

B<debcheckout> and this manpage have been written by Stefano Zacchiroli
<I<zack@debian.org>>.

=cut

use strict;
use warnings;
no if $] >= 5.018, 'warnings', 'experimental::smartmatch';
use feature 'switch';
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use Pod::Usage;
use File::Basename;
use File::Copy qw/copy/;
use File::Temp qw/tempdir/;
use Cwd;
use Devscripts::Compression;
use Devscripts::Versort;

my @files = ();	  # files to checkout

my $compression_re = compression_get_file_extension_regex();

# <snippet from="bts.pl">
# <!-- TODO we really need to factor out in a Perl module the
#      configuration file parsing code -->
my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
my %config_vars = (
    'DEBCHECKOUT_AUTH_URLS' => '',
    'DEBCHECKOUT_SOURCE' => 'auto',
    'DEBCHECKOUT_USER' => '',
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
# </snippet>

my $lwp_broken;
my $ua;

sub have_lwp() {
    return ($lwp_broken ? 0 : 1) if defined $lwp_broken;
    eval {
	require LWP;
	require LWP::UserAgent;
    };

    if ($@) {
	if ($@ =~ m%^Can\'t locate LWP%) {
	    $lwp_broken="the libwww-perl package is not installed";
	} else {
	    $lwp_broken="couldn't load LWP::UserAgent: $@";
	}
    }
    else { $lwp_broken=''; }
    return $lwp_broken ? 0 : 1;
}

sub init_agent {
    $ua = new LWP::UserAgent;  # we create a global UserAgent object
    $ua->agent("LWP::UserAgent/Devscripts");
    $ua->env_proxy;
}

sub recurs_mkdir {
    my ($dir) = @_;
    my @temp = split /\//, $dir;
    my $createdir = "";
    foreach my $piece (@temp) {
	if (! length $createdir and ! length $piece) {
	    $createdir = "/";
	} elsif (length $createdir and $createdir ne "/") {
	    $createdir .= "/";
	}
	$createdir .= "$piece";
	if (! -d $createdir) {
	    mkdir($createdir) or return 0;
	}
    }
    return 1;
}

# Find the repository URL (and type) for a given package name, parsing Vcs-*
# fields.  Returns (version, type, url, origtgz_name) tuple.
sub find_repo($$) {
    my ($pkg, $desired_ver) = @_;
    my @repo = ("", 0, "", "");
    my $found = 0;
    my ($nonepoch_version, $version) = ("", "");
    my $origtgz_name = "";
    my $type = "";
    my $url = "";
    my @repos = ();

    open(APT, "apt-cache showsrc $pkg |");
    while (my $line = <APT>) {
	$found = 1;
	chomp($line);
	if ($line =~ /^(x-)?vcs-(\w+):\s*(.*)$/i) {
	    next if lc($2) eq "browser";
	    ($type, $url) = (lc($2), $3);
	} elsif ($line =~ /^Version:\s*(.*)$/i) {
	    $version = $1;
	    ($nonepoch_version = $version) =~ s/^\d+://;
	} elsif ($line =~ /^ [a-f0-9]{32} \d+ (\S+)(?:_\Q$nonepoch_version\E|\.orig)\.tar\.$compression_re$/) {
	    $origtgz_name = $1;
	} elsif ($line =~ /^$/) {
	    push (@repos, [$version, $type, $url, $origtgz_name])
		if ($version and $type and $url and
		    ($desired_ver eq "" or $desired_ver eq $version));
	    $version = "";
	    $type = "";
	    $url = "";
	    $origtgz_name = "";
	}
    }
    close(APT);
    die "unknown package '$pkg'\n" unless $found;

    if (@repos) {
	@repos = Devscripts::Versort::versort(@repos);
	@repo = @{$repos[0]};
    }
    return @repo;
}

# Find the browse URL for a given package name, parsing Vcs-* fields.
sub find_browse($$) {
    my ($pkg, $desired_ver) = @_;
    my $browse = "";
    my $found = 0;
    my $version = "";
    my @browses;

    open(APT, "apt-cache showsrc $pkg |");
    while (my $line = <APT>) {
	$found = 1;
	chomp($line);
	if ($line =~ /^(x-)?vcs-(\w+):\s*(.*)$/i) {
	    if (lc($2) eq "browser") {
		$browse = $3;
	    }
	} elsif ($line =~ /^Version:\s*(.*)$/i) {
	    $version = $1;
	} elsif ($line =~ /^$/) {
	    push(@browses, [$version, $browse])
		if $version and $browse and
		($desired_ver eq "" or $desired_ver eq $version);
	    $version = "";
	    $browse = "";
	}
    }
    close(APT);
    die "unknown package '$pkg'\n" unless $found;
    if (@browses) {
	@browses = Devscripts::Versort::versort(@browses);
	$browse = $browses[0][1];
    }
    return $browse;
}

# Patch the cmdline invocation of a VCS to ensure the repository is checkout to
# a given target directory.
sub set_destdir($$@) {
    my ($repo_type, $destdir, @cmd) = @_;
    $destdir =~ s|^-d\s*||;

    given ($repo_type) {
	when ("cvs") {
	    my $module = pop @cmd;
	    push @cmd, ("-d", $destdir, $module);
	}
	when (/^(bzr|darcs|git|hg|svn)$/) {
	    push @cmd, $destdir;
	}
	default {
	    die "sorry, don't know how to set the destination directory for $repo_type repositories (patches welcome!)\n";
	}
    }
    return @cmd;
}

# try patching a repository URL to enable authenticated mode, *relying
# only on user defined rules*
sub user_set_auth($$) {
    my ($repo_type, $url) = @_;
    my @rules = split ' ', $config_vars{'DEBCHECKOUT_AUTH_URLS'};
    while (my $pat = shift @rules) {	# read pairs for s/$pat/$subst/
	my $subst = shift @rules
	    or die "Configuration error for DEBCHECKOUT_AUTH_URLS: regexp and replacement texts must come in pairs. See debcheckout(1).\n";
	$url =~ s/$pat/qq("$subst")/ee;	# ZACK: my worst Perl line ever
    }
    return $url;
}

# Patch a given repository URL to ensure that the checked out out repository
# can be committed to. Only works for well known repositories (mainly Alioth's).
sub set_auth($$$$) {
    my ($repo_type, $url, $user, $dont_act) = @_;

    my $old_url = $url;

    $user .= "@" if length $user;
    my $user_local = $user;
    $user_local =~ s|(.*)(@)|$1|;
    my $user_url = $url;

    # Adjust urls from new-style anonymous access to old-style and then deal
    # with adjusting for authentication on alioth
    $url =~ s@(?:alioth\.debian\.org/(?:anonscm/bzr|scm/loggerhead/bzr)|anonscm\.debian\.org/bzr(?:/bzr)?)@bzr.debian.org/bzr@;
    $url =~ s@(?:alioth\.debian\.org/anonscm/darcs|anonscm\.debian\.org/darcs)@darcs.debian.org/darcs@;
    $url =~ s@git://anonscm\.debian\.org@git://git.debian.org@;
    $url =~ s@(?:alioth\.debian\.org/anonscm/git|anonscm\.debian\.org/git)@git.debian.org/git@;
    $url =~ s@(?:alioth\.debian\.org/anonscm/hg|anonscm\.debian\.org/hg)@hg.debian.org/hg@;
    $url =~ s@svn://(?:scm\.alioth|anonscm)\.debian\.org@svn://svn.debian.org@;

    # other providers
    $url =~ s!(?:git|https?)://github\.com/!git\@github.com:!;

    given ($repo_type) {
	when ("bzr") {
	    $url =~ s|^[\w+]+://(bzr\.debian\.org)/(.*)|bzr+ssh://$user$1/bzr/$2|;
	    $url =~ s[^\w+://(?:(bazaar|code)\.)?(launchpad\.net/.*)][bzr+ssh://${user}bazaar.$2];
	}
	when ("darcs")  {
	    if ($url =~ m|(~)|) {
		$user_url =~ s|^\w+://(darcs\.debian\.org)/(~)(.*?)/.*|$3|;
		die "the local user '$user_local' doesn't own the personal repository '$url'\n"
		    if $user_local ne $user_url and !$dont_act;
		$url =~ s|^\w+://(darcs\.debian\.org)/(~)(.*?)/(.*)|$user$1:~/public_darcs/$4|;
	    } else {
		$url =~ s|^\w+://(darcs\.debian\.org)/(?:darcs/)?(.*)|$user$1:/darcs/$2|;
	    }
	}
	when ("git") {
	    if ($url =~ m%(/users/|~)%) {
		$user_url =~ s|^\w+://(git\.debian\.org)/git/users/(.*?)/.*|$2|;
		$user_url =~ s|^\w+://(git\.debian\.org)/~(.*?)/.*|$2|;

		die "the local user '$user_local' doesn't own the personal repository '$url'\n"
		    if $user_local ne $user_url and !$dont_act;
		$url =~ s|^\w+://(git\.debian\.org)/git/users/.*?/(.*)|git+ssh://$user$1/~/public_git/$2|;
		$url =~ s|^\w+://(git\.debian\.org)/~.*?/(.*)|git+ssh://$user$1/~/public_git/$2|;
	    } else {
		$url =~ s|^\w+://(git\.debian\.org)/(?:git/)?(.*)|git+ssh://$user$1/git/$2|;
	    }
	    $url =~ s[^\w+://(?:(git|code)\.)?(launchpad\.net/.*)][git+ssh://${user}git.$2];
	}
	# "hg ssh://" needs an extra slash so paths are not based in the user's $HOME
	when ("hg") {
	    $url =~ s|^\w+://(hg\.debian\.org/)|ssh://$user$1/|;
	}
	when ("svn") {
	    $url =~ s|^\w+://(svn\.debian\.org)/(.*)|svn+ssh://$user$1/svn/$2|;
	}
	default {
	    die "sorry, don't know how to enable authentication for $repo_type repositories (patches welcome!)\n";
	}
    }
    if ($url eq $old_url) { # last attempt: try with user-defined rules
	$url = user_set_auth($repo_type, $url);
    }
    die "can't use authenticated mode on repository '$url' since it is not a known repository (e.g. alioth)\n"
	if $url eq $old_url;
    return $url;
}

# Hack around specific, known deficiencies in repositories that don't follow
# standard behavior.
sub munge_url($$)
{
    my ($repo_type, $repo_url) = @_;

    given ($repo_type) {
	when ('bzr') {
	    # bzr.d.o explicitly doesn't run a smart server.  Need to use nosmart
	    $repo_url =~ s|^http://(bzr\.debian\.org)/(.*)|nosmart+http://$1/$2|;
	}
    }
    return $repo_url;
}

# Checkout a given repository in a given destination directory.
sub checkout_repo($$$) {
    my ($repo_type, $repo_url, $destdir) = @_;
    my @cmd;

    given ($repo_type) {
	when ("arch") { @cmd = ("tla", "grab", $repo_url); }  # XXX ???
	when ("bzr") { @cmd = ("bzr", "branch", $repo_url); }
	when ("cvs") {
	    $repo_url =~ s|^-d\s*||;
	    my ($root, $module) = split /\s+/, $repo_url;
	    $module ||= '';
	    @cmd = ("cvs", "-d", $root, "checkout", $module);
	}
	when ("darcs") { @cmd = ("darcs", "get", $repo_url); }
	when ("git") {
	    if ($repo_url =~ m|(.*)\s+-b\s+(.*)|) {
	      @cmd = ("git", "clone", $1, "-b", $2);
	    } else {
	      @cmd = ("git", "clone", $repo_url);
	    }
	}
	when ("hg") { @cmd = ("hg", "clone", $repo_url); }
	when ("svn") { @cmd = ("svn", "co", $repo_url); }
	default { die "unsupported version control system '$repo_type'.\n"; }
    }
    @cmd = set_destdir($repo_type, $destdir, @cmd) if length $destdir;
    print "@cmd ...\n";
    system @cmd;
    my $rc = $? >> 8;
    return $rc;
}

# Checkout a given set of files from a given repository in a given
# destination directory.
sub checkout_files($$$$) {
    my ($repo_type, $repo_url, $destdir, $browse_url) = @_;
    my @cmd;
    my $tempdir;

    foreach my $file (@files) {
	my $fetched = 0;

	# Cheap'n'dirty escaping
	# We should possibly depend on URI::Escape, but this should do...
	my $escaped_file = $file;
	$escaped_file =~ s|\+|%2B|g;

	my $dir;
	if (defined $destdir and length $destdir) {
	    $dir = "$destdir/";
	} else {
	    $dir = "./";
	}
	$dir .= dirname($file);

	if (! recurs_mkdir($dir)) {
	    print STDERR "Failed to create directory $dir\n";
	    return 1;
	}

	given ($repo_type) {
	    when ("arch") {
		# If we've already retrieved a copy of the repository,
		# reuse it
		if (!length($tempdir)) {
		    if (!($tempdir = tempdir( "debcheckoutXXXX", TMPDIR => 1, CLEANUP => 1 ))) {
			print STDERR
			    "Failed to create temporary directory . $!\n";
			return 1;
		    }

		    my $oldcwd = getcwd();
		    chdir $tempdir;
		    @cmd = ("tla", "grab", $repo_url);
		    print "@cmd ...\n";
		    my $rc = system(@cmd);
		    chdir $oldcwd;
		    return ($rc >> 8) if $rc != 0;
		}

		if (!copy("$tempdir/$file", $dir)) {
		    print STDERR "Failed to copy $file to $dir: $!\n";
		    return 1;
		}
	    }
	    when ("cvs") {
		if (!length($tempdir)) {
		    if (!($tempdir = tempdir( "debcheckoutXXXX", TMPDIR => 1, CLEANUP => 1 ))) {
			print STDERR
			    "Failed to create temporary directory . $!\n";
			return 1;
		    }
		}
		$repo_url =~ s|^-d\s*||;
		my ($root, $module) = split /\s+/, $repo_url;
		# If an explicit module name isn't present, use the last
		# component of the URL
		if (!length($module)) {
		    $module = $repo_url;
		    $module =~ s%^.*/(.*?)$%$1%;
		}
		$module .= "/$file";
		$module =~ s%//%/%g;

		my $oldcwd = getcwd();
		chdir $tempdir;
		@cmd = ("cvs", "-d", $root, "export", "-r", "HEAD", "-f",
			$module);
		print "\n@cmd ...\n";
		system @cmd;
		if (($? >> 8) != 0) {
		    chdir $oldcwd;
		    return ($? >> 8);
		} else {
		    chdir $oldcwd;
		    if (copy("$tempdir/$module", $dir)) {
			print "Copied to $destdir/$file\n";
		    } else {
			print STDERR "Failed to copy $file to $dir: $!\n";
			return 1;
		    }
		}
	    }
	    when (/(svn|bzr)/) {
		@cmd = ($repo_type, "cat", "$repo_url/$file");
		print "@cmd > $dir/" . basename($file) . " ... \n";
		if (! open CAT, '-|', @cmd) {
		    print STDERR "Failed to execute @cmd $!\n";
		    return 1;
		}
		local $/;
		my $content = <CAT>;
		close CAT;
		if (! open OUTPUT, ">", $dir . "/" . basename($file)) {
		    print STDERR "Failed to create output file "
			. basename($file) ." $!\n";
		    return 1;
		}
		print OUTPUT $content;
		close OUTPUT;
	    }
	    when (/(darcs|hg)/) {
		# Subtly different but close enough
		if (have_lwp) {
		    print "Attempting to retrieve $file via HTTP ...\n";

		    my $file_url = $repo_type eq "darcs"
			? "$repo_url/$escaped_file"
			: "$repo_url/raw-file/tip/$file";
		    init_agent() unless $ua;
		    my $request = HTTP::Request->new('GET', "$file_url");
		    my $response = $ua->request($request);
		    if ($response->is_success) {
			if (! open OUTPUT, ">", $dir . "/" . basename($file)) {
			    print STDERR "Failed to create output file "
				. basename($file) . " $!\n";
			    return 1;
			}
			print "Writing to $dir/" . basename($file) . " ... \n";
			print OUTPUT $response->content;
			close OUTPUT;
			$fetched = 1;
		    }
		}
		if ($fetched == 0) {
		    # If we've already retrieved a copy of the repository,
		    # reuse it
		    if (!length($tempdir)) {
			if (!($tempdir = tempdir( "debcheckoutXXXX", TMPDIR => 1, CLEANUP => 1 ))) {
			    print STDERR
				"Failed to create temporary directory . $!\n";
			    return 1;
			}

			# Can't get / clone in to a directory that already exists...
			$tempdir .= "/repo";
			if ($repo_type eq "darcs") {
			    @cmd = ("darcs", "get", $repo_url, $tempdir);
			} else {
			    @cmd = ("hg", "clone", $repo_url, $tempdir);
			}
			print "@cmd ...\n";
			my $rc = system(@cmd);
			return ($rc >> 8) if $rc != 0;
			print "\n";
		    }
		}
		if (copy "$tempdir/$file", $dir) {
		    print "Copied $file to $dir\n";
		} else {
		    print STDERR "Failed to copy $file to $dir: $!\n";
		    return 1;
		}
	    }
	    when ("git") {
		# If there isn't a browse URL (either because the package
		# doesn't ship one, or because we were called with a URL,
		# try a common pattern for gitweb
		if (!length($browse_url)) {
		    if ($repo_url =~ m%^\w+://([^/]+)/(?:git/)?(.*)$%) {
			$browse_url = "http://$1/?p=$2";
		    }
		}
		if (have_lwp and $browse_url =~ /^http/) {
		    $escaped_file =~ s|/|%2F|g;

		    print "Attempting to retrieve $file via HTTP ...\n";

		    init_agent() unless $ua;
		    my $file_url = "$browse_url;a=blob_plain";
		    $file_url .= ";f=$escaped_file;hb=HEAD";
		    my $request = HTTP::Request->new('GET', $file_url);
		    my $response = $ua->request($request);
		    my $error = 0;
		    if (!$response->is_success) {
			if ($browse_url =~ /\.git$/) {
			    print "Error retrieving file: "
				. $response->status_line . "\n";
			    $error = 1;
			} else {
			    $browse_url .= ".git";
			    $file_url = "$browse_url;a=blob_plain";
			    $file_url .= ";f=$escaped_file;hb=HEAD";
			    $request = HTTP::Request->new('GET', $file_url);
			    $response = $ua->request($request);
			    if (!$response->is_success) {
				print "Error retrieving file: "
				    . $response->status_line . "\n";
				$error = 1;
			    }
			}
		    }
		    if (!$error) {
			if (! open OUTPUT, ">", $dir . "/" . basename($file)) {
			    print STDERR "Failed to create output file "
				. basename($file) . " $!\n";
			    return 1;
			}
			print "Writing to $dir/" . basename($file) . " ... \n";
			print OUTPUT $response->content;
			close OUTPUT;
			$fetched = 1;
		    }
		}
		if ($fetched == 0) {
		    # If we've already retrieved a copy of the repository,
		    # reuse it
		    if (!length($tempdir)) {
			if (!($tempdir = tempdir( "debcheckoutXXXX", TMPDIR => 1, CLEANUP => 1 ))) {
			    print STDERR
				"Failed to create temporary directory . $!\n";
			    return 1;
			}
			# Since git won't clone in to a directory that
			# already exists...
			$tempdir .= "/repo";
			# Can't shallow clone from an http:: URL
			$repo_url =~ s/^http/git/;
			@cmd = ("git", "clone", "--depth", "1", $repo_url,
				"$tempdir");
			print "@cmd ...\n\n";
			my $rc = system(@cmd);
			return ($rc >> 8) if $rc != 0;
			print "\n";
		    }

		    my $oldcwd = getcwd();
		    chdir $tempdir;

		    @cmd = ($repo_type, "show", "HEAD:$file");
		    print "@cmd ... > $dir/" . basename($file) . "\n";
		    if (! open CAT, '-|', @cmd) {
			print STDERR "Failed to execute @cmd $!\n";
			chdir $oldcwd;
			return 1;
		    }
		    chdir $oldcwd;
		    local $/;
		    my $content = <CAT>;
		    close CAT;
		    if (! open OUTPUT, ">", $dir . "/" . basename($file)) {
			print STDERR "Failed to create output file "
			    . basename($file) ." $!\n";
			return 1;
		    }
		    print OUTPUT $content;
		    close OUTPUT;
		}
	    }
	    default {
		die "unsupported version control system '$repo_type'.\n";
	    }
	}
    }

    # If we've got this far, all the files were retrieved successfully
    return 0;
}

# download source package, unpack it, and merge its contents into the checkout
sub unpack_source($$$$$) {
    my ($pkg, $version, $destdir, $origtgz_name, $unpack_source) = @_;

    return 1 if ($unpack_source eq 'never');
    return 1 if (defined $origtgz_name and $origtgz_name eq ''); # only really relevant with URL on command line

    $destdir ||= $pkg;
    # Apt will auto-resolve binary package names to source package names.  We
    # need to know the source package name to correctly identify the source
    # package artifacts (dsc, orig.tar.*, etc)
    (my $srcpkg = $origtgz_name) =~ s/_.*//;
    # is this a debian-dir-only repository?
    unless (-d $destdir) {
	print STDERR "debcheckout did not create the $destdir directory - this is probably a bug\n";
	return 0;
    }
    my @repo_files = glob "$destdir/*";
    my $debian_only = 0;
    if (@repo_files == 1 and $repo_files[0] eq "$destdir/debian") {
	$debian_only = 1;
    }

    return 1 if ($unpack_source eq 'auto' and not $debian_only);
    if ($unpack_source ne 'download-only' and $debian_only) {
	print "repository only contains the debian directory, using apt-get source\n";
    }

    my $tmpdir = File::Temp->newdir(DIR => ".");

    # unpack
    my $oldcwd = getcwd();
    chdir $tmpdir;
    my @args = ('source');
    push @args, '--download-only' if ($unpack_source eq 'download-only' or not $debian_only);
    push @args, $version ? "$srcpkg=$version" : $srcpkg;
    system('apt-get', @args);
    chdir $oldcwd;
    if ($? >> 8) {
	print STDERR "apt-get source failed\n";
	return 0;
    }

    # put source package in place
    foreach my $sourcefile (glob "$tmpdir/${srcpkg}_*") {
	next unless (-f $sourcefile); # skip directories
	my $base = $sourcefile;
	$base =~ s!.*/!!;
	rename $sourcefile, $base or die "rename $sourcefile $base: $!";
    }

    return 1 if ($unpack_source eq 'download-only' or not $debian_only);

    # figure out which directory was created
    my @dirs = glob "$tmpdir/$srcpkg-*/";
    unless (@dirs) {
	print STDERR "apt-get source did not create any $tmpdir/$srcpkg-* directory\n";
	return 0;
    }
    my $directory = $dirs[0];
    chop $directory;

    # move all files over, except the debian directory
    opendir DIR, $directory or die "opendir $directory: $!";
    foreach my $file (readdir DIR) {
	if ($file eq 'debian') {
	    system ('rm', '-rf', "$directory/$file");
	} elsif ($file eq '.' or $file eq '..') {
	    next;
	} else {
	    rename "$directory/$file", "$destdir/$file" or
		die "rename $directory/$file $destdir/$file: $!";
	}
    }
    closedir DIR;
    rmdir $directory or die "rmdir $directory: $!";

    # $tmpdir is automatically removed
    return 1;
}

# Print information about a repository and quit.
sub print_repo($$) {
    my ($repo_type, $repo_url) = @_;

    print "$repo_type\t$repo_url\n";
    exit(0);
}

sub git_ls_remote($$) {
    my ($url, $prefix) = @_;

    $url =~ s|\s+-b\s+.*||;
    my $cmd = "git ls-remote '$url'";
    $cmd .= " '$prefix/*'" if length $prefix;
    open GIT, "$cmd |" or die "can't execute $cmd\n";
    my @refs;
    while (my $line = <GIT>) {
	chomp $line;
	my ($sha1, $name) = split /\s+/, $line;
	my $ref = $name;
	$ref = substr($ref, length($prefix) + 1) if length $prefix;
	push @refs, $ref;
    }
    close GIT;
    return @refs;
}

# Given a GIT repository URL, extract its topgit info (if any), see
# the "topgit" package for more information
sub tg_info($) {
    my ($url) = @_;

    my %info;
    $info{'topgit'} = 'no';
    $info{'top-bases'} = '';
    my @bases = git_ls_remote($url, 'refs/top-bases');
    if (@bases) {
	$info{'topgit'} = 'yes';
	$info{'top-bases'} = join ' ', @bases;
    }
    return(\%info);
}

# Print details about a repository and quit.
sub print_details($$) {
    my ($repo_type, $repo_url) = @_;

    print "type\t$repo_type\n";
    print "url\t$repo_url\n";
    if ($repo_type eq "git") {
	my $tg_info = tg_info($repo_url);
	while (my ($k, $v) = each %$tg_info) {
	    print "$k\t$v\n";
	}
    }
    exit(0);
}

sub guess_repo_type($$) {
    my ($repo_url, $default) = @_;
    my $repo_type = $default;
    if ($repo_url =~ /^(git|svn|bzr)(\+ssh)?:/) {
	$repo_type = $1;
    } elsif ($repo_url =~ /^https?:\/\/(svn|git|hg|bzr|darcs)\.debian\.org/) {
	$repo_type = $1;
    } elsif ($repo_url =~ m@^https?://anonscm.debian.org/(svn|git|hg|bzr|darcs)/@) {
	$repo_type = $1;
    }
    return $repo_type;
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
    my $version = "";       # package version
    my $origtgz_name = undef; # orig.tar.gz name (or "" when none; undef means unknown)
    my $print_mode = 0;	  # print only mode
    my $details_mode = 0;	  # details only mode
    my $use_package = ''; # use this package instead of guessing from the URL
    my $repo_type = "svn";  # default repo typo, overridden by '-t'
    my $repo_url = "";	  # repository URL
    my $user = "";	  # login name (authenticated mode only)
    my $browse_url = "";    # online browsable repository URL
    my $git_track = "";     # list of remote GIT branches to --track
    my $unpack_source = $config_vars{DEBCHECKOUT_SOURCE}; # retrieve and unpack orig.tar.gz
    GetOptions(
	"auth|a" => \$auth,
	"help|h" => sub { pod2usage({-exitval => 0, -verbose => 1}); },
	"print|p" => \$print_mode,
	"details|d" => \$details_mode,
	"package|P=s" => \$use_package,
	"type|t=s" => \$repo_type,
	"user|u=s" => \$user,
	"file|f=s" => sub { push(@files, $_[1]); },
	"git-track=s" => \$git_track,
	"source=s" => \$unpack_source,
	) or pod2usage({-exitval => 3});
    pod2usage({-exitval => 3}) if ($#ARGV < 0 or $#ARGV > 1);
    pod2usage({-exitval => 3,
	       -message =>
		   "-d and -p are mutually exclusive.\n", })
	if ($print_mode and $details_mode);
    my $dont_act = 1 if ($print_mode or $details_mode);
    pod2usage({-exitval => 3,
	       -message =>
		   "--source argument must be one of never, auto, download-only, and always\n", })
	unless ($unpack_source =~ /^(never|auto|download-only|always)$/);

    # -u|--user implies -a|--auth
    $auth = 1 if length $user;

    # set user from the config file to be used with -a|--auth without -u|--user
    $user = $config_vars{DEBCHECKOUT_USER} unless $user;

    $destdir = $ARGV[1] if $#ARGV > 0;
    ($pkg, $version) = split(/=/, $ARGV[0]);
    $version ||= "";

    if (not is_package($pkg)) {  # repo-url passed on the command line
	$repo_url = $ARGV[0];
	$repo_type = guess_repo_type($repo_url, $repo_type);
	$pkg = ""; $version = "";
	# when --package is given, use it
	if ($use_package) {
	    $pkg = $use_package;
	# else guess package from url
	} elsif ($repo_url =~ m!/trunk/([a-z0-9.+-]+)!) { # svn with {trunk,tags,branches}/$pkg
	    $pkg = $1;
	} elsif ($repo_url =~ m!([a-z0-9.+-]+)/trunk/?!) { # svn with $pkg/{trunk,tags,branches}
	    $pkg = $1;
	} elsif ($repo_url =~ /([a-z0-9.+-]+)\.git(\s+-b\s+.*)?$/) { # git
	    $pkg = $1;
	} elsif ($repo_url =~ /([a-z0-9.+-]+)$/) { # catch-all
	    $pkg = $1;
	}
	$origtgz_name = $pkg; # FIXME: this should rather set srcpkg in unpack_source() directly
    } else {  # package name passed on the command line
	($version, $repo_type, $repo_url, $origtgz_name) = find_repo($pkg, $version);
	unless ($repo_type) {
	    my $vermsg = "";
	    $vermsg = ", version $version" if length $version;
	    print <<EOF;
No repository found for package $pkg$vermsg.

A Vcs-* field is missing in its source record. See Debian Developer's
Reference 6.2.5:
 `https://www.debian.org/doc/developers-reference/best-pkging-practices.html#bpp-vcs'
If you know that the package is maintained via a version control
system consider asking the maintainer to expose such information.

Nevertheless, you can get the sources of package $pkg
from the Debian archive executing:

 apt-get source $pkg

Note however that what you obtain will *not* be a local copy of
some version control system: your changes will not be preserved
and it will not be possible to commit them directly.

EOF
            exit(1);
	}
	$browse_url = find_browse($pkg, $version) if @files;
    }

    $repo_url = munge_url($repo_type, $repo_url);
    $repo_url = set_auth($repo_type, $repo_url, $user, $dont_act)
	if $auth and not @files;
    print_repo($repo_type, $repo_url) if $print_mode;		# ... then quit
    print_details($repo_type, $repo_url) if $details_mode;	# ... then quit
    if (length $pkg) {
	print "declared $repo_type repository at $repo_url\n";
	$destdir = $pkg unless length $destdir;
    }
    my $rc;
    if (@files) {
	$rc = checkout_files($repo_type, $repo_url, $destdir, $browse_url);
    } else {
	$rc = checkout_repo($repo_type, $repo_url, $destdir);
    }   # XXX: there is no way to know for sure what is the destdir :-(
    die "checkout failed (the command above returned a non-zero exit code)\n"
	if $rc != 0;

    # post-checkout actions
    if ($repo_type eq 'bzr' and $auth) {
	if (open B, '>>', "$destdir/.bzr/branch/branch.conf") {
	    print B "\npush_location = $repo_url";
	    close B;
	} else {
	    print STDERR
		"failed to open branch.conf to add push_location: $!\n";
	}
    } elsif ($repo_type eq 'git') {
	my $tg_info = tg_info($repo_url);
	my $wcdir = $destdir;
	# HACK: if $destdir is unknown, take last URL part and remove /.git$/
	$wcdir = (split m|\.|, (split m|/|, $repo_url)[-1])[0]
	    unless length $wcdir;
	if ($$tg_info{'topgit'} eq 'yes') {
	    print "TopGit detected, populating top-bases ...\n";
	    system("cd $wcdir && tg remote --populate origin");
	    $rc = $? >> 8;
	    print STDERR "TopGit population failed\n" if $rc != 0;
	}
	system("cd $wcdir && git config user.name \"$ENV{'DEBFULLNAME'}\"")
	    if (defined($ENV{'DEBFULLNAME'}));
	system("cd $wcdir && git config user.email \"$ENV{'DEBEMAIL'}\"")
	    if (defined($ENV{'DEBEMAIL'}));
	if (length $git_track) {
	    my @heads;
	    if ($git_track eq '*') {
		@heads = git_ls_remote($repo_url, 'refs/heads');
	    } else {
		@heads = split ' ', $git_track;
	    }
	    # Filter out any branches already populated via TopGit
	    my @tgheads = split ' ', $$tg_info{'top-bases'};
	    my $master = 'master';
	    if (open(HEAD, "env GIT_DIR=\"$wcdir/.git\" git symbolic-ref HEAD |")) {
		$master = <HEAD>;
		chomp $master;
		$master =~ s@refs/heads/@@;
	    }
	    close(HEAD);
	    foreach my $head (@heads) {
		next if $head eq $master;
		next if grep { $head eq $_ } @tgheads;
		my $cmd = "cd $wcdir";
		$cmd .= " && git branch --track $head remotes/origin/$head";
		system($cmd);
	    }
	}
    } elsif ($repo_type eq 'hg') {
	my $username = '';
	$username .= " $ENV{'DEBFULLNAME'}" if (defined($ENV{'DEBFULLNAME'}));
	$username .= " <$ENV{'DEBEMAIL'}>" if (defined($ENV{'DEBEMAIL'}));
	if ($username) {
	    if (open(HGRC, '>>', "$destdir/.hg/hgrc")) {
		print HGRC "[ui]\nusername =$username\n";
		close HGRC;
	    } else {
		print STDERR
		    "failed to open hgrc to set username: $!\n";
	    }
	}
    }
    die "post-checkout action failed\n"
	if $rc != 0;

    if ($unpack_source) {
	unless ($pkg) {
	    print STDERR "could not determine package name for orig.tar.gz retrieval\n";
	    $rc ||= 1;
	    exit($rc);
	}
	unpack_source($pkg, $version, $destdir, $origtgz_name, $unpack_source) or $rc = 1;
    }

    exit($rc);
}

main();

# vim:sw=4
