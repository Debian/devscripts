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

use 5.008;  # uses 'our' variables and filetest
use strict;
use Cwd;
use File::Basename;
use File::Copy;
use filetest 'access';
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
my $CURRENT_WATCHFILE_VERSION = 3;

my $progname = basename($0);
my $modified_conf_msg;
my $opwd = cwd();

# Did we find any new upstream versions on our wanderings?
our $found = 0;

sub process_watchline ($$$$$$);
sub process_watchfile ($$$$);
sub recursive_regex_dir ($$$);
sub newest_dir ($$$$$);
sub dehs_msg ($);
sub dehs_warn ($);
sub dehs_die ($);
sub dehs_output ();

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
    --download     Report on newer and absent versions, and download (default)
    --no-download  Report on newer and absent versions, but don\'t download
    --pasv         Use PASV mode for FTP connections
    --no-pasv      Do not use PASV mode for FTP connections (default)
    --timeout N    Specifies how much time, in seconds, we give remote
                   servers to respond (default 20 seconds)
    --symlink      Make an orig.tar.gz symlink to downloaded file (default)
    --rename       Rename to orig.tar.gz instead of symlinking
                   (Both will use orig.tar.bz2 if appropriate)
    --no-symlink   Don\'t make symlink or rename
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
    --watchfile FILE
                   Specify the watchfile rather than using debian/watch;
                   no directory traversing will be done in this case
    --upstream-version VERSION
                   Specify the current upstream version in use rather than
                   parsing debian/changelog to determine this
    --package PACKAGE
                   Specify the package name rather than examining
                   debian/changelog; must use --upstream-version and
                   --watchfile with this option, no directory traversing
                   will be performed, no actions (even downloading) will be
                   carried out
    --no-dehs      Use traditional uscan output format (default)
    --dehs         Use DEHS style output (XML-type)
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
my $report = 0; # report even on up-to-date packages?
my $symlink = 'symlink';
my $verbose = 0;
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.*)?';
my $dehs = 0;
my %dehs_tags;
my $dehs_end_output = 0;
my $dehs_start_output = 0;
my $pkg_report_header = '';
my $timeout = 20;

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
               'USCAN_TIMEOUT' => 20,
		       'USCAN_DOWNLOAD' => 'yes',
		       'USCAN_PASV' => 'default',
		       'USCAN_SYMLINK' => 'symlink',
		       'USCAN_VERBOSE' => 'no',
		       'USCAN_DEHS_OUTPUT' => 'no',
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
    $config_vars{'USCAN_TIMEOUT'} =~ m/^\d+$/
    or $config_vars{'USCAN_TIMEOUT'}=20;
    $config_vars{'USCAN_SYMLINK'} =~ /^(yes|no|symlinks?|rename)$/
	or $config_vars{'USCAN_SYMLINK'}='yes';
    $config_vars{'USCAN_SYMLINK'}='symlink'
	if $config_vars{'USCAN_SYMLINK'} eq 'yes' or
	    $config_vars{'USCAN_SYMLINK'} eq 'symlinks';
    $config_vars{'USCAN_VERBOSE'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_VERBOSE'}='no';
    $config_vars{'USCAN_DEHS_OUTPUT'} =~ /^(yes|no)$/
	or $config_vars{'USCAN_DEHS_OUTPUT'}='no';
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
    $timeout = $config_vars{'USCAN_TIMEOUT'};
    $symlink = $config_vars{'USCAN_SYMLINK'};
    $verbose = $config_vars{'USCAN_VERBOSE'} eq 'yes' ? 1 : 0;
    $dehs = $config_vars{'USCAN_DEHS_OUTPUT'} eq 'yes' ? 1 : 0;
    $check_dirname_level = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
    $check_dirname_regex = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_REGEX'};
}

