#! /usr/bin/perl -w

# uscan: This program looks for watchfiles and checks upstream ftp sites
# for later versions of the software.
#
# Originally written by Christoph Lameter <clameter@debian.org> (I believe)
# Modified by Julian Gilbey <jdg@debian.org>
# HTTP support added by Piotr Roszatycki <dexter@debian.org>
# Copyright 1999, Julian Gilbey
# Rewritten in Perl, Copyright 2002, Julian Gilbey
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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use 5.006_000;  # uses 'our' variables
use strict;
use Cwd;
use File::Basename;
use Getopt::Long;
use lib '/usr/share/devscripts';
use Devscripts::Versort;
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

my $progname = basename($0);
my $modified_conf_msg;
my $opwd = cwd();

# Did we find any new upstream versions on our wanderings?
our $found = 0;

sub process_watchline ($$$$$$);
sub process_watchfile ($$$$);

sub usage {
    print <<"EOF";
Usage: $progname [options] [dir ...]
  Process watchfiles in all .../debian/ subdirs of those listed (or the
  current directory if none listed) to check for upstream releases.
Options:
    --report, --no-download
                   Only report on newer or absent versions, do not download
    --debug        Dump the downloaded web pages to stdout for debugging
                   your watch file. 
    --download     Report on newer and absent versions, and download (default)
    --pasv         Use PASV mode for FTP connections
    --no-pasv      Do not use PASV mode for FTP connections (default)
    --symlink      Make an orig.tar.gz symlink to downloaded file (default)
    --no-symlink   Don\'t make this symlink
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
                   (default: 'PACKAGE(-.*)?')
    --no-conf, --noconf
                   Don\'t read devscripts config files;
                   must be the first option given
    --help         Show this message
    --version      Show version information

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999 by Julian Gilbey, all rights reserved.
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

my $download = 1;
my $symlink = 1;
my $verbose = 0;
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.*)?';

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'USCAN_DOWNLOAD' => 'yes',
		       'USCAN_PASV' => 'default',
		       'USCAN_SYMLINK' => 'yes',
		       'USCAN_VERBOSE' => 'no',
		       'DEVSCRIPTS_CHECK_DIRNAME_LEVEL' => 1,
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.*)?',
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
    $config_vars{'USCAN_DOWNLOAD'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_DOWNLOAD'}='yes';
    $config_vars{'USCAN_PASV'} =~ /^(yes|no|default)$/
	or $config_vars{'USCAN_PASV'}='default';
    $config_vars{'USCAN_SYMLINK'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_SYMLINK'}='yes';
    $config_vars{'USCAN_VERBOSE'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_VERBOSE'}='no';
    $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} =~ /^[012]$/
	or $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'}=1;

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $download = $config_vars{'USCAN_DOWNLOAD'} eq 'no' ? 0 : 1;
    $passive = $config_vars{'USCAN_PASV'} eq 'yes' ? 1 :
	$config_vars{'USCAN_PASV'} eq 'no' ? 0 : 'default';
    $symlink = $config_vars{'USCAN_SYMLINK'} eq 'no' ? 0 : 1;
    $verbose = $config_vars{'USCAN_VERBOSE'} eq 'yes' ? 1 : 0;
    $check_dirname_level = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
    $check_dirname_regex = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_REGEX'};
}

# Now read the command line arguments
my $debug = 0;
my ($opt_h, $opt_v, $opt_download, $opt_passive, $opt_symlink);
my ($opt_verbose, $opt_ignore, $opt_level, $opt_regex, $opt_noconf);

GetOptions("help" => \$opt_h,
	   "version" => \$opt_v,
	   "download!" => \$opt_download,
	   "report" => sub { $opt_download = 0; },
	   "passive|pasv!" => \$opt_passive,
	   "symlink!" => \$opt_symlink,
	   "verbose!" => \$opt_verbose,
	   "debug" => \$debug,
	   "ignore-dirname" => \$opt_ignore,
	   "check-dirname-level=s" => \$opt_level,
	   "check-dirname-regex=s" => \$opt_regex,
	   "noconf" => \$opt_noconf,
	   "no-conf" => \$opt_noconf,
	   )
    or die "Usage: $progname [options] [directories]\nRun $progname --help for more details\n";

if ($opt_noconf) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}
if ($opt_h) { usage(); exit 0; }
if ($opt_v) { version(); exit 0; }

# Now we can set the other variables according to the command line options

$download = $opt_download if defined $opt_download;
$passive = $opt_passive if defined $opt_passive;
$symlink = $opt_symlink if defined $opt_symlink;
$verbose = $opt_verbose if defined $opt_verbose;

