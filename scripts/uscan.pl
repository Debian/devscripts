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

my $CURRENT_WATCHFILE_VERSION = 3;

my $progname = basename($0);
my $modified_conf_msg;
my $opwd = cwd();

my $haveSSL = 1;
eval { require LWP::Protocol::https; };
if ($@) {
    $haveSSL = 0;
}
my $havegpgv = (-x '/usr/bin/gpgv');
my $havegpg = first { -x $_ } qw(/usr/bin/gpg2 /usr/bin/gpg);

# Did we find any new upstream versions on our wanderings?
our $found = 0;

sub process_watchline ($$$$$$);
sub process_watchfile ($$$$);
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
my $opt_download_version;
my $opt_user_agent;
my $opt_download_current_version;

GetOptions("help" => \$opt_h,
	   "version" => \$opt_v,
	   "destdir=s" => \$opt_destdir,
	   "download!" => \$opt_download,
	   "download-version=s" => \$opt_download_version,
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
if (defined $opt_repack_compression) {
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
    if (exists $opt2comp{$opt_repack_compression}) {
	$repack_compression = $opt2comp{$opt_repack_compression};
    } else {
        uscan_die "$progname: invalid compression $opt_repack_compression given.\n";
    }
}
$dehs = $opt_dehs if defined $opt_dehs;
$exclusion = $opt_exclusion if defined $opt_exclusion;
$copyright_file = $opt_copyright_file if defined $opt_copyright_file;
$user_agent_string = $opt_user_agent if defined $opt_user_agent;
$download_version = $opt_download_version if defined $opt_download_version;

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

# Was there a --uversion option?
if (defined $opt_uversion) {
    if (@debdirs == 1) {
	$debdirs[0][3] = $opt_uversion;
    } else {
	uscan_warn "$progname warning: ignoring --uversion as more than one debian/watch file found\n";
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
# watch_version=3:
#
# Correct handling of regex special characters in the path part:
# ftp://ftp.worldforge.org/pub/worldforge/libs/Atlas-C++/transitional/Atlas-C\+\+-(.+)\.tar\.gz
#
# Directory pattern matching:
# ftp://ftp.nessus.org/pub/nessus/nessus-([\d\.]+)/src/nessus-core-([\d\.]+)\.tar\.gz
#
# The pattern in each part may contain several (...) groups and
# the version number is determined by joining all groups together
# using "." as separator.  For example:
#   ftp://site/dir/path/pattern-(\d+)_(\d+)_(\d+)\.tar\.gz
#
# This is another way of handling site with funny version numbers,
# this time using mangling.  (Note that multiple groups will be
# concatenated before mangling is performed, and that mangling will
# only be performed on the basename version number, not any path version
# numbers.)
# opts=uversionmangle=s/^/0.0./ \
#   ftp://ftp.ibiblio.org/pub/Linux/ALPHA/wine/development/Wine-(.+)\.tar\.gz
#
# Similarly, the upstream part of the Debian version number can be
# mangled:
# opts=dversionmangle=s/\.dfsg\.\d+$// \
#   http://some.site.org/some/path/foobar-(.+)\.tar\.gz
#
# The versionmangle=... option is a shorthand for saying uversionmangle=...
# and dversionmangle=... and applies to both upstream and Debian versions.
#
# The option filenamemangle can be used to mangle the name under which
# the downloaded file will be saved:
#   href="http://foo.bar.org/download/?path=&amp;download=foo-0.1.1.tar.gz"
# could be handled as:
# opts=filenamemangle=s/.*=(.*)/$1/ \
#     http://foo.bar.org/download/\?path=&amp;download=foo-(.+)\.tar\.gz
# and
#   href="http://foo.bar.org/download/?path=&amp;download_version=0.1.1"
# as:
# opts=filenamemangle=s/.*=(.*)/foo-$1\.tar\.gz/ \
#    http://foo.bar.org/download/\?path=&amp;download_version=(.+)
#
# The option downloadurlmangle can be used to mangle the URL of the file
# to download.  This can only be used with http:// URLs.  This may be
# necessary if the link given on the webpage needs to be transformed in
# some way into one which will work automatically, for example:
# opts=downloadurlmangle=s/prdownload/download/ \
#   http://developer.berlios.de/project/showfiles.php?group_id=2051 \
#   http://prdownload.berlios.de/softdevice/vdr-softdevice-(.+).tgz


sub process_watchline ($$$$$$)
{
    my ($line, $watch_version, $pkg_dir, $pkg, $pkg_version, $watchfile) = @_;

    my $origline = $line;
    my ($base, $site, $dir, $filepattern, $pattern, $lastversion, $action);
    my $basedir;
    my (@patterns, @sites, @redirections, @basedirs);
    my %options = ();

    my ($request, $response);
    my ($newfile, $newversion);
    my $style='new';
    my $urlbase;
    my $headers = HTTP::Headers->new;
    my ($keyring, $gpghome);

    # Need to clear remembered redirection URLs so we don't try to build URLs
    # from previous watch files or watch lines
    $user_agent->clear_redirections;

    # Comma-separated list of features that sites being queried might
    # want to be aware of
    $headers->header('X-uscan-features' => 'enhanced-matching');
    $headers->header('Accept' => '*/*');
    %dehs_tags = ('package' => $pkg);

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
    } else {
	# version 2/3 watchfile
	if ($line =~ s/^opt(?:ion)?s=//) {
	    my $opts;
	    if ($line =~ s/^"(.*?)"\s+//) {
		$opts=$1;
	    } elsif ($line =~ s/^(\S+)\s+//) {
		$opts=$1;
	    } else {
		uscan_warn "$progname warning: malformed opts=... in watchfile, skipping line:\n$origline\n";
		return 1;
	    }

	    my @opts = split /,/, $opts;
	    foreach my $opt (@opts) {
		if ($opt eq 'pasv' or $opt eq 'passive') {
		    $options{'pasv'}=1;
		}
		elsif ($opt eq 'active' or $opt eq 'nopasv'
		       or $opt eq 'nopassive') {
		    $options{'pasv'}=0;
		}
		elsif ($opt =~ /^repacksuffix\s*=\s*(.+)/) {
		    $options{'repacksuffix'} = $1;
		}
		elsif ($opt =~ /^uversionmangle\s*=\s*(.+)/) {
		    @{$options{'uversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^dversionmangle\s*=\s*(.+)/) {
		    @{$options{'dversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^versionmangle\s*=\s*(.+)/) {
		    @{$options{'uversionmangle'}} = split /;/, $1;
		    @{$options{'dversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^filenamemangle\s*=\s*(.+)/) {
		    @{$options{'filenamemangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^downloadurlmangle\s*=\s*(.+)/) {
		    @{$options{'downloadurlmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^pgpsigurlmangle\s*=\s*(.+)/) {
		    @{$options{'pgpsigurlmangle'}} = split /;/, $1;
		}
		else {
		    uscan_warn "$progname warning: unrecognised option $opt\n";
		}
	    }
	}

	($base, $filepattern, $lastversion, $action) = split ' ', $line, 4;

	if ($base =~ s%/([^/]*\([^/]*\)[^/]*)$%/%) {
	    # Last component of $base has a pair of parentheses, so no
	    # separate filepattern field; we remove the filepattern from the
	    # end of $base and rescan the rest of the line
	    $filepattern = $1;
	    (undef, $lastversion, $action) = split ' ', $line, 3;
	}

	if ((!$lastversion or $lastversion eq 'debian') and not defined $pkg_version) {
	    uscan_warn "$progname warning: Unable to determine current version\n  in $watchfile, skipping:\n  $line\n";
	    return 1;
	}

	# Check all's OK
	if (not $filepattern or $filepattern !~ /\(.*\)/) {
	    uscan_warn "$progname warning: Filename pattern missing version delimiters ()\n  in $watchfile, skipping:\n  $line\n";
	    return 1;
	}

	# Check validity of options
	if ($base =~ /^ftp:/ and exists $options{'downloadurlmangle'}) {
	    uscan_warn "$progname warning: downloadurlmangle option invalid for ftp sites,\n  ignoring in $watchfile:\n  $line\n";
	}

	# Check validity of options
	if (($download || $force_download) && exists $options{'pgpsigurlmangle'}) {
	    if (! $havegpgv) {
		uscan_warn "$progname warning: pgpsigurlmangle option exists, but you must have gpgv installed to verify\n  in $watchfile, skipping:\n  $line\n";
		return 1;
	    }
	    $keyring = first { -r $_ } qw(debian/upstream/signing-key.pgp debian/upstream/signing-key.asc debian/upstream-signing-key.pgp);
	    if (!defined $keyring) {
		uscan_warn "$progname warning: pgpsigurlmangle option exists, but the upstream keyring does not exist\n  in $watchfile, skipping:\n  $line\n";
		return 1;
	    }
	    if ($keyring =~ m/\.asc$/) {
		if (!$havegpg) {
		    uscan_warn "$progname warning: $keyring is armored but gpg/gpg2 is not available to dearmor it\n  in $watchfile, skipping:\n $line\n";
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

	# Handle sf.net addresses specially
	if ($base =~ m%^http://sf\.net/%) {
	    $base =~ s%^http://sf\.net/%https://qa.debian.org/watch/sf.php/%;
	    $filepattern .= '(?:\?.*)?';
	}
	# Handle pypi.python.org addresses specially
	$base =~ s%^https?://pypi\.python\.org/packages/source/./%https://pypi.debian.net/%;

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

    if (! $lastversion or $lastversion eq 'debian') {
	if (defined $pkg_version) {
	    $lastversion=$pkg_version;
	} else {
	    uscan_warn "$progname warning: Unable to determine current version\n  in $watchfile, skipping:\n  $line\n";
	    return 1;
	}
    }
    # And mangle it if requested
    my $mangled_lastversion;
    $mangled_lastversion = $lastversion;
    foreach my $pat (@{$options{'dversionmangle'}}) {
	if (! safe_replace(\$mangled_lastversion, $pat)) {
	    uscan_warn "$progname: In $watchfile, potentially"
	      . " unsafe or malformed dversionmangle"
	      . " pattern:\n  '$pat'"
	      . " found. Skipping watchline\n"
	      . "  $line\n";
	    return 1;
	}
    }
    if($opt_download_current_version) {
	$download_version = $mangled_lastversion;
	$force_download = 1;
    }

    # Check all's OK
    if ($pattern !~ /\(.*\)/) {
	uscan_warn "$progname warning: Filename pattern missing version delimiters ()\n  in $watchfile, skipping:\n  $line\n";
	return 1;
    }

    push @patterns, $pattern;
    push @sites, $site;
    push @basedirs, $basedir;

    # What is the most recent file, based on the filenames?
    # We first have to find the candidates, then we sort them using
    # Devscripts::Versort::upstream_versort
    if ($site =~ m%^http(s)?://%) {
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

	print STDERR "$progname debug: redirections: @redirections\n"
	    if $debug;

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
	print STDERR "$progname debug: received content:\n$content\[End of received content]\n"
	    if $debug;

	if ($content =~ m%^<[?]xml%i &&
	    $content =~ m%xmlns="http://s3.amazonaws.com/doc/2006-03-01/"%) {
	    # this is an S3 bucket listing.  Insert an 'a href' tag
	    # into the content for each 'Key', so that it looks like html (LP: #798293)
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

	print STDERR "$progname debug: matching pattern(s) @patterns\n" if $debug;
	my @hrefs;
	while ($content =~ m/<\s*a\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/sgi) {
	    my $href = $2;
	    $href =~ s/\n//g;
	    foreach my $_pattern (@patterns) {
		if ($href =~ m&^$_pattern$&) {
		    if ($watch_version == 2) {
			# watch_version 2 only recognised one group; the code
			# below will break version 2 watchfiles with a construction
			# such as file-([\d\.]+(-\d+)?) (bug #327258)
			push @hrefs, [$1, $href];
		    } else {
			# need the map { ... } here to handle cases of (...)?
			# which may match but then return undef values
			my $mangled_version =
			    join(".", map { $_ if defined($_) }
			 	$href =~ m&^$_pattern$&);
			foreach my $pat (@{$options{'uversionmangle'}}) {
			    if (! safe_replace(\$mangled_version, $pat)) {
				uscan_warn "$progname: In $watchfile, potentially"
			 	 . " unsafe or malformed uversionmangle"
				  . " pattern:\n  '$pat'"
				  . " found. Skipping watchline\n"
				  . "  $line\n";
				return 1;
			    }
			}
			push @hrefs, [$mangled_version, $href];
		    }
		}
	    }
	}
	if (@hrefs) {
	    if ($verbose) {
		print "-- Found the following matching hrefs:\n";
		foreach my $href (@hrefs) { print "     $$href[1] ($$href[0])\n"; }
	    }
	    if (defined $download_version) {
		my @vhrefs = grep { $$_[0] eq $download_version } @hrefs;
		if (@vhrefs) {
		    ($newversion, $newfile) = @{$vhrefs[0]};
		} else {
		    uscan_warn "$progname warning: In $watchfile no matching hrefs for version $download_version"
			. " in watch line\n  $line\n";
		    return 1;
		}
	    } else {
		@hrefs = Devscripts::Versort::upstream_versort(@hrefs);
		($newversion, $newfile) = @{$hrefs[0]};
	    }
	} else {
	    uscan_warn "$progname warning: In $watchfile,\n  no matching hrefs for watch line\n  $line\n";
	    return 1;
	}
    }
    else {
	# Better be an FTP site
	if ($site !~ m%^ftp://%) {
	    uscan_warn "$progname warning: Unknown protocol in $watchfile, skipping:\n  $site\n";
	    return 1;
	}

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
	print STDERR "$progname debug: received content:\n$content\[End of received content]\n"
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
		    if (! safe_replace(\$mangled_version, $pat)) {
			uscan_warn "$progname: In $watchfile, potentially"
			  . " unsafe or malformed uversionmangle"
			  . " pattern:\n  '$pat'"
			  . " found. Skipping watchline\n"
			  . "  $line\n";
			return 1;
		    }
		}
		push @files, [$mangled_version, $file];
	    }
	} else {
	    # they all look like:
	    # info info ... info filename [ -> linkname]
	    for my $ln (split(/\n/, $content)) {
		if ($ln =~ m/\s($filepattern)(\s+->\s+\S+)?$/) {
		    my $file = $1;
		    my $mangled_version = join(".", $file =~ m/^$filepattern$/);
		    foreach my $pat (@{$options{'uversionmangle'}}) {
			if (! safe_replace(\$mangled_version, $pat)) {
			    uscan_warn "$progname: In $watchfile, potentially"
			      . " unsafe or malformed uversionmangle"
			      . " pattern:\n  '$pat'"
			      . " found. Skipping watchline\n"
			      . "  $line\n";
			    return 1;
			}
		    }
		    push @files, [$mangled_version, $file];
		}
	    }
	}

	if (@files) {
	    if ($verbose) {
		print "-- Found the following matching files:\n";
		foreach my $file (@files) { print "     $$file[1] ($$file[0])\n"; }
	    }
	    if (defined $download_version) {
		my @vfiles = grep { $$_[0] eq $download_version } @files;
		if (@vfiles) {
		    ($newversion, $newfile) = @{$vfiles[0]};
		} else {
		    uscan_warn "$progname warning: In $watchfile no matching files for version $download_version"
			. " in watch line\n  $line\n";
		    return 1;
		}
	    } else {
		@files = Devscripts::Versort::upstream_versort(@files);
		($newversion, $newfile) = @{$files[0]};
	    }
	} else {
	    uscan_warn "$progname warning: In $watchfile no matching files for watch line\n  $line\n";
	    return 1;
	}
    }

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

    my $newfile_base=basename($newfile);
    if (exists $options{'filenamemangle'}) {
        $newfile_base=$newfile;
    }
    foreach my $pat (@{$options{'filenamemangle'}}) {
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

    if (exists $options{'pgpsigurlmangle'}) {
	$pgpsig_url = $upstream_url;
	foreach my $pat (@{$options{'pgpsigurlmangle'}}) {
	    if (! safe_replace(\$pgpsig_url, $pat)) {
		uscan_warn "$progname: In $watchfile, potentially"
		  . " unsafe or malformed pgpsigurlmangle"
		  . " pattern:\n  '$pat'"
		  . " found. Skipping watchline\n"
		  . "  $line\n";
		return 1;
	    }
	}
    }

    $dehs_tags{'debian-uversion'} = $lastversion;
    $dehs_tags{'debian-mangled-uversion'} = $mangled_lastversion;
    $dehs_tags{'upstream-version'} = $newversion;
    $dehs_tags{'upstream-url'} = $upstream_url;

    # Can't just use $lastversion eq $newversion, as then 0.01 and 0.1
    # compare different, whereas they are treated as equal by dpkg
    if (system("dpkg", "--compare-versions", "1:${mangled_lastversion}-0", "eq", "1:${newversion}-0") == 0) {
	if ($verbose or ($download == 0 and $report and ! $dehs)) {
	    print $pkg_report_header;
	    $pkg_report_header = '';
	    print "Newest version on remote site is $newversion, local version is $lastversion\n" .
		($mangled_lastversion eq $lastversion ? "" : " (mangled local version number $mangled_lastversion)\n");
	    print " => Package is up to date\n";
	}
	$dehs_tags{'status'} = "up to date";
	if (! $force_download) {
	    return 0;
	} else {
	    $download = 1;
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
	foreach my $suffix (qw(gz bz2 lzma xz)) {
	    if (-f "$destdir/${pkg}_${newversion}.orig.tar.$suffix") {
		print " => ${pkg}_${newversion}.orig.tar.$suffix already in package directory '$destdir'\n"
		    if $verbose or ($download == 0 and ! $dehs);
		return 0;
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
    # Check GPG
    if (defined $pgpsig_url) {
	print "-- Downloading OpenPGP signature for package as $newfile_base.pgp\n" if $verbose;
	if (!$downloader->($pgpsig_url, "$destdir/$newfile_base.pgp")) {
	    return 1;
	}

	print "-- Verifying OpenPGP signature $newfile_base.pgp for $newfile_base\n" if $verbose;
	system('/usr/bin/gpgv', '--homedir', '/dev/null',
	       '--keyring', $keyring,
	       "$destdir/$newfile_base.pgp", "$destdir/$newfile_base") >> 8 == 0
		 or uscan_die("$progname warning: OpenPGP signature did not verify.\n");
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

    # Call mk-origtargz (renames, repacks, etc.)
    my $mk_origtargz_out;
    my $path = "$destdir/$newfile_base";
    my $target = $newfile_base;
    unless ($symlink eq "no") {
	my @cmd = ("mk-origtargz");
	push @cmd, "--package", $pkg;
	push @cmd, "--version", $newversion;
	push @cmd, '--repack-suffix', $options{repacksuffix} if defined $options{repacksuffix};
	push @cmd, "--rename" if $symlink eq "rename";
	push @cmd, "--copy"   if $symlink eq "copy";
	push @cmd, "--repack" if $repack;
	push @cmd, "--compression", $repack_compression;
	push @cmd, "--directory", $destdir;
	push @cmd, "--copyright-file", "debian/copyright"
	    if ($exclusion && -e "debian/copyright");
	push @cmd, "--copyright-file", $copyright_file
	    if ($exclusion && defined $copyright_file);
	push @cmd, $path;

	spawn(exec => \@cmd,
	      to_string => \$mk_origtargz_out,
	      wait_child => 1);
	chomp($mk_origtargz_out);
	$path = $1 if $mk_origtargz_out =~ /Successfully .* (?:to|as) ([^,]+)\.$/;
	$path = $1 if $mk_origtargz_out =~ /Leaving (.*) where it is/;
	$target = basename($path);
    }

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

	# Any symlink requests are already handled by uscan
	if ($action =~ /^uupdate(\s|$)/) {
	    push @cmd, "--no-symlink";
	}

	if ($watch_version > 1) {
	    push @cmd, "--upstream-version", $newversion, $path;
	} else {
	    push @cmd, $path, $newversion;
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
    my ($site, $dir, $pattern, $optref, $watchfile) = @_;
    my $base = $site.$dir;
    my ($request, $response);

    if ($site =~ m%^http(s)?://%) {
	if (defined($1) and !$haveSSL) {
	    uscan_die "$progname: you must have the liblwp-protocol-https-perl package installed\nto use https URLs\n";
	}
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base);
	$response = $user_agent->request($request);
	if (! $response->is_success) {
	    uscan_warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
	    return 1;
	}

	my $content = $response->content;
	print STDERR "$progname debug: received content:\n$content\[End of received content\]\n"
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
	while ($content =~ m/<\s*a\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/gi) {
	    my $href = $2;
	    if ($href =~ m&^$dirpattern/?$&) {
		my $mangled_version = join(".", map { $_ // '' } $href =~ m&^$dirpattern/?$&);
		push @hrefs, [$mangled_version, $href];
	    }
	}
	if (@hrefs) {
	    @hrefs = Devscripts::Versort::upstream_versort(@hrefs);
	    if ($debug) {
		print "-- Found the following matching hrefs (newest first):\n";
		foreach my $href (@hrefs) { print "     $$href[1] ($$href[0])\n"; }
	    }
	    my $newdir = $hrefs[0][1];
	    # just give the final directory component
	    $newdir =~ s%/$%%;
	    $newdir =~ s%^.*/%%;
	    return $newdir;
	} else {
	    uscan_warn "$progname warning: In $watchfile,\n  no matching hrefs for pattern\n  $site$dir$pattern";
	    return 1;
	}
    }
    else {
	# Better be an FTP site
	if ($site !~ m%^ftp://%) {
	    return 1;
	}

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
	print STDERR "$progname debug: received content:\n$content\[End of received content]\n"
	    if $debug;

	# FTP directory listings either look like:
	# info info ... info filename [ -> linkname]
	# or they're HTMLised (if they've been through an HTTP proxy)
	# so we may have to look for <a href="filename"> type patterns
	print STDERR "$progname debug: matching pattern $pattern\n" if $debug;
	my (@dirs);

	# We separate out HTMLised listings from standard listings, so
	# that we can target our search correctly
	if ($content =~ /<\s*a\s+[^>]*href/i) {
	    while ($content =~
		m/(?:<\s*a\s+[^>]*href\s*=\s*\")((?-i)$pattern)\"/gi) {
		my $dir = $1;
		my $mangled_version = join(".", $dir =~ m/^$pattern$/);
		push @dirs, [$mangled_version, $dir];
	    }
	} else {
	    # they all look like:
	    # info info ... info filename [ -> linkname]
	    foreach my $ln (split(/\n/, $content)) {
		if ($ln =~ m/($pattern)(\s+->\s+\S+)?$/) {
		    my $dir = $1;
		    my $mangled_version = join(".", $dir =~ m/^$pattern$/);
		    push @dirs, [$mangled_version, $dir];
		}
	    }
	}
	if (@dirs) {
	    if ($debug) {
		print STDERR "-- Found the following matching dirs:\n";
		foreach my $dir (@dirs) { print STDERR "     $$dir[1]\n"; }
	    }
	    @dirs = Devscripts::Versort::upstream_versort(@dirs);
	    my ($newversion, $newdir) = @{$dirs[0]};
	    return $newdir;
	} else {
	    uscan_warn "$progname warning: In $watchfile no matching dirs for pattern\n  $base$pattern\n";
	    return '';
	}
    }
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