# Now read the command line arguments
my $debug = 0;
my ($opt_h, $opt_v, $opt_download, $opt_report, $opt_passive, $opt_symlink);
my ($opt_verbose, $opt_ignore, $opt_level, $opt_regex, $opt_noconf);
my ($opt_package, $opt_uversion, $opt_watchfile, $opt_dehs, $opt_timeout);

GetOptions("help" => \$opt_h,
	   "version" => \$opt_v,
	   "download!" => \$opt_download,
	   "report" => sub { $opt_download = 0; },
	   "report-status" => sub { $opt_download = 0; $opt_report = 1; },
	   "passive|pasv!" => \$opt_passive,
       "timeout=i" => \$opt_timeout,
	   "symlink!" => sub { $opt_symlink = $_[1] ? 'symlink' : 'no'; },
	   "rename" => sub { $opt_symlink = 'rename'; },
	   "package=s" => \$opt_package,
	   "upstream-version=s" => \$opt_uversion,
	   "watchfile=s" => \$opt_watchfile,
	   "dehs!" => \$opt_dehs,
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
$report = $opt_report if defined $opt_report;
$passive = $opt_passive if defined $opt_passive;
$timeout = $opt_timeout if defined $opt_timeout;
$symlink = $opt_symlink if defined $opt_symlink;
$verbose = $opt_verbose if defined $opt_verbose;
$dehs = $opt_dehs if defined $opt_dehs;
if ($dehs) {
    $SIG{'__WARN__'} = \&dehs_warn;
    $SIG{'__DIE__'} = \&dehs_die;
}

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

if (defined $opt_package) {
    die "$progname: --package requires the use of --upstream-version and --watchfile\nas well; run $progname --help for more details\n"
	unless defined $opt_uversion and defined $opt_watchfile;
    $download = -$download unless defined $opt_download;
}

die "$progname: Can't use --verbose if you're using --dehs!\n"
    if $verbose and $dehs;

die "$progname: Can't use --report-status if you're using --dehs!\n"
    if $verbose and $report;

die "$progname: Can't use --report-status if you're using --download!\n"
    if $download and $report;

warn "$progname: You're going to get strange (non-XML) output using --debug and --dehs together!\n"
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

my $user_agent = LWP::UserAgent->new(env_proxy => 1);
$user_agent->timeout($timeout);

if (defined $opt_watchfile) {
    die "Can't have directory arguments if using --watchfile" if @ARGV;

    # no directory traversing then, and things are very simple
    if (defined $opt_package) {
	# no need to even look for a changelog!
	process_watchfile(undef, $opt_package, $opt_uversion, $opt_watchfile);
    } else {
	# Check for debian/changelog file
	until (-r 'debian/changelog') {
	    chdir '..' or die "$progname: can't chdir ..: $!\n";
	    if (cwd() eq '/') {
		die "$progname: cannot find readable debian/changelog anywhere!\nAre you in the source code tree?\n";
	    }
	}

	# Figure out package info we need
	my $changelog = `dpkg-parsechangelog`;
	unless ($? == 0) {
	    die "$progname: Problems running dpkg-parsechangelog\n";
	}

	my ($package, $debversion, $uversion);
	$changelog =~ /^Source: (.*?)$/m and $package=$1;
	$changelog =~ /^Version: (.*?)$/m and $debversion=$1;
	if (! defined $package || ! defined $debversion) {
	    die "$progname: Problems determining package name and/or version from\n  debian/changelog\n";
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
	    die "$progname: not processing watchfile because this directory does not match the package name\n" .
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
    exit 0;
}

# Otherwise we're scanning for watchfiles
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
    exec 'find', @ARGV, qw(-follow -type d -name debian -print);
    die "$progname: couldn't exec find: $!\n";
}

die "$progname: No debian directories found\n" unless @dirs;

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

	my ($package, $debversion, $uversion);
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
	    print "-- Skip watchfile in $dir/debian since it does not match the package name\n" .
	        "   (or the settings of the--check-dirname-level and --check-dirname-regex options if any).\n"
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
	warn "$progname warning: Found watchfile in $dir,\n  but couldn't find/read changelog; skipping\n";
	next;
    }
    elsif (-f 'debian/watch') {
	warn "$progname warning: Found watchfile in $dir,\n  but it is not readable; skipping\n";
	next;
    }
}