# dirname stuff
if ($opt_ignore) {
    die "$progname: --ignore-dirname has been replaced by --check-dirname-level and\n--check-dirname-regex; run $progname --help for more details\n";
}

if (defined $opt_level) {
    if ($opt_level =~ /^[012]$/) { $check_dirname_level = $opt_level; }
    else {
	die "$progname: unrecognised --check-dirname-level value (allowed are 0,1,2)\n";
    }
}

$check_dirname_regex = $opt_regex if defined $opt_regex;


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

my $user_agent = LWP::UserAgent->new(env_proxy => 1);

push @ARGV, '.' if ! @ARGV;

print "-- Scanning for watchfiles in @ARGV\n" if $verbose;

# Run find to find the directories.  We will handle filenames with spaces
# correctly, which makes this code a little messier than it would be
# otherwise.
my @dirs;
my $pid = open FIND, '-|';
if (! defined $pid) {
    die "$progname: couldn't fork: $!\n";
}
if ($pid) {
    while (<FIND>) {
	chomp;
	push @dirs, $_;
    }
    close FIND;
} else {
    exec 'find', @ARGV, qw(-type d -name debian -print);
    die "$progname: couldn't exec find: $!\n";
}

my @debdirs = ();

my $origdir = cwd;
for my $dir (@dirs) {
    unless (chdir $origdir) {
	warn "$progname warning: Couldn't chdir back to $origdir, skipping: $!\n";
	next;
    }
    $dir =~ s%/debian$%%;
    unless (chdir $dir) {
	warn "$progname warning: Couldn't chdir $dir, skipping: $!\n";
	next;
    }

    # Check for debian/watch file
    if (-r 'debian/watch' and -r 'debian/changelog') {
	# Figure out package info we need
	my $changelog = `dpkg-parsechangelog`;
	unless ($? == 0) {
	    warn "$progname warning: Problems running dpkg-parsechangelog in $dir, skipping\n";
	    next;
	}

	my ($package, $debversion, $version);
	$changelog =~ /^Source: (.*?)$/m and $package=$1;
	$changelog =~ /^Version: (.*?)$/m and $debversion=$1;
	if (! defined $package || ! defined $debversion) {
	    warn "$progname warning: Problems determining package name and/or version from\n  $dir/debian/changelog, skipping\n";
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
	    print "-- Skip watchfile in $dir/debian since it does not match the package name\n".
	        "   (or the settings of the--check-dirname-level and --check-dirname-regex options if any).\n"
	        if $verbose;
	    next;
	}

	# Get upstream version number
	$version = $debversion;
	$version =~ s/-[^-]+$//;  # revision
	$version =~ s/^\d+://;    # epoch

	push @debdirs, [$debversion, $dir, $package, $version, $good_dirname];
    }
    elsif (-r 'debian/watch') {
	warn "$progname warning: Found watchfile in $dir,\n  but couldn't find/read changelog; skipping\n";
	next;
    }
    elsif (-f 'debian/watch') {
	warn "$progname warning: Found watchfile in $dir,\n  but it is not readable; skipping\n";
	next;
    }
}

# Now sort the list of directories, so that we process the most recent
# directories first, as determined by the package version numbers
@debdirs = Devscripts::Versort::versort(@debdirs);

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
    my $good_dirname = $$debdir[3];

    if (exists $donepkgs{$parentdir}{$package}) {
	warn "$progname warning: Skipping $dir/debian/watch\n  as this package has already been scanned successfully\n";
	next;
    }

    unless (chdir $origdir) {
	warn "$progname warning: Couldn't chdir back to $origdir, skipping: $!\n";
	next;
    }
    unless (chdir $dir) {
	warn "$progname warning: Couldn't chdir $dir, skipping: $!\n";
	next;
    }

    if (process_watchfile($dir, $package, $version, $good_dirname) == 0) {
	$donepkgs{$parentdir}{$package} = 1;
    }
}

print "-- Scan finished\n" if $verbose;

exit $found ? 0 : 1;


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
#   ftp://site.name/dir/path/pattern-(.*)\.tar\.gz [version [action]]
# 
# For http sites:
#   http://site.name/dir/path/pattern-(.*)\.tar\.gz [version [action]]
# or
#   http://site.name/dir/path/base pattern-(.*)\.tar\.gz [version [action]]
# 
# Lines can be prefixed with opts=<opts>.
# 
# Then the patterns matched will be checked to find the one with the
# greatest version number (as determined by the (...) group), using the
# Debian version number comparison algorithm described below.

