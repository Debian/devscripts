#! /usr/bin/perl -w

# debchange: update the debian changelog using your favorite visual editor
# For options, see the usage message below.
#
# When creating a new changelog section, if either of the environment
# variables DEBEMAIL or EMAIL is set, debchange will use this as the
# uploader's email address (with the former taking precedence), and if
# DEBFULLNAME is set, it will use this as the uploader's full name.
# Otherwise, it will take the standard values for the current user or,
# failing that, just copy the values from the previous changelog entry.
#
# Originally by Christoph Lameter <clameter@debian.org>
# Modified extensively by Julian Gilbey <jdg@debian.org>
#
# Copyright 1999-2003 by Julian Gilbey 
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

use 5.008;  # We're using PerlIO layers
use strict;
use open ':utf8';  # changelogs are written with UTF-8 encoding
use filetest 'access';  # use access rather than stat for -w
use Encode 'decode_utf8';  # for checking whether user names are valid
use Getopt::Long;
use File::Copy;
use File::Basename;
use Cwd;

# Predeclare functions
sub fatal($);

# And global variables
my $progname = basename($0);
my $modified_conf_msg;
my %env;
my $CHGLINE;  # used by the format O section at the end

sub usage () {
    print <<"EOF";
Usage: $progname [options] [changelog entry]
Options:
  -i, --increment
         Increase the Debian release number, adding a new changelog entry
  -a, --append
         Append a new entry to the current changelog
  -e, --edit
         Don't change version number or add a new changelog entry, just
	 update the changelog's stamp and open up an editor
  -r, --release
         Update the changelog timestamp. If the distribution is set to
         "UNRELEASED", change it to unstable (or another distribution as
	 specified by --distribution).
  -v <version>, --newversion=<version>
         Add a new changelog entry with version number specified
  -b, --force-bad-version
         Force a version to be less than the current one (e.g. when
         backporting)
  -n, --nmu
         Increment the Debian release number for a non-maintainer upload
  --closes nnnnn[,nnnnn,...]
         Add entries for closing these bug numbers,
         getting bug titles from the BTS (bug-tracking system, bugs.debian.org)
  --[no]query
         [Don\'t] try contacting the BTS to get bug titles
  -d, --fromdirname
         Add a new changelog entry with version taken from the directory name
  -p, --preserve
         Preserve the directory name
  --no-preserve
         Do not preserve the directory name (default)
  -D, --distribution <dist>
         Use the specified distribution in the new changelog entry, if any
  -u, --urgency <urgency>
         Use the specified urgency in the new changelog entry, if any
  -c, --changelog <changelog>
         Specify the name of the changelog to use in place of debian/changelog
         No directory traversal or checking is performed in this case.
  --news
         Specify that debian/NEWS is to be edited; cannot be used
         with --changelog
  --check-dirname-level N
         How much to check directory names:
         N=0   never
         N=1   only if program changes directory (default)
         N=2   always
  --check-dirname-regex REGEX
         What constitutes a matching directory name; REGEX is
         a Perl regular expression; the string \`PACKAGE\' will
         be replaced by the package name; see manpage for details
         (default: 'PACKAGE(-.*)?')
  --no-conf, --noconf
         Don\'t read devscripts config files; must be the first option given
  --release-heuristic log|changelog
         Select heuristic used to determine if a package has been released.
	 (default: log)
  --help, -h
         Display this help message and exit
  --version
         Display version information
  At most one of -a, -i and -v (or their long equivalents) may be used.
  With no options, one of -i or -a is chosen by looking for a .upload
  file in the parent directory and checking its contents.

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

sub version () {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999-2003 by Julian Gilbey, all rights reserved.
Based on code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

# Start by setting default values
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.*)?';
my $opt_p = 0;
my $opt_query = 1;
my $opt_release_heuristic = 'log';

# Next, read configuration files and then command line
# The next stuff is boilerplate

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DEBCHANGE_PRESERVE' => 'no',
		       'DEBCHANGE_QUERY_BTS' => 'yes',
		       'DEVSCRIPTS_CHECK_DIRNAME_LEVEL' => 1,
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.*)?',
		       'DEBCHANGE_RELEASE_HEURISTIC' => 'log',
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
    $config_vars{'DEBCHANGE_PRESERVE'} =~ /^(yes|no)$/
	or $config_vars{'DEBCHANGE_PRESERVE'}='no';
    $config_vars{'DEBCHANGE_QUERY_BTS'} =~ /^(yes|no)$/
	or $config_vars{'DEBCHANGE_QUERY_BTS'}='yes';
    $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} =~ /^[012]$/
	or $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'}=1;
    $config_vars{'DEBCHANGE_RELEASE_HEURISTIC'} =~ /^(log|changelog)$/
	or $config_vars{'DEBCHANGE_RELEASE_HEURISTIC'}='log';

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $opt_p = $config_vars{'DEBCHANGE_PRESERVE'} eq 'yes' ? 1 : 0;
    $opt_query = $config_vars{'DEBCHANGE_QUERY_BTS'} eq 'no' ? 0 : 1;
    $check_dirname_level = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
    $check_dirname_regex = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_REGEX'};
    $opt_release_heuristic = $config_vars{'DEBCHANGE_RELEASE_HEURISTIC'};
}

# We use bundling so that the short option behaviour is the same as
# with older debchange versions.
my ($opt_help, $opt_version);
my ($opt_i, $opt_a, $opt_e, $opt_r, $opt_v, $opt_b, $opt_d, $opt_D, $opt_u, $opt_n, $opt_c, @closes);
my ($opt_news);
my ($opt_ignore, $opt_level, $opt_regex, $opt_noconf);
$opt_u = 'low';

Getopt::Long::Configure('bundling');
GetOptions("help|h" => \$opt_help,
	   "version" => \$opt_version,
	   "i|increment" => \$opt_i,
	   "a|append" => \$opt_a,
	   "e|edit" => \$opt_e,
	   "r|release" => \$opt_r,
	   "v|newversion=s" => \$opt_v,
	   "b|force-bad-version" => \$opt_b,
	   "d|fromdirname" => \$opt_d,
	   "p" => \$opt_p,
	   "preserve!" => \$opt_p,
           "D|distribution=s" => \$opt_D,
           "u|urgency=s" => \$opt_u,
	   "n|nmu" => \$opt_n,
	   "query!" => \$opt_query,
	   "closes=s" => \@closes,
	   "c|changelog=s" => \$opt_c,
	   "news" => \$opt_news,
	   "ignore-dirname" => \$opt_ignore,
	   "check-dirname-level=s" => \$opt_level,
	   "check-dirname-regex=s" => \$opt_regex,
	   "noconf" => \$opt_noconf,
	   "no-conf" => \$opt_noconf,
	   "release-heuristic=s" => \$opt_release_heuristic,
	   )
    or die "Usage: $progname [options] [changelog entry]\nRun $progname --help for more details\n";

if ($opt_noconf) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}
if ($opt_help) { usage; exit 0; }
if ($opt_version) { version; exit 0; }

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

if (defined $opt_regex) { $check_dirname_regex = $opt_regex; }

fatal "Only one of -c/--changelog and --news is allowed; try $progname --help for more help"
    if $opt_c and $opt_news;

fatal "--closes should not be used with --news; put bug numbers in the changelog not the NEWS file"
    if $opt_news && @closes;
    
my $changelog_path = $opt_c || $ENV{'CHANGELOG'} || 'debian/changelog';
if ($opt_news) { $changelog_path = "debian/NEWS"; }
if ($changelog_path ne 'debian/changelog' and $changelog_path ne 'debian/NEWS') {
    $check_dirname_level = 0;
}

@closes = split(/,/, join(',', @closes));
map { s/^\#//; } @closes;  # remove any leading # from bug numbers

# Only allow at most one non-help option
fatal "Only one of -a, -i, -e, -r, -v, -d is allowed; try $progname --help for more help"
    if ($opt_i?1:0) + ($opt_a?1:0) + ($opt_e?1:0) + ($opt_r?1:0) + ($opt_v?1:0) + ($opt_d?1:0) > 1;

# We'll process the rest of the command line later.

# Look for the changelog
my $chdir = 0;
if ($changelog_path eq 'debian/changelog') {
    until (-f 'debian/changelog') {
	$chdir = 1;
	chdir '..' or die "$progname: can't chdir ..: $!\n";
	if (cwd() eq '/') {
	    die "$progname: cannot find debian/changelog anywhere!\nAre you in the source code tree?\n";
	}
    }

    # Can't write, so stop now.
    if (! -w 'debian/changelog')
    {
        die "$progname: debian/changelog is not writable!\n";
    }
}
else {
    unless (-f $changelog_path) {
	die "$progname: cannot find $changelog_path!\nAre you in the correct directory?\n";
    }

    # Can't write, so stop now.
    if (! -w $changelog_path)
    {
        die "$progname: $changelog_path is not writable!\n";
    }
}

#####

# Find the current version number etc.
my %changelog;
open PARSED, qq[dpkg-parsechangelog -l"$changelog_path" | ]
    or fatal "Cannot execute dpkg-parsechangelog: $!";
my $last;
while (<PARSED>) {
    chomp;
    if (/^(\S+):\s(.+?)\s*$/) { $changelog{$1}=$2; $last=$1; }
    elsif (/^(\S+):\s$/) { $changelog{$1}=''; $last=$1; }
    elsif (/^\s\.$/) { $changelog{$last}.="\n"; }
    elsif (/^\s(.+)$/) { $changelog{$last}.="$1\n"; }
    else {
	fatal "Don't understand dpkg-parsechangelog output: $_";
    }
}

close PARSED
    or fatal "Problem executing dpkg-parsechangelog: $!";
if ($?) { fatal "dpkg-parsechangelog failed!" }

# Now we've read the changelog, set some variables and then
# let's check the directory name is sensible
fatal "No package name in changelog!"
    unless exists $changelog{'Source'};
my $PACKAGE = $changelog{'Source'};
fatal "No version number in changelog!"
    unless exists $changelog{'Version'};
my $VERSION=$changelog{'Version'};
fatal "No maintainer in changelog!"
    unless exists $changelog{'Maintainer'};
my ($MAINTAINER,$EMAIL) = ($changelog{'Maintainer'} =~ /^([^<]+) <(.*)>/);
fatal "No distribution in changelog!"
    unless exists $changelog{'Distribution'};
my $DISTRIBUTION=$changelog{'Distribution'};
fatal "No changes in changelog!"
    unless exists $changelog{'Changes'};
my $CHANGES=$changelog{'Changes'};

# Is the directory name acceptable?
if ($check_dirname_level ==  2 or
    ($check_dirname_level == 1 and $chdir)) {
    my $re = $check_dirname_regex;
    $re =~ s/PACKAGE/\\Q$PACKAGE\\E/g;
    my $gooddir;
    if ($re =~ m%/%) { $gooddir = eval "cwd() =~ /^$re\$/;"; }
    else { $gooddir = eval "basename(cwd()) =~ /^$re\$/;"; }
    
    if (! $gooddir) {
	my $pwd = cwd();
	die <<"EOF";
$progname: found debian/changelog for package $PACKAGE in the directory
  $pwd
but this directory name does not match the package name according to the
regex  $check_dirname_regex.

To run $progname on this package, see the --check-dirname-level and
--check-dirname-regex options; run $progname --help for more info.
EOF
    }
}


# Clean up after old versions of debchange
if (-f "debian/RELEASED") {
    unlink("debian/RELEASED");
}

if ( -e "$changelog_path.dch" ) {
    fatal "The backup file $changelog_path.dch already exists --\n" .
		  "please move it before trying again";
}


# Is this a native Debian package, i.e., does it have a - in the
# version number?
(my $EPOCH) = ($VERSION =~ /^(\d+):/);
(my $SVERSION=$VERSION) =~ s/^\d+://;
(my $UVERSION=$SVERSION) =~ s/-[^-]*$//;

# Check, sanitise and decode these environment variables
check_env_utf8('DEBFULLNAME');
check_env_utf8('DEBEMAIL');
check_env_utf8('EMAIL');

if (exists $env{'DEBEMAIL'} and $env{'DEBEMAIL'} =~ /^(.*)\s+<(.*)>$/) {
    $env{'DEBFULLNAME'} = $1 unless exists $env{'DEBFULLNAME'};
    $env{'DEBEMAIL'} = $2;
}
if (! exists $env{'DEBEMAIL'} or ! exists $env{'DEBFULLNAME'}) {
    if (exists $env{'EMAIL'} and $env{'EMAIL'} =~ /^(.*)\s+<(.*)>$/) {
	$env{'DEBFULLNAME'} = $1 unless exists $env{'DEBFULLNAME'};
	$env{'EMAIL'} = $2;
    }
}

# Now use the gleaned values to detemine our MAINTAINER and EMAIL values
if (exists $env{'DEBFULLNAME'}) {
    $MAINTAINER = $env{'DEBFULLNAME'};
} else {
    my @pw = getpwuid $<;
    if (defined($pw[6])) {
	if (my $pw = decode_utf8($pw[6])) {
	    $pw =~ s/,.*//;
	    $MAINTAINER = $pw;
	} else {
	    warn "$progname warning: passwd full name field for uid $<\nis not UTF-8 encoded; ignoring\n";
	}
    }
}
# Otherwise, $MAINTAINER retains its default value of the last changelog entry

# Email is easier
if (exists $env{'DEBEMAIL'}) { $EMAIL = $env{'DEBEMAIL'}; }
elsif (exists $env{'EMAIL'}) { $EMAIL = $env{'EMAIL'}; }
else {
    my $addr;
    if (open MAILNAME, '/etc/mailname') {
	chomp($addr = <MAILNAME>);
	close MAILNAME;
    }
    if (!$addr) {
	chomp($addr = `hostname --fqdn 2>/dev/null`);
	$addr = undef if $?;
    }
    if ($addr) {
	my $user = getpwuid $<;
	if (!$user) {
	    $addr = undef;
	}
	else {
	    $addr = "$user\@$addr";
	}
    }
    $EMAIL = $addr if $addr;
}
# Otherwise, $EMAIL retains its default value of the last changelog entry

#####

# Do we need to generate "closes" entries?

my @closes_text = ();
my $warnings = 0;
if (@closes and $opt_query) { # and we have to query the BTS
    if (system('command -v wget >/dev/null 2>&1') >> 8 != 0) {
	warn "$progname warning: wget not installed, so cannot query the bug-tracking system\n";
	$opt_query=0;
	$warnings++;
	# This will now go and execute the "if (@closes and ! $opt_query)" code
    }
    else
    {
	my %bugs;
	my $lastbug;

	my $bugs = `wget -q -O - 'http://bugs.debian.org/cgi-bin/pkgreport.cgi?src=$PACKAGE'`;
	if ($? >> 8 != 0) {
	    warn "$progname warning: wget failed, so cannot query the bug-tracking system\n";
	    $opt_query=0;
	    $warnings++;
	    # This will now go and execute the "if (@closes and ! $opt_query)" code
	}

	foreach (split /\n/, $bugs) {
	    if (m%<a href=\"bugreport.cgi\?bug=([0-9]*).*?>\#\1: (.*?)</a>%) {
		$bugs{$1} = [$2];
		$lastbug=$1;
	    }
	    elsif (defined $lastbug and
		   m%<a href=\"pkgreport.cgi\?pkg=([a-z0-9\+\-\.]*)%) {
		push @{$bugs{$lastbug}}, $1
		    if exists $bugs{$lastbug};
		$lastbug = undef;
	    }
	}

	foreach my $close (@closes) {
	    if (exists $bugs{$close}) {
		my ($title,$pkg) = @{$bugs{$close}};
		$title =~ s/^($pkg|$PACKAGE): //;
		push @closes_text, "Closes: \#$close: $title\n";
	    }
	    else { # not our package, or wnpp
		my $bug = `wget -q -O - 'http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=$close'`;
		if ($? >> 8 != 0) {
		    warn "$progname warning: unknown bug \#$close does not belong to $PACKAGE,\n  disabling closing changelog entry\n";
		    $warnings++;
		    push @closes_text, "Closes?? \#$close: UNKNOWN BUG IN WRONG PACKAGE!!\n";
                } else {
		    my ($bugtitle) = ($bug =~ m%<TITLE>.*?\#$close - (.*?)</TITLE>%);
		    my ($bugpkg) = ($bug =~ m%<a href=\"pkgreport.cgi\?pkg=([a-z0-9\+\-\.]*)%);
		    $bugpkg ||= '?';
		    my ($bugsrcpkg) = ($bug =~ m%<a href=\"pkgreport.cgi\?src=([a-z0-9\+\-\.]*)%);
		    $bugsrcpkg ||= '?';
		    if ($bugsrcpkg eq $PACKAGE) {
			warn "$progname warning: bug \#$close appears to be already archived,\n  disabling closing changelog entry\n";
			$warnings++;
			push @closes_text, "Closes?? \#$close: ALREADY ARCHIVED?  $bugtitle!!\n";
		    }
		    elsif ($bugpkg eq 'wnpp') {
			if ($bugtitle =~ /(^(O|RFA|ITA): )/) {
			    push @closes_text, "New maintainer. (Closes: \#$close: $bugtitle)\n";
			}
			elsif  ($bugtitle =~ /(^(RFP|ITP): )/) {
			    push @closes_text, "Initial release. (Closes: \#$close: $bugtitle)\n";
			}
		    }
		    else {
			warn "$progname warning: bug \#$close belongs to package $bugpkg (src $bugsrcpkg),\n  not to $PACKAGE: disabling closing changelog entry\n";
			$warnings++;
			push @closes_text, "Closes?? \#$close: WRONG PACKAGE!!  $bugtitle\n";
		    }
		}
	    }
        }
   }
}

if (@closes and ! $opt_query) { # and we don't have to query the BTS
    foreach my $close (@closes) {
	unless ($close =~ /^\d{3,}$/) {
	    warn "$progname warning: Bug number $close is invalid; ignoring\n";
	    $warnings++;
	    next;
	}
	push @closes_text, "Closes: \#$close: \n";
    }
}


# Get a possible changelog entry from the command line
my $TEXT=decode_utf8(join(' ', @ARGV));
if (@ARGV and ! $TEXT) {
    warn "$progname warning: command-line changelog entry not UTF-8 encoded; ignoring\n";
    $TEXT='';
}

# Get the date
chomp(my $DATE=`822-date`);

# Are we going to have to figure things out for ourselves?
if (! $opt_i && ! $opt_v && ! $opt_d && ! $opt_a && ! $opt_e && ! $opt_r) {
    # Yes, we are
    if ($opt_release_heuristic eq 'log') {
        my @UPFILES = glob("../$PACKAGE\_$SVERSION\_*.upload");
        if (@UPFILES > 1) {
	    fatal "Found more than one appropriate .upload file!\n" .
		          "Please use an explicit -a, -i or -v option instead.";
        }
        elsif (@UPFILES == 0) { $opt_a = 1 }
        else {
	    open UPFILE, "<${UPFILES[0]}"
	        or fatal "Couldn't open .upload file for reading: $!\n" .
			    "Please use an explicit -a, -i or -v option instead.";
	    while (<UPFILE>) {
	        if (m%^(s|Successfully uploaded) (/.*/)?\Q$PACKAGE\E\_\Q$SVERSION\E\_[\w\-]+\.changes %) {
		   $opt_i = 1;
		   last;
	        }
	    }
	    close UPFILE
	        or fatal "Problems experienced reading .upload file: $!\n" .
			    "Please use an explicit -a, -i or -v option instead.";
	    if (! $opt_i) {
	        warn "$progname warning: A successful upload of the current version was not logged\n" .
		    "in the upload log file; adding log entry to current version.";
	        $opt_a = 1;
	    }
        }
    }
    elsif ($opt_release_heuristic eq 'changelog') {
	if ($changelog{Distribution} eq 'UNRELEASED') {
		$opt_a = 1;
	}
	else {
		$opt_i = 1;
	}
    }
    else {
	fatal "bad release heuristic value";
    }
}

# Open in anticipation....
open S, $changelog_path or fatal "Cannot open changelog: $!";
open O, ">$changelog_path.dch"
    or fatal "Cannot write to temporary file: $!";
# Turn off form feeds; taken from perlform
select((select(O), $^L = "")[0]);

# Note that we now have to remove it
my $tmpchk=1;
my ($NEW_VERSION, $NEW_SVERSION, $NEW_UVERSION);
my $line;

if ($opt_i || $opt_n || $opt_v || $opt_d) {
    # Check that a given explicit version number is sensible.
    if ($opt_v || $opt_d) {
	if($opt_v) {
	    $NEW_VERSION=$opt_v;
	} else {
	    my $pwd = cwd();
	    # The directory name should be <package>-<version>
	    my $version_chars = '0-9a-zA-Z+\.';
	    $version_chars .= ':' if defined $EPOCH;
	    $version_chars .= '\-' if $UVERSION ne $SVERSION;
	    if ($pwd =~ m%.*/\Q$PACKAGE\E-([0-9][$version_chars]*)$%) {
		$NEW_VERSION=$1;
		if ($NEW_VERSION eq $UVERSION) {
		    # So it's a Debian-native package
		    if ($SVERSION eq $UVERSION) {
			fatal "New version taken from directory ($NEW_VERSION) is equal to\n" .
			    "the current version number ($UVERSION)!";
		    }
		    # So we just increment the Debian revision
		    warn "$progname warning: Incrementing Debian revision without altering\nupstream version number.\n";
		    $VERSION =~ /^(.*?)([a-yA-Y][a-zA-Z]*|\d*)$/;
		    my $end = $2;
		    if ($end eq '') {
			fatal "Cannot determine new Debian revision; please use -v option!";
		    }
		    $end++;
		    $NEW_VERSION="$1$end";
		} else {
		    $NEW_VERSION = "$EPOCH:$NEW_VERSION" if defined $EPOCH;
		    $NEW_VERSION .= "-1";
		}
	    } else {
		fatal "The directory name must be <package>-<version> for -d to work!\n" .
		    "No underscores allowed!";
	    }
	    # Don't try renaming the directory in this case!
	    $opt_p=1;
	}

	if (system("dpkg --compare-versions $VERSION lt $NEW_VERSION" .
		  " 2>/dev/null 1>&2")) {
	    if ($opt_b) {
		warn "$progname warning: new version ($NEW_VERSION) is less than\n" .
		    "the current version number ($VERSION).\n";
	    } else {
		fatal "New version specified ($NEW_VERSION) is less than\n" .
		    "the current version number ($VERSION)!  Use -b to force.";
	    }
	}

	($NEW_SVERSION=$NEW_VERSION) =~ s/^\d+://;
	($NEW_UVERSION=$NEW_SVERSION) =~ s/-[^-]*$//;
    }

    # We use the following criteria for the version and release number:
    # the last component of the version number is used as the
    # release number.  If this is not a Debian native package, then the
    # upstream version number is everything up to the final '-', not
    # including epochs.

    if (! $NEW_VERSION) {
	if ($VERSION =~ /(.*?)([a-yA-Y][a-zA-Z]*|\d+)$/i) {
	    my $end=$2;
            my $start=$1;
            # If it's not already an NMU make it so
            # otherwise we can be safe if we behave like dch -i
	    if ($opt_n and not $start =~ /\.$/) {
	    	$end += 0.1;
            } else {
                $end++;
            }
            $NEW_VERSION = "$start$end";
	    ($NEW_SVERSION=$NEW_VERSION) =~ s/^\d+://;
	    ($NEW_UVERSION=$NEW_SVERSION) =~ s/-[^-]*$//;
	} else {
	    fatal "Error parsing version number: $VERSION";
	}
    }

    my $distribution = $opt_D || (($opt_release_heuristic eq 'changelog') ? "UNRELEASED" : $DISTRIBUTION);
    print O "$PACKAGE ($NEW_VERSION) $distribution; ",
        "urgency=$opt_u\n\n";

    if ($opt_n && ! $opt_news) {
        print O "  * Non-maintainer upload.\n";
        $line = 1;
    }
    if (@closes_text or $TEXT) {
	format_line($_, 1) foreach @closes_text;
	format_line($TEXT, 1) if length $TEXT;
    } elsif ($opt_news) {
	print O "  \n";
    } else {
	print O "  * \n";
    }
    $line += 3;
    print O "\n -- $MAINTAINER <$EMAIL>  $DATE\n\n";

    # Copy the old changelog file to the new one
    local $/ = undef;
    print O <S>;
}
elsif ($opt_a) {
    # This means we just have to generate a new * entry in changelog
    # and if a multi-developer changelog is detected, add developer names.
    $NEW_VERSION=$VERSION;
    $NEW_SVERSION=$SVERSION;
    $NEW_UVERSION=$UVERSION;

    # Read and discard maintainer line, and see who made the
    # last entry.
    $line=-1;
    my $lastmaint;
    while (<S>) {
	$line++;
	if (/^ --\s+([^<]+)\s+/) {
	    $lastmaint=$1;
	    last;
	}
    }

    # Munging of changelog for multimaintainer mode.
    my $multimaint=0;
    if (! $opt_news) {
	my $lastmultimaint;
	
	# Parse the changlog for multi-maintainer maintainer lines of
	# the form [ Full Name ] and record the last of these.
	while ($CHANGES=~/.*\n^\s+\[\s+([^]]+)\s+]\s*$/mg) {
	    $lastmultimaint=$1;
	}

	if ((! defined $lastmultimaint && defined $lastmaint &&
	     $lastmaint ne $MAINTAINER)
	    ||
	    (defined $lastmultimaint && $lastmultimaint ne $MAINTAINER)
	   ) {
	    $multimaint=1;
	
	    if (! $lastmultimaint) {
	        # Add a multi-maintainer header to the top of the existing
	        # changelog.
	        my $newchanges='';
	        $CHANGES=~s/^(  .+)$/  [ $lastmaint ]\n$1/m;
	    }
	}
    }
    
    # The first lines are as we have already found
    print O $CHANGES;

    # Add a multi-maintainer header.
    if ($multimaint) {
	print O "\n  [ $MAINTAINER ]\n";
	$line+=2;
    }

    if (@closes_text or $TEXT) {
	format_line($_, 0) foreach @closes_text;
	format_line($TEXT, 0) if length $TEXT;
    } elsif ($opt_news) {
	print O "\n  \n";
	$line++;
    } else {
	print O "  * \n";
    }

    print O "\n -- $MAINTAINER <$EMAIL>  $DATE\n";

    # Copy the rest of the changelog file to new one
    # Slurp the rest....
    local $/ = undef;
    print O <S>;
}
else { # $opt_e or $opt_r
    if ($opt_r) {
        # Change the distribution from UNRELEASED for release.
	my $distribution = $opt_D || "unstable";
	$CHANGES=~s/(\([^)]+\)\s+)([^;]+);/$1$distribution;/;
    }
    
    # We don't do any fancy stuff with respect to versions or adding
    # entries, we just update the timestamp and open the editor
    
    print O $CHANGES;

    print O "\n -- $MAINTAINER <$EMAIL>  $DATE\n";

    # Copy the rest of the changelog file to the new one
    $line=-1;
    while (<S>) { $line++; last if /^ --/; }
    # Slurp the rest...
    local $/ = undef;
    print O <S>;

    # Set the start-line to 1, as we don't know what they want to edit
    $line=1;
}

close S or fatal "Error closing $changelog_path: $!";
close O or fatal "Error closing temporary changelog: $!";

if ($warnings) {
    if ($warnings>1) {
	warn "$progname: Did you see those $warnings warnings?  Press RETURN to continue...\n";
    } else {
	warn "$progname: Did you see that warning?  Press RETURN to continue...\n";
    }
    my $garbage = <STDIN>;
}

# Now Run the Editor; always run if doing "closes" to give a chance to check
if (! $TEXT or @closes_text) {
    my $mtime = (stat("$changelog_path.dch"))[9];
    defined $mtime or fatal
	"Error getting modification time of temporary changelog: $!";

    system("sensible-editor +$line $changelog_path.dch") == 0 or
    fatal "Error editing the changelog";

    if (! @closes_text) { # so must have a changelog added by hand
	my $newmtime = (stat("$changelog_path.dch"))[9];
	defined $newmtime or fatal
	    "Error getting modification time of temporary changelog: $!";
	if ($mtime == $newmtime) {
	    warn "$progname: Changelog unmodified; exiting.\n";
	    exit 0;
	}
    }
}

copy("$changelog_path.dch","$changelog_path") or
    fatal "Couldn't replace changelog with new changelog: $!";

# Now find out what the new package version number is if we need to
# rename the directory

if ((cwd() =~ m%/\Q$PACKAGE\E-\Q$UVERSION\E$%) && !$opt_p) {
    # Find the current version number etc.
    my ($new_version, $new_sversion, $new_uversion);
    open PARSED, "dpkg-parsechangelog |"
	or fatal "Cannot execute dpkg-parsechangelog: $!";
    while (<PARSED>) {
	if (/^Version:\s(.+?)\s*$/) { $new_version=$1; }
    }

    close PARSED
	or fatal "Problem executing dpkg-parsechangelog: $!";
    if ($?) { fatal "dpkg-parsechangelog failed!" }

    fatal "No version number in changelog!"
	unless defined $new_version;

    # Is this a native Debian package, i.e., does it have a - in the
    # version number?
    $new_version =~ s/^\d+://;  # remove epoch
    ($new_uversion=$new_version) =~ s/-[^-]*$//;  # remove revision

    if ($new_uversion ne $UVERSION) {
	# Then we rename the directory
	if (move(cwd(), "../$PACKAGE-$new_uversion")) {
	    warn "$progname warning: your current directory has been renamed to:\n../$PACKAGE-$new_uversion\n";
	} else {
	    warn "$progname warning: Couldn't rename directory: $!";
	}
    }
}

exit 0;


# Format for standard Debian changelogs
format CHANGELOG =
  * ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    $CHGLINE
 ~~ ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    $CHGLINE
.
# Format for NEWS files.
format NEWS =
  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    $CHGLINE
~~^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    $CHGLINE
.

my $linecount=0;
sub format_line {
    $CHGLINE=shift;
    my $newentry=shift;

    print O "\n" if $opt_news && ! ($newentry || $linecount);
    $linecount++;
    my $f=select(O);
    if ($opt_news) {
        $~='NEWS';
    }
    else {
        $~='CHANGELOG';
    }
    write O;
    select $f;
}

sub BEGIN {
    # Initialise the variable
    $tmpchk=0;
}

sub END {
    if ($tmpchk) {
	unlink "$changelog_path.dch" or
	    warn "$progname warning: Could not remove $changelog_path.dch";
	unlink "$changelog_path.dch~";  # emacs backup file
    }
}

sub fatal($) {
    my ($pack,$file,$line);
    ($pack,$file,$line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    die $msg;
}

# Is the environment variable valid or not?
sub check_env_utf8 {
    my $envvar = $_[0];

    if (exists $ENV{$envvar} and $ENV{$envvar} ne '') {
	if (! decode_utf8($ENV{$envvar})) {
	    warn "$progname warning: environment variable $envvar not UTF-8 encoded; ignoring\n";
	} else {
	    $env{$envvar} = decode_utf8($ENV{$envvar});
	}
    }
}