# Was there a --uversion option?
if (defined $opt_uversion) {
    if (@debdirs == 1) {
	$debdirs[0][3] = $opt_uversion;
    } else {
	warn "$progname warning: ignoring --uversion as more than one debian/watch file found\n";
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

    if (process_watchfile($dir, $package, $version, "debian/watch")
	== 0) {
	$donepkgs{$parentdir}{$package} = 1;
    }
    # Are there any warnings to give if we're using dehs?
    dehs_output if $dehs;
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
#
# watch_version=3:
#
# Correct handling of regex special characters in the path part:
# ftp://ftp.worldforge.org/pub/worldforge/libs/Atlas-C++/transitional/Atlas-C\+\+-(.*)\.tar\.gz
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
# opts=uversionmangle=s/^/0.0/ \
#   ftp://ftp.ibiblio.org/pub/Linux/ALPHA/wine/development/Wine-(.*)\.tar\.gz
# 
# Similarly, the upstream part of the Debian version number can be
# mangled:
# opts=dversionmangle=s/\.dfsg\.\d+$// \
#   http://some.site.org/some/path/foobar-(.*)\.tar\.gz


sub process_watchline ($$$$$$)
{
    my ($line, $watch_version, $pkg_dir, $pkg, $pkg_version, $watchfile) = @_;

    my $origline = $line;
    my ($base, $site, $dir, $filepattern, $pattern, $lastversion, $action);
    my %options = ();

    my ($request, $response);
    my ($newfile, $newversion);
    my $style='new';
    my $urlbase;

    %dehs_tags = ('package' => $pkg);

    if ($watch_version == 1) {
	($site, $dir, $pattern, $lastversion, $action) = split ' ', $line;

	if (! defined $lastversion or $site =~ /\(.*\)/ or $dir =~ /\(.*\)/) {
	    warn "$progname warning: there appears to be a version 2 format line in\n  the version 1 watchfile $watchfile;\n  Have you forgotten a 'version=2' line at the start, perhaps?\n  Skipping the line: $line\n";
	    return 1;
	}
	if ($site !~ m%\w+://%) {
	    $site = "ftp://$site";
	    if ($pattern !~ /\(.*\)/) {
		# watch_version=1 and old style watchfile;
		# pattern uses ? and * shell wildcards; everything from the
		# first to last of these metachars is the pattern to match on
		$pattern =~ s/(\?|\*)/($1/;
		$pattern =~ s/(\?|\*)([^\?\*]*)$/$1)$2/;
		$pattern =~ s/\./\\./g;
		$pattern =~ s/\?/./g;
		$pattern =~ s/\*/.*/g;
		$style='old';
		warn "$progname warning: Using very old style of filename pattern in $watchfile\n  (this might lead to incorrect results): $3\n";
	    }
	}

	# Merge site and dir
	$base = "$site/$dir/";
	$base =~ s%(?<!:)//%/%g;
	$base =~ m%^(\w+://[^/]+)%;
	$site = $1;
    } else {
	# version 2/3 watchfile
	if ($line =~ s/^opt(?:ion)?s=//) {
	    my $opts;
	    if ($line =~ s/^"(.*?)"\s+//) {
		$opts=$1;
	    } elsif ($line =~ s/^(\S+)\s+//) {
		$opts=$1;
	    } else {
		warn "$progname warning: malformed opts=... in watchfile, skipping line:\n$origline\n";
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
		elsif ($opt =~ /^uversionmangle\s*=\s*(.+)/) {
		    @{$options{'uversionmangle'}} = split /;/, $1;
		}
		elsif ($opt =~ /^dversionmangle\s*=\s*(.+)/) {
		    @{$options{'dversionmangle'}} = split /;/, $1;
		}
		else {
		    warn "$progname warning: unrecognised option $opt\n";
		}
	    }
	}

	($base, $filepattern, $lastversion, $action) = split ' ', $line;

	if ($base =~ m%/([^/]*\([^/]*\)[^/]*)$%) {
	    # only three fields
	    $action = $lastversion;
	    $lastversion = $pattern;
	    $filepattern = $1;
	    $base =~ s%/[^/]+$%/%;
	}

	# Handle sf.net addresses specially
	$base =~ s%^http://sf.net/%http://qa.debian.org/watch/sf.php/%;
	if ($base =~ m%^(\w+://[^/]+)%) {
	    $site = $1;
	} else {
	    warn "$progname warning: Can't determine protocol and site in\n  $watchfile, skipping:\n  $line\n";
	    return 1;
	}

	# Find the path with the greatest version number matching the regex
	$base = recursive_regex_dir($base, \%options, $watchfile);
	if ($base eq '') { return 1; }

	# We're going to make the pattern
	# (?:(?:http://site.name)?/dir/path/)?base_pattern
	# It's fine even for ftp sites
	my $basedir = $base;
	$basedir =~ s%^\w+://[^/]+/%/%;
	$pattern = "(?:(?:$site)?" . quotemeta($basedir) . ")?$filepattern";
    }

    # Check all's OK
    if ($pattern !~ /\(.*\)/) {
	warn "$progname warning: Filename pattern missing version delimeters ()\n  in $watchfile, skipping:\n  $line\n";
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
	    warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
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
	    if ($href =~ m&^$pattern$&) {
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
			     $href =~ m&^$pattern$&);
		    foreach my $pat (@{$options{'uversionmangle'}}) {
			eval "\$mangled_version =~ $pat;";
		    }
		    push @hrefs, [$mangled_version, $href];
		}
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
	    warn "$progname warning: In $watchfile,\n  no matching hrefs for watch line\n  $line\n";
	    return 1;
	}
    }
    else {
	# Better be an FTP site
	if ($site !~ m%^ftp://%) {
	    warn "$progname warning: Unknown protocol in $watchfile, skipping:\n  $site\n";
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
	    warn "$progname warning: In watchfile $watchfile, reading FTP directory\n  $base failed: " . $response->status_line . "\n";
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
	           m&(?:<\s*a\s+[^>]*href\s*=\s*\"| )($pattern)(\"| )&gi) {
	    my $file = $1;
	    my $mangled_version = join(".", $file =~ m/^$pattern$/);
	    foreach my $pat (@{$options{'uversionmangle'}}) {
		eval "\$mangled_version =~ $pat;";
	    }
	    push @files, [$mangled_version, $file];
	}
	if (@files) {
	    if ($verbose) {
		print "-- Found the following matching files:\n";
		foreach my $file (@files) { print "     $$file[1]\n"; }
	    }
	    @files = Devscripts::Versort::versort(@files);
	    ($newversion, $newfile) = @{$files[0]};
	} else {
	    warn "$progname warning: In $watchfile no matching files for watch line\n  $line\n";
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
    # Remove HTTP header trash
    if ($site =~ m%^http://%)
    {
        $newfile_base =~ s/\?.*$//;
    }
    if (! $lastversion or $lastversion eq 'debian') {
	$lastversion=$pkg_version;
    }
    # And mangle it if requested
    my $mangled_lastversion = $lastversion;
    foreach my $pat (@{$options{'dversionmangle'}}) {
	eval "\$mangled_lastversion =~ $pat;";
    }

    # So what have we got to report now?
    my $upstream_url;
    # Upstream URL?  Copying code from below - ugh.
    if ($site =~ m%^http://%) {
	# absolute URL?
	if ($newfile =~ m%^\w+://%) {
	    $upstream_url = $newfile;
	}
	# absolute filename?
	elsif ($newfile =~ m%^/%) {
	    $upstream_url = "$site$newfile";
	}
	# relative filename, we hope
	else {
	    $upstream_url = "$urlbase$newfile";
	}
    }
    else {
	# FTP site
	$upstream_url = "$base$newfile";
    }

    $dehs_tags{'debian-uversion'} = $lastversion;
    $dehs_tags{'debian-mangled-uversion'} = $mangled_lastversion;
    $dehs_tags{'upstream-version'} = $newversion;
    $dehs_tags{'upstream-url'} = $upstream_url;

    # Can't just use $lastversion eq $newversion, as then 0.01 and 0.1
    # compare different, whereas they are treated as equal by dpkg
    if (system("dpkg --compare-versions '$mangled_lastversion' eq '$newversion'") == 0) {
	if ($verbose or ($download == 0 and $report and ! $dehs)) {
	    print $pkg_report_header;
	    $pkg_report_header = '';
	    print "Newest version on remote site is $newversion, local version is $lastversion\n" .
		($mangled_lastversion eq $lastversion ? "" : " (mangled local version number $mangled_lastversion)\n");
	    print " => Package is up to date\n";
	}
	$dehs_tags{'status'} = "up to date";
	return 0;
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
    if (system("dpkg --compare-versions '$mangled_lastversion' gt '$newversion'") == 0) {
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

    if (defined $pkg_dir) {
	if (-f "../$newfile_base") {
	    print " => $newfile_base already in package directory\n"
		if $verbose or ($download == 0 and ! $dehs);
	    return 0;
	}
	if (-f "../${pkg}_${newversion}.orig.tar.gz") {
	    print " => ${pkg}_${newversion}.orig.tar.gz already in package directory\n"
		if $verbose or ($download == 0 and ! $dehs);
	    return 0;
	}
	elsif (-f "../${pkg}_${newversion}.orig.tar.bz2") {
	    print " => ${pkg}_${newversion}.orig.tar.bz2 already in package directory\n"
		if $verbose or ($download == 0 and ! $dehs);
	    return 0;
	}
    }

    if ($verbose) {
	print " => Newer version available from\n";
	print "    $upstream_url\n";
    } elsif ($dehs) {
	$dehs_tags{'status'} = "Newer version available";
    } else {
	print "$pkg: Newer version ($newversion) available on remote site:\n  $upstream_url\n  (local version is $lastversion" .
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
    # Download newer package
    if ($upstream_url =~ m%^http://%) {
	print STDERR "$progname debug: requesting URL $upstream_url\n" if $debug;
	$request = HTTP::Request->new('GET', $upstream_url);
	$response = $user_agent->request($request, "../$newfile_base");
	if (! $response->is_success) {
	    warn "$progname warning: In directory $pkg_dir, downloading\n  $upstream_url failed: " . $response->status_line . "\n";
	    return 1;
	}
    }
    else {
	# FTP site
	if (exists $options{'pasv'}) {
	    $ENV{'FTP_PASSIVE'}=$options{'pasv'};
	}
	print STDERR "$progname debug: requesting URL $upstream_url\n" if $debug;
	$request = HTTP::Request->new('GET', "$upstream_url");
	$response = $user_agent->request($request, "../$newfile_base");
	if (exists $options{'pasv'}) {
	    if (defined $passive) { $ENV{'FTP_PASSIVE'}=$passive; }
	    else { delete $ENV{'FTP_PASSIVE'}; }
	}
	if (! $response->is_success) {
	    warn "$progname warning: In directory $pkg_dir, downloading\n  $upstream_url failed: " . $response->status_line . "\n";
	    return 1;
	}
    }

    if ($newfile_base =~ /\.(tar\.gz|tgz)$/) {
	if ($symlink eq 'symlink') {
	    symlink $newfile_base, "../${pkg}_${newversion}.orig.tar.gz";
	} elsif ($symlink eq 'rename') {
	    move "../$newfile_base", "../${pkg}_${newversion}.orig.tar.gz";
	}
    }
    elsif ($newfile_base =~ /\.(tar\.bz2|tbz2?)$/) {
	if ($symlink eq 'symlink') {
	    symlink $newfile_base, "../${pkg}_${newversion}.orig.tar.bz2";
	} elsif ($symlink eq 'rename') {
	    move "../$newfile_base", "../${pkg}_${newversion}.orig.tar.bz2";
	}
    }

    if ($verbose) {
	print "-- Successfully downloaded updated package $newfile_base\n";
	if ($newfile_base =~ /\.(tar\.gz|tgz)$/) {
	    if ($symlink eq 'symlink') {
		print "    and symlinked ${pkg}_${newversion}.orig.tar.gz to it\n";
	    } elsif ($symlink eq 'rename') {
		print "    and renamed it as ${pkg}_${newversion}.orig.tar.gz\n";
	    }
	}
	elsif ($newfile_base =~ /\.(tar\.bz2|tbz2?)$/) {
	    if ($symlink eq 'symlink') {
		print "    and symlinked ${pkg}_${newversion}.orig.tar.bz2 to it\n";
	    } elsif ($symlink eq 'rename') {
		print "    and renamed it as ${pkg}_${newversion}.orig.tar.bz2\n";
	    }
	}
    } elsif ($dehs) {
	my $msg = "Successfully downloaded updated package $newfile_base";
	if ($newfile_base =~ /\.(tar\.gz|tgz)$/) {
	    if ($symlink eq 'symlink') {
		$msg .= " and symlinked ${pkg}_${newversion}.orig.tar.gz to it";
	    } elsif ($symlink eq 'rename') {
		$msg .= " and renamed it as ${pkg}_${newversion}.orig.tar.gz";
	    }
	}
	elsif ($newfile_base =~ /\.(tar\.bz2|tbz2?)$/) {
	    if ($symlink eq 'symlink') {
		$msg .= " and symlinked ${pkg}_${newversion}.orig.tar.bz2 to it";
	    } elsif ($symlink eq 'rename') {
		$msg .= " and renamed it as ${pkg}_${newversion}.orig.tar.bz2";
	    }
	}
	dehs_msg($msg);
    } else {
	print "$pkg: Successfully downloaded updated package $newfile_base\n";
	if ($newfile_base =~ /\.(tar\.gz|tgz)$/) {
	    if ($symlink eq 'symlink') {
		print "    and symlinked ${pkg}_${newversion}.orig.tar.gz to it\n";
	    } elsif ($symlink eq 'rename') {
		print "    and renamed it as ${pkg}_${newversion}.orig.tar.gz\n";
	    }
	}
	elsif ($newfile_base =~ /\.(tar\.bz2|tbz2?)$/) {
	    if ($symlink eq 'symlink') {
		print "    and symlinked ${pkg}_${newversion}.orig.tar.bz2 to it\n";
	    } elsif ($symlink eq 'rename') {
		print "    and renamed it as ${pkg}_${newversion}.orig.tar.bz2\n";
	    }
	}
    }

    # Do whatever the user wishes to do
    if ($action) {
	my $usefile = "../$newfile_base";
	if ($symlink =~ /^(symlink|rename)$/
	    and $newfile_base =~ /\.(tar\.gz|tgz)$/) {
	    $usefile = "../${pkg}_${newversion}.orig.tar.gz";
	}
	elsif ($symlink =~ /^(symlink|rename)$/
	    and $newfile_base =~ /\.(tar\.bz2|tbz2)$/) {
	    $usefile = "../${pkg}_${newversion}.orig.tar.bz2";
	}

	if ($watch_version > 1) {
	    print "-- Executing user specified script\n     $action --upstream-version $newversion $newfile_base" if $verbose;
	    if ($dehs) {
		my $msg = "Executing user specified script: $action --upstream-version $newversion $newfile_base; output:\n";
		$msg .= `$action --upstream-version $newversion $usefile 2>&1`;
		dehs_msg($msg);
	    } else {
		system("$action --upstream-version $newversion $usefile");
	    }
	} else {
	    print "-- Executing user specified script $action $newfile_base $newversion" if $verbose;
	    if ($dehs) {
		my $msg = "Executing user specified script: $action $newfile_base $newversion; output:\n";
		$msg .= `$action $usefile $newversion 2>&1`;
		dehs_msg($msg);
	    } else {
		system("$action $usefile $newversion");
	    }
	}
    }

    return 0;
}


sub recursive_regex_dir ($$$) {
    my ($base, $optref, $watchfile)=@_;

    $base =~ m%^(\w+://[^/]+)/(.*)$%;
    my $site = $1;
    my @dirs = split /(\/)/, $2;
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
		$dir .= "$newest_dir/";
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

    if ($site =~ m%^http://%) {
	print STDERR "$progname debug: requesting URL $base\n" if $debug;
	$request = HTTP::Request->new('GET', $base);
	$response = $user_agent->request($request);
	if (! $response->is_success) {
	    warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
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
		my $mangled_version = join(".", $href =~ m&^$dirpattern/?$&);
		push @hrefs, [$mangled_version, $href];
	    }
	}
	if (@hrefs) {
	    if ($debug) {
		print "-- Found the following matching hrefs:\n";
		foreach my $href (@hrefs) { print "     $$href[1]\n"; }
	    }
	    @hrefs = Devscripts::Versort::versort(@hrefs);
	    my ($newversion, $newdir) = @{$hrefs[0]};
	    return $newdir;
	} else {
	    warn "$progname warning: In $watchfile,\n  no matching hrefs for pattern\n  $site$dir$pattern";
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
	    warn "$progname warning: In watchfile $watchfile, reading webpage\n  $base failed: " . $response->status_line . "\n";
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
	$content =~ s/\n/ \n/g; # make every filename have an extra
	                        # space after it in a normal FTP listing
	while ($content =~
	       m/(?:<\s*a\s+[^>]*href\s*=\s*\"| )($pattern)(\"| )/gi) {
	    my $dir = $1;
	    my $mangled_version = join(".", $dir =~ m/^$pattern$/);
	    push @dirs, [$mangled_version, $dir];
	}
	if (@dirs) {
	    if ($debug) {
		print "-- Found the following matching dirs:\n";
		foreach my $dir (@dirs) { print "     $$dir[1]\n"; }
	    }
	    @dirs = Devscripts::Versort::versort(@dirs);
	    my ($newversion, $newdir) = @{$dirs[0]};
	    return $newdir;
	} else {
	    warn "$progname warning: In $watchfile no matching dirs for pattern\n  $site$base$pattern\n";
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
	warn "$progname warning: could not open $watchfile: $!\n";
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
		warn "$progname warning: $watchfile ended with \\; skipping last line\n";
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
		    warn "$progname ERROR: $watchfile version number is unrecognised; skipping watchfile\n";
		    last;
		}
		next;
	    } else {
		warn "$progname warning: $watchfile is an obsolete version 1 watchfile;\n  please upgrade to a higher version\n  (see uscan(1) for details).\n";
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
	$status=1, warn "$progname warning: problems reading $watchfile: $!\n";

    return $status;
}


# Collect up messages for dehs output into a tag
sub dehs_msg ($)
{
    my $msg = $_[0];
    $msg =~ s/\s*$//;
    push @{$dehs_tags{'messages'}}, $msg;
}

sub dehs_warn ($)
{
    my $warning = $_[0];
    $warning =~ s/\s*$//;
    push @{$dehs_tags{'warnings'}}, $warning;
}

sub dehs_die ($)
{
    my $msg = $_[0];
    $msg =~ s/\s*$//;
    %dehs_tags = ('errors' => "$msg");
    $dehs_end_output=1;
    dehs_output;
    exit 1;
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
		    status messages warnings errors)) {
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