sub process_watchline ($$$$$$)
{
    my ($line, $watch_version, $pkg_dir, $pkg, $pkg_version, $good_dirname) = @_;

    my ($base, $site, $dir, $pattern, $lastversion, $action);
    my %options = ();

    my ($request, $response);
    my ($newfile, $newversion);
    my $style='new';
    my $urlbase;

    if ($watch_version == 1) {
	($site, $dir, $pattern, $lastversion, $action) = split ' ', $line;

	if (! defined $lastversion or $site =~ /\(.*\)/ or $dir =~ /\(.*\)/) {
	    warn "$progname warning: there appears to be a version 2 format line in\n  the version 1 watchfile $dir/debian/watch;\n  Have you forgotten a 'version=2' line at the start, perhaps?\n  Skipping the line: $line\n";
	    return 1;
	}
	if ($site !~ m%\w+://%) {
	    $site = "ftp://$site";
	    if ($pattern !~ /\(.*\)/) {
		# watch_version=1 and old style watchfile;
		# pattern uses ? and * shell wildcards; everything from the first
		# to last of these metachars is the pattern to match on.
		$pattern =~ s/(\?|\*)/($1/;
		$pattern =~ s/(\?|\*)([^\?\*]*)$/$1)$2/;
		$pattern =~ s/\./\\./g;
		$pattern =~ s/\?/./g;
		$pattern =~ s/\*/.*/g;
		$style='old';
		warn "$progname warning: Using very old style of filename pattern in $pkg_dir/debian/watch\n  (this might lead to incorrect results): $3\n";
	    }
	}

	# Merge site and dir
	$base = "$site/$dir/";
	$base =~ s%(?<!:)//%/%g;
	$base =~ m%^(\w+://[^/]+)%;
	$site = $1;
    } else {
	if ($line =~ s/^opt(?:ion)?s=(\S+)\s+//) {
	    my $opts=$1;
	    my @opts = split /,/, $opts;
	    foreach my $opt (@opts) {
		if ($opt eq 'pasv' or $opt eq 'passive') {
		    $options{'pasv'}=1;
		}
		elsif ($opt eq 'active' or $opt eq 'nopasv'
		       or $opt eq 'nopassive') {
		    $options{'pasv'}=0;
		}
		else {
		    warn "$progname warning: unrecognised option $opt\n";
		}
	    }
	}
	($base, $pattern, $lastversion, $action) = split ' ', $line;
	if ($base =~ /\(.*\)/) {
	    # only three fields
	    $action = $lastversion;
	    $lastversion = $pattern;
	    # We're going to make the pattern
	    # (?:(?:http://site.name)?/dir/path/)?base_pattern
	    # It's fine even for ftp sites
	    $pattern = $base;
	    $pattern =~ s%^(\w+://[^/]+)%(?:$1)?%;
	    $pattern =~ s%^(.*/)%(?:$1)?%;
	    $base =~ s%/[^/]+$%/%;
	}

	if ($base =~ m%^(\w+://[^/]+)%) {
	    $site = $1;
	} else {
	    warn "$progname warning: Can't determine protocol and site in\n  $pkg_dir/debian/watch, skipping:\n  $line\n";
	    return 1;
	}
    }

    # Check all's OK
    if ($pattern !~ /\(.*\)/) {
	warn "$progname warning: Filename pattern missing version delimeters ()\n  in $pkg_dir/debian/watch, skipping:\n  $line\n";
	return 1;
    }

    # What is the most recent file, based on the filenames?
    # We first have to find the candidates, then we sort them using
    # Devscripts::Versort::versort
    if ($site =~ m%^http://%) {
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base);
	$response = $user_agent->request($request);
	if (! $response->is_success) {
	    warn "$progname warning: In watchfile $pkg_dir/debian/watch, reading webpage\n  $base failed: " . $response->status_line . "\n";
	    return 1;
	}

	my $content = $response->content;
	print STDERR "$progname debug: received content:\n$content\[End of received content]\n"
	    if $debug;
	# We need this horrid stuff to handle href=foo type
	# links.  OK, bad HTML, but we have to handle it nonetheless.
	# It's bug #89749.
	$content =~ s/href\s*=\s*(?=[^\"\'])([^\s>]+)/href="$1"/ig;
	# Strip comments
	$content =~ s/<!-- .*?-->//sg;
	# Is there a base URL given?
	if ($content =~ /<\s*base\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/) {
	    # Ensure it ends with /
	    $urlbase = "$2/";
	    $urlbase =~ s%//$%/%;
	} else {
	    # May have to strip a base filename
	    ($urlbase = $base) =~ s%/[^/]*$%/%;
	}

	print STDERR "$progname debug: matching pattern $pattern\n" if $debug;
	my @hrefs;
	while ($content =~ m/<\s*a\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/gi) {
	    my $href = $2;
	    if ($href =~ m/^$pattern$/) {
		push @hrefs, [$1, $href];  # [ version, href ]
	    }
	}
	if (@hrefs) {
	    if ($verbose) {
		print "-- Found the following matching hrefs:\n";
		foreach my $href (@hrefs) { print "     $$href[1]\n"; }
	    }
	    @hrefs = Devscripts::Versort::versort(@hrefs);
	    ($newversion, $newfile) = @{$hrefs[0]};
	} else {
	    warn "$progname warning: In $pkg_dir/debian/watch,\n  no matching hrefs for watch line\n  $line\n";
	    return 1;
	}
    }
    else {
	# Better be an FTP site
	if ($site !~ m%^ftp://%) {
	    warn "$progname warning: Unknown protocol in $pkg_dir/debian/watch, skipping:\n  $site\n";
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
	    warn "$progname warning: In watchfile $pkg_dir/debian/watch, reading FTP directory\n  $base failed: " . $response->status_line . "\n";
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
	$content =~ s/\n/ \n/g; # make every filename have an extra
	                        # space after it in a normal FTP listing
	while ($content =~
	           m/(?:<\s*a\s+[^>]*href\s*=\s*\"| )($pattern)(\"| )/gi) {
	    push @files, [$2, $1];  # [ version, file ]
	}
	if (@files) {
	    if ($verbose) {
		print "-- Found the following matching files:\n";
		foreach my $file (@files) { print "     $$file[1]\n"; }
	    }
	    @files = Devscripts::Versort::versort(@files);
	    ($newversion, $newfile) = @{$files[0]};
	} else {
	    warn "$progname warning: In $pkg_dir/debian/watch no matching files for watch line\n  $line\n";
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
	    warn <<"EOF";
$progname warning: In $pkg_dir/debian/watch, couldn\'t determine a
  pure numeric version number from the file name for watch line
  $line
  and file name $newfile
  Please use a new style watchfile instead!
EOF
	    return 1;
	}
    }
			
    my $newfile_base=basename($newfile);
    # Remove HTTP header trash
    if ($site =~ m%^http://%)
    {
        $newfile_base =~ s/\?.*$//;
    }
    if (! $lastversion or $lastversion eq 'debian') {
	$lastversion=$pkg_version;
    }

    print "Newest version on remote site is $newversion, local version is $lastversion\n"
	if $verbose;

    # Can't just use $lastversion eq $newversion, as then 0.01 and 0.1
    # compare different, whereas they are treated as equal by dpkg
    if (system("dpkg --compare-versions '$lastversion' eq '$newversion'") == 0) {
	print " => Package is up to date\n" if $verbose;
	return 0;
    }

    # We use dpkg's rules to determine whether our current version
    # is newer or older than the remote version.
    if (system("dpkg --compare-versions '$lastversion' gt '$newversion'") == 0) {
        if ($verbose) {
	    print " => remote site does not even have current version\n";
	} else {
	    print "$pkg: remote site does not even have current version\n";
	}
        return 0;
    } else {
	# There's a newer upstream version available, which may already
	# be on our system or may not be
	$found++;
    }

    if (-f "../$newfile_base") {
        print " => $newfile_base already in package directory\n"
	    if $verbose;
        return 0;
    }
    if (-f "../${pkg}_${newversion}.orig.tar.gz") {
        warn "$progname warning: In directory $pkg_dir, found file\n  ${pkg}_${newversion}.orig.tar.gz but not $newfile_base,\n  which is the newest file available on remote site.  Skipping.\n";
        return 0;
    }

    if ($verbose) {
	print " => Newer version available\n";
    } else {
	print "$pkg: Newer version ($newversion) available on remote site\n  (local version is $lastversion)\n";
    }

    return 0 unless $download;

    print "-- Downloading updated package $newfile_base\n" if $verbose;
    # Download newer package
    if ($site =~ m%^http://%) {
	# absolute URL?
	if ($newfile =~ m%^\w+://%) {
	    print STDERR "$progname debug: requesting URL $newfile\n" if $debug;
	    $request = HTTP::Request->new('GET', $newfile);
	    $response = $user_agent->request($request, "../$newfile_base");
	    if (! $response->is_success) {
		warn "$progname warning: In directory $pkg_dir, downloading\n  $newfile failed: " . $response->status_line . "\n";
		return 1;
	    }
	}
	# absolute filename?
	elsif ($newfile =~ m%^/%) {
	    print STDERR "$progname debug: requesting URL $site$newfile\n" if $debug;
	    $request = HTTP::Request->new('GET', "$site$newfile");
	    $response = $user_agent->request($request, "../$newfile_base");
	    if (! $response->is_success) {
		warn "$progname warning: In directory $pkg_dir, downloading\n  $site$newfile failed: " . $response->status_line . "\n";
		return 1;
	    }
	}
	# relative filename, we hope
	else {
	    print STDERR "$progname debug: requesting URL $urlbase$newfile\n" if $debug;
	    $request = HTTP::Request->new('GET', "$urlbase$newfile");
	    $response = $user_agent->request($request, "../$newfile_base");
	    if (! $response->is_success) {
		warn "$progname warning: In directory $pkg_dir, downloading\n  $urlbase$newfile failed: " . $response->status_line . "\n";
		return 1;
	    }
	}
    }
    else {
	# FTP site
	if (exists $options{'pasv'}) {
	    $ENV{'FTP_PASSIVE'}=$options{'pasv'};
	}
	print STDERR "$progname debug: requesting URL $base$newfile\n" if $debug;
	$request = HTTP::Request->new('GET', "$base$newfile");
	$response = $user_agent->request($request, "../$newfile_base");
	if (exists $options{'pasv'}) {
	    if (defined $passive) { $ENV{'FTP_PASSIVE'}=$passive; }
	    else { delete $ENV{'FTP_PASSIVE'}; }
	}
	if (! $response->is_success) {
	    warn "$progname warning: In directory $pkg_dir, downloading\n  $base$newfile failed: " . $response->status_line . "\n";
	    return 1;
	}
    }

    if ($symlink and $newfile_base =~ /\.(tar\.gz|tgz)$/) {
	symlink $newfile_base, "../${pkg}_${newversion}.orig.tar.gz";
    }

    if ($verbose) {
	print "-- Successfully downloaded updated package $newfile_base\n";
	if ($symlink and $newfile_base =~ /\.(tar\.gz|tgz)$/) {
	    print "    and symlinked ${pkg}_${newversion}.orig.tar.gz to it\n";
	}
    } else {
	print "$pkg: Successfully downloaded updated package $newfile_base\n";
	if ($symlink and $newfile_base =~ /\.(tar\.gz|tgz)$/) {
	    print "    and symlinked ${pkg}_${newversion}.orig.tar.gz to it\n";
	}
    }

    # Do whatever the user wishes to do
    if ($action) {
	my $usefile = ($symlink and $newfile_base =~ /\.(tar\.gz|tgz)$/) ?
	    "../${pkg}_${newversion}.orig.tar.gz" : "../$newfile_base";

	if ($watch_version > 1) {
	    print "-- Executing user specified script\n     $action --upstream-version $newversion $newfile_base" if $verbose;
	    system("$action --upstream-version $newversion $usefile");
	} else {
	    print "-- Executing user specified script $action $newfile_base $newversion" if $verbose;
	    system("$action $usefile $newversion");
	}
    }

    return 0;
}

# parameters are dir, package, upstream version, good dirname
sub process_watchfile ($$$$)
{
    my ($dir, $package, $version, $good_dirname) = @_;
    my $watch_version=0;
    my $status=0;

    unless (open WATCH, 'debian/watch') {
	warn "$progname warning: could not open $dir/debian/watch: $!\n";
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
		warn "$progname warning: $dir/debian/watch ended with \\; skipping last line\n";
		$status=1;
		last;
	    }
	    $_ .= <WATCH>;
	    goto CHOMP;
	}

	if (! $watch_version) {
	    if (/^version\s*=\s*(\d+)(\s|$)/) {
		$watch_version=$1;
		if ($watch_version < 2 or $watch_version > 2) {
		    print STDERR "Error: $dir/debian/watch version number is unrecognised; skipping watchfile\n";
		    last;
		}
		next;
	    } else {
		warn "$progname warning: $dir/debian/watch is an obsolete version 1 watchfile;\n  please upgrade to a higher version\n  (see uscan(1) for details).\n";
		$watch_version=1;
	    }
	}

	# Handle shell \\ -> \
	s/\\\\/\\/g if $watch_version==1;
	print "-- In $dir/debian/watch, processing watchfile line:\n   $_\n" if $verbose;
	$status +=
	    process_watchline($_, $watch_version, $dir, $package, $version, $good_dirname);
    }

    close WATCH or
	$status=1, warn "$progname warning: problems reading $dir/debian/watch\n";

    return $status;
}
