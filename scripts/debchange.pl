#! /usr/bin/perl

# debchange: update the debian changelog using your favorite visual editor
# For options, see the usage message below.
#
# When creating a new changelog section, if either of the environment
# variables DEBEMAIL or EMAIL is set, debchange will use this as the
# uploader's email address (with the former taking precedence), and if
# DEBFULLNAME or NAME is set, it will use this as the uploader's full name.
# Otherwise, it will take the standard values for the current user or,
# failing that, just copy the values from the previous changelog entry.
#
# Originally by Christoph Lameter <clameter@debian.org>
# Modified extensively by Julian Gilbey <jdg@debian.org>
#
# Copyright 1999-2005 by Julian Gilbey
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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

use 5.008;  # We're using PerlIO layers
use strict;
use warnings;
use open ':utf8';  # changelogs are written with UTF-8 encoding
use filetest 'access';  # use access rather than stat for -w
# for checking whether user names are valid and making format() behave
use Encode qw/decode_utf8 encode_utf8/;
use Getopt::Long qw(:config gnu_getopt);
use File::Copy;
use File::Basename;
use Cwd;
use Dpkg::Compression;
use Dpkg::Vendor qw(get_current_vendor);
use lib '/usr/share/devscripts';
use Devscripts::Debbugs;

# Predeclare functions
sub fatal($);
my $warnings = 0;

# And global variables
my $progname = basename($0);
my $modified_conf_msg;
my %env;
my $CHGLINE;  # used by the format O section at the end

my $lpdc_broken;

sub have_lpdc {
    return ($lpdc_broken ? 0 : 1) if defined $lpdc_broken;
    eval {
	require Parse::DebControl;
    };

    if ($@) {
	if ($@ =~ m%^Can\'t locate Parse/DebControl%) {
	    $lpdc_broken="the libparse-debcontrol-perl package is not installed";
	} else {
	    $lpdc_broken="couldn't load Parse::DebControl: $@";
	}
    }
    else { $lpdc_broken=''; }
    return $lpdc_broken ? 0 : 1;
}

my $debian_distro_info;
sub get_debian_distro_info {
    return $debian_distro_info if defined $debian_distro_info;
    eval {
	require Debian::DistroInfo;
    };
    if ($@) {
	printf "libdistro-info-perl is not installed, Debian release names "
	       . "are not known.\n";
	$debian_distro_info = 0;
    } else {
	$debian_distro_info = DebianDistroInfo->new();
    }
    return $debian_distro_info;
}

my $ubuntu_distro_info;
sub get_ubuntu_distro_info {
    return $ubuntu_distro_info if defined $ubuntu_distro_info;
    eval {
	require Debian::DistroInfo;
    };
    if ($@) {
	printf "libdistro-info-perl is not installed, Ubuntu release names "
	       . "are not known.\n";
	$ubuntu_distro_info = 0;
    } else {
	$ubuntu_distro_info = UbuntuDistroInfo->new();
    }
    return $ubuntu_distro_info;
}

sub get_ubuntu_devel_distro {
    my $ubu_info = get_ubuntu_distro_info();
    if ($ubu_info == 0 or !$ubu_info->devel()) {
	warn "$progname warning: Unable to determine the current Ubuntu "
	     . "development release. Using UNRELEASED instead.\n";
	return 'UNRELEASED';
    } else {
	return $ubu_info->devel();
    }
}

sub usage () {
    print <<"EOF";
Usage: $progname [options] [changelog entry]
Options:
  -a, --append
         Append a new entry to the current changelog
  -i, --increment
         Increase the Debian release number, adding a new changelog entry
  -v <version>, --newversion=<version>
         Add a new changelog entry with version number specified
  -e, --edit
         Don't change version number or add a new changelog entry, just
         update the changelog's stamp and open up an editor
  -r, --release
         Update the changelog timestamp. If the distribution is set to
         "UNRELEASED", change it to unstable (or another distribution as
         specified by --distribution).
  --force-save-on-release
         When --release is used and an editor opened to allow inspection
         of the changelog, require the user to save the changelog their
         editor opened.  Otherwise, the original changelog will not be
         modified. (default)
  --no-force-save-on-release
         Do not do so. Note that a dummy changelog entry may be supplied
         in order to achieve the same effect - e.g. $progname --release ""
         The entry will not be added to the changelog but its presence will
         suppress the editor
  --create
         Create a new changelog (default) or NEWS file (with --news) and
         open for editing
  --empty
         When creating a new changelog, don't add any changes to it
         (i.e. only include the header and trailer lines)
  --package <package>
         Specify the package name when using --create (optional)
  --auto-nmu
         Attempt to intelligently determine whether a change to the
         changelog represents an NMU (default)
  --no-auto-nmu
         Do not do so
  -n, --nmu
         Increment the Debian release number for a non-maintainer upload
  --bin-nmu
         Increment the Debian release number for a binary non-maintainer upload
  -q, --qa
         Increment the Debian release number for a Debian QA Team upload
  -R, --rebuild
         Increment the Debian release number for an Ubuntu no-change rebuild
  -s, --security
         Increment the Debian release number for a Debian Security Team upload
  --team
         Increment the Debian release number for a team upload
  -U, --upstream
         Increment the Debian release number without any appended derivative
         distribution name
  --bpo
         Increment the Debian release number for a Backports.org upload
         to "squeeze-backports"
  -l, --local <suffix>
         Add a suffix to the Debian version number for a local build
  -b, --force-bad-version
         Force a version to be less than the current one (e.g., when
         backporting)
  --allow-lower-version <pattern>
         Allow a version to be less than the current one (e.g., when
         backporting) if it matches the specified pattern
  --force-distribution
         Force the provided distribution to be used, even if it doesn't match
         the list of known distributions
  --closes nnnnn[,nnnnn,...]
         Add entries for closing these bug numbers,
         getting bug titles from the BTS (bug-tracking system, bugs.debian.org)
  --[no]query
         [Don\'t] try contacting the BTS to get bug titles (default: do query)
  -d, --fromdirname
         Add a new changelog entry with version taken from the directory name
  -p, --preserve
         Preserve the directory name
  --no-preserve
         Do not preserve the directory name (default)
  --vendor <vendor>
         Override the distributor ID from dpkg-vendor.
  -D, --distribution <dist>
         Use the specified distribution in the changelog entry being edited
  -u, --urgency <urgency>
         Use the specified urgency in the changelog entry being edited
  -c, --changelog <changelog>
         Specify the name of the changelog to use in place of debian/changelog
         No directory traversal or checking is performed in this case.
  --news <newsfile>
         Specify that the newsfile (default debian/NEWS) is to be edited
  --[no]multimaint
         When appending an entry to a changelog section (-a), [do not]
         indicate if multiple maintainers are now involved (default: do so)
  --[no]multimaint-merge
         When appending an entry to a changelog section, [do not] merge the
         entry into an existing changelog section for the current author.
         (default: do not)
  -m, --maintmaint
         Don\'t change (maintain) the maintainer details in the changelog entry
  -M, --controlmaint
         Use maintainer name and email from the debian/control Maintainer field
  -t, --mainttrailer
         Don\'t change (maintain) the trailer line in the changelog entry; i.e.
         maintain the maintainer and date/time details
  --check-dirname-level N
         How much to check directory names:
         N=0   never
         N=1   only if program changes directory (default)
         N=2   always
  --check-dirname-regex REGEX
         What constitutes a matching directory name; REGEX is
         a Perl regular expression; the string \`PACKAGE\' will
         be replaced by the package name; see manpage for details
         (default: 'PACKAGE(-.+)?')
  --no-conf, --noconf
         Don\'t read devscripts config files; must be the first option given
  --release-heuristic log|changelog
         Select heuristic used to determine if a package has been released.
         (default: changelog)
  --help, -h
         Display this help message and exit
  --version
         Display version information
  At most one of -a, -i, -e, -r, -v, -d, -n, --bin-nmu, -q, --qa, -R, -s,
  --team, --bpo, -l (or their long equivalents) may be used.
  With no options, one of -i or -a is chosen by looking at the release
  specified in the changelog.

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
my $check_dirname_regex = 'PACKAGE(-.+)?';
my $opt_p = 0;
my $opt_query = 1;
my $opt_release_heuristic = 'changelog';
my $opt_multimaint = 1;
my $opt_multimaint_merge = 0;
my $opt_tz = undef;
my $opt_t = '';
my $opt_allow_lower = '';
my $opt_auto_nmu = 'yes';
my $opt_force_save_on_release = 1;
my $opt_vendor = undef;

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
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.+)?',
		       'DEBCHANGE_RELEASE_HEURISTIC' => 'changelog',
		       'DEBCHANGE_MULTIMAINT' => 'yes',
		       'DEBCHANGE_TZ' => $ENV{TZ}, # undef if TZ unset
		       'DEBCHANGE_MULTIMAINT_MERGE' => 'no',
		       'DEBCHANGE_MAINTTRAILER' => '',
		       'DEBCHANGE_LOWER_VERSION_PATTERN' => '',
		       'DEBCHANGE_AUTO_NMU' => 'yes',
		       'DEBCHANGE_FORCE_SAVE_ON_RELEASE' => 'yes',
		       'DEBCHANGE_VENDOR' => '',
		       );
    $config_vars{'DEBCHANGE_TZ'} ||= '';
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
	or $config_vars{'DEBCHANGE_RELEASE_HEURISTIC'}='changelog';
    $config_vars{'DEBCHANGE_MULTIMAINT'} =~ /^(yes|no)$/
	or $config_vars{'DEBCHANGE_MULTIMAINT'}='yes';
    $config_vars{'DEBCHANGE_MULTIMAINT_MERGE'} =~ /^(yes|no)$/
	or $config_vars{'DEBCHANGE_MULTIMAINT_MERGE'}='no';
    $config_vars{'DEBCHANGE_AUTO_NMU'} =~ /^(yes|no)$/
	or $config_vars{'DEBCHANGE_AUTO_NMU'}='yes';
    $config_vars{'DEBCHANGE_FORCE_SAVE_ON_RELEASE'} =~ /^(yes|no)$/
	or $config_vars{'DEBCHANGE_FORCE_SAVE_ON_RELEASE'}='yes';

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
    $opt_multimaint = $config_vars{'DEBCHANGE_MULTIMAINT'} eq 'no' ? 0 : 1;
    $opt_tz = $config_vars{'DEBCHANGE_TZ'};
    $opt_multimaint_merge = $config_vars{'DEBCHANGE_MULTIMAINT_MERGE'} eq 'no' ? 0 : 1;
    $opt_t = ($config_vars{'DEBCHANGE_MAINTTRAILER'} eq 'no' ? 0 : 1)
	if $config_vars{'DEBCHANGE_MAINTTRAILER'};
    $opt_allow_lower = $config_vars{'DEBCHANGE_LOWER_VERSION_PATTERN'};
    $opt_auto_nmu = $config_vars{'DEBCHANGE_AUTO_NMU'};
    $opt_force_save_on_release =
	$config_vars{'DEBCHANGE_FORCE_SAVE_ON_RELEASE'} eq 'yes' ? 1 : 0;
    $opt_vendor = $config_vars{'DEBCHANGE_VENDOR'};
}

# We use bundling so that the short option behaviour is the same as
# with older debchange versions.
my ($opt_help, $opt_version);
my ($opt_i, $opt_a, $opt_e, $opt_r, $opt_v, $opt_b, $opt_d, $opt_D, $opt_u, $opt_force_dist);
my ($opt_n, $opt_bn, $opt_qa, $opt_R, $opt_s, $opt_team, $opt_U, $opt_bpo, $opt_l, $opt_c, $opt_m, $opt_M, $opt_create, $opt_package, @closes);
my ($opt_news);
my ($opt_level, $opt_regex, $opt_noconf, $opt_empty);

Getopt::Long::Configure('bundling');
GetOptions("help|h" => \$opt_help,
	   "version" => \$opt_version,
	   "i|increment" => \$opt_i,
	   "a|append" => \$opt_a,
	   "e|edit" => \$opt_e,
	   "r|release" => \$opt_r,
	   "create" => \$opt_create,
	   "package=s" => \$opt_package,
	   "v|newversion=s" => \$opt_v,
	   "b|force-bad-version" => \$opt_b,
	   "allow-lower-version=s" => \$opt_allow_lower,
	   "force-distribution" => \$opt_force_dist,
	   "d|fromdirname" => \$opt_d,
	   "p" => \$opt_p,
	   "preserve!" => \$opt_p,
	   "D|distribution=s" => \$opt_D,
	   "u|urgency=s" => \$opt_u,
	   "n|nmu" => \$opt_n,
	   "bin-nmu" => \$opt_bn,
	   "q|qa" => \$opt_qa,
	   "R|rebuild" => \$opt_R,
	   "s|security" => \$opt_s,
	   "team" => \$opt_team,
	   "U|upstream" => \$opt_U,
	   "bpo" => \$opt_bpo,
	   "l|local=s" => \$opt_l,
	   "query!" => \$opt_query,
	   "closes=s" => \@closes,
	   "c|changelog=s" => \$opt_c,
	   "news:s" => \$opt_news,
	   "multimaint!" => \$opt_multimaint,
	   "multi-maint!" => \$opt_multimaint,
	   'multimaint-merge!' => \$opt_multimaint_merge,
	   'multi-maint-merge!' => \$opt_multimaint_merge,
	   "m|maintmaint" => \$opt_m,
	   "M|controlmaint" => \$opt_M,
	   "t|mainttrailer!" => \$opt_t,
	   "check-dirname-level=s" => \$opt_level,
	   "check-dirname-regex=s" => \$opt_regex,
	   "noconf" => \$opt_noconf,
	   "no-conf" => \$opt_noconf,
	   "release-heuristic=s" => \$opt_release_heuristic,
	   "empty" => \$opt_empty,
	   "auto-nmu!" => \$opt_auto_nmu,
	   "force-save-on-release!" => \$opt_force_save_on_release,
	   "vendor=s" => \$opt_vendor,
	   )
    or die "Usage: $progname [options] [changelog entry]\nRun $progname --help for more details\n";

# So that we can distinguish, if required, between an explicit
# passing of -a / -i and their values being automagically deduced
# later on
my $opt_a_passed = $opt_a || 0;
my $opt_i_passed = $opt_i || 0;
$opt_news = 'debian/NEWS' if defined $opt_news and $opt_news eq '';

if ($opt_t eq '' && $opt_release_heuristic eq 'changelog') {
    $opt_t = 1;
}

if ($opt_noconf) {
    fatal "--no-conf is only acceptable as the first command-line option!";
}
if ($opt_help) { usage; exit 0; }
if ($opt_version) { version; exit 0; }

if (defined $opt_level) {
    if ($opt_level =~ /^[012]$/) { $check_dirname_level = $opt_level; }
    else {
	fatal "Unrecognised --check-dirname-level value (allowed are 0,1,2)";
    }
}

if (defined $opt_regex) { $check_dirname_regex = $opt_regex; }

# Only allow at most one non-help option
fatal "Only one of -a, -i, -e, -r, -v, -d, -n/--nmu, --bin-nmu, -q/--qa, -R/--rebuild, -s/--security, --team, --bpo, -l/--local is allowed;\ntry $progname --help for more help"
    if ($opt_i?1:0) + ($opt_a?1:0) + ($opt_e?1:0) + ($opt_r?1:0) + ($opt_v?1:0) + ($opt_d?1:0) + ($opt_n?1:0) + ($opt_bn?1:0) + ($opt_qa?1:0) + ($opt_R?1:0) + ($opt_s?1:0) + ($opt_team?1:0) + ($opt_bpo?1:0) + ($opt_l?1:0) > 1;

if ($opt_s) {
    $opt_u = "high";
}

if (defined $opt_u) {
    fatal "Urgency can only be one of: low, medium, high, critical, emergency"
	unless $opt_u =~ /^(low|medium|high|critical|emergency)$/;
}

# See if we're Debian, Ubuntu or someone else, if we can
my $vendor;
if (not $opt_vendor eq '') {
    $vendor = $opt_vendor;
} else {
    if (defined $opt_D) {
	# Try to guess the vendor based on the given distribution name
	my $distro = $opt_D;
	$distro =~ s/-.*//;
	my $deb_info = get_debian_distro_info();
	my $ubu_info = get_ubuntu_distro_info();
	if ($deb_info != 0 and $deb_info->valid($distro)) {
	    $vendor = 'Debian';
	} elsif ($ubu_info != 0 and $ubu_info->valid($distro)) {
	    $vendor = 'Ubuntu';
	}
    }
    if (not defined $vendor) {
	# Get the vendor from dpkg-vendor (dpkg-vendor --query Vendor)
	$vendor = get_current_vendor();
    }
}
$vendor ||= 'Debian';
if ($vendor eq 'Ubuntu' and ($opt_n or $opt_bn or $opt_qa or $opt_bpo)) {
    $vendor = 'Debian';
}

# Check the distro name given.
if (defined $opt_D) {
    if ($vendor eq 'Debian') {
	unless ($opt_D =~ /^(experimental|unstable|UNRELEASED|((old)?stable|testing)(-proposed-updates|-security)?|proposed-updates)$/) {
	    my $deb_info = get_debian_distro_info();
	    my $stable_backports = "";
	    if ($deb_info == 0) {
		warn "$progname warning: Unable to determine Debian's backport distributions.\n";
	    } else {
		$stable_backports = $deb_info->stable() . "-backports";
	    }
	    if ($deb_info == 0 || not $opt_D eq $stable_backports) {
		$stable_backports = ", " . $stable_backports if not $stable_backports eq "";
		warn "$progname warning: Recognised distributions are: unstable, testing, stable,\n"
		     . "oldstable, experimental, {testing-,stable-,oldstable-,}proposed-updates,\n"
		     . "{testing,stable,oldstable}-security$stable_backports and UNRELEASED.\n"
		     . "Using your request anyway.\n";
		$warnings++ if not $opt_force_dist;
	    }
	}
    } elsif ($vendor eq 'Ubuntu') {
	if ($opt_D eq 'UNRELEASED') {
	    ;
	} else {
	    my $ubu_release = $opt_D;
	    $ubu_release =~ s/(-updates|-security|-proposed|-backports)$//;
	    my $ubu_info = get_ubuntu_distro_info();
	    if ($ubu_info == 0) {
		warn "$progname warning: Unable to determine if $ubu_release "
		     . "is a valid Ubuntu release.\n";
	    } elsif (! $ubu_info->valid($ubu_release)) {
		warn "$progname warning: Recognised distributions are:\n{"
		     . join(',', $ubu_info->supported())
		     . "}{,-updates,-security,-proposed,-backports} and UNRELEASED.\n"
		     . "Using your request anyway.\n";
		$warnings++ if not $opt_force_dist;
	    }
	}
    } else {
	# Unknown vendor, skip check
    }
}

fatal "--closes should not be used with --news; put bug numbers in the changelog not the NEWS file"
    if $opt_news && @closes;

# hm, this can probably be used with more than just -i.
fatal "--package can only be used with --create, --increment and --newversion"
    if $opt_package && ! ($opt_create || $opt_i || $opt_v);

my $changelog_path = $opt_c || $ENV{'CHANGELOG'} || 'debian/changelog';
my $real_changelog_path = $changelog_path;
if ($opt_news) { $changelog_path = $opt_news; }
if ($changelog_path ne 'debian/changelog' and not $opt_news) {
    $check_dirname_level = 0;
}

# extra --create checks
fatal "--package cannot be used when creating a NEWS file"
    if $opt_package && $opt_news;

if ($opt_create) {
    if ($opt_a || $opt_i || $opt_e || $opt_r || $opt_b || $opt_n || $opt_bn ||
	    $opt_qa || $opt_R || $opt_s || $opt_team || $opt_bpo || $opt_l ||
	    $opt_allow_lower) {
	warn "$progname warning: ignoring -a/-i/-e/-r/-b/--allow-lower-version/-n/--bin-nmu/-q/--qa/-R/-s/--team/--bpo/-l options with --create\n";
	$warnings++;
    }
    if ($opt_package && $opt_d) {
	fatal "Can only use one of --package and -d";
    }
}


@closes = split(/,/, join(',', @closes));
map { s/^\#//; } @closes;  # remove any leading # from bug numbers

# We'll process the rest of the command line later.

# Look for the changelog
my $chdir = 0;
if (! $opt_create) {
    if ($changelog_path eq 'debian/changelog' or $opt_news) {
	until (-f $changelog_path) {
	    $chdir = 1;
	    chdir '..' or fatal "Can't chdir ..: $!";
	    if (cwd() eq '/') {
		fatal "Cannot find $changelog_path anywhere!\nAre you in the source code tree?\n(You could use --create if you wish to create this file.)";
	    }
	}

	# Can't write, so stop now.
	if (! -w $changelog_path) {
	    fatal "$changelog_path is not writable!";
	}
    }
    else {
	unless (-f $changelog_path) {
	    fatal "Cannot find $changelog_path!\nAre you in the correct directory?\n(You could use --create if you wish to create this file.)";
	}

	# Can't write, so stop now.
	if (! -w $changelog_path) {
	    fatal "$changelog_path is not writable!";
	}
    }
}
else {  # $opt_create
    unless (-d dirname $changelog_path) {
	fatal "Cannot find " . (dirname $changelog_path) . " directory!\nAre you in the correct directory?";
    }
    if (-f $changelog_path) {
	fatal "File $changelog_path already exists!";
    }
    unless (-w dirname $changelog_path) {
	fatal "Cannot find " . (dirname $changelog_path) . " directory!\nAre you in the correct directory?";
    }
    if ($opt_news && ! -f 'debian/changelog') {
	fatal "I can't create $opt_news without debian/changelog present";
    }
}

#####

# Find the current version number etc.
my %changelog;
my $PACKAGE = 'PACKAGE';
my $VERSION = 'VERSION';
my $MAINTAINER = 'MAINTAINER';
my $EMAIL = 'EMAIL';
my $DISTRIBUTION = 'UNRELEASED';
my $bpo_dist = '';
my %bpo_dists = ( 60, 'squeeze' );
my $latest_bpo_dist = '60';
my $CHANGES = '';
# Changelog urgency, possibly propogated to NEWS files
my $CL_URGENCY = '';

if (! $opt_create || ($opt_create && $opt_news)) {
    if (! $opt_create) {
	open PARSED, qq[dpkg-parsechangelog -l"$changelog_path" | ]
	    or fatal "Cannot execute dpkg-parsechangelog: $!";
    } elsif ($opt_create && $opt_news) {
	open PARSED, qq[dpkg-parsechangelog | ]
	    or fatal "Cannot execute dpkg-parsechangelog: $!";
    } else {
	fatal "This can't happen: what am I parsing?";
    }

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
    if ($?) { fatal "dpkg-parsechangelog failed!"; }

    # Now we've read the changelog, set some variables and then
    # let's check the directory name is sensible
    fatal "No package name in changelog!"
	unless exists $changelog{'Source'};
    $PACKAGE = $changelog{'Source'};
    fatal "No version number in changelog!"
	unless exists $changelog{'Version'};
    $VERSION=$changelog{'Version'};
    fatal "No maintainer in changelog!"
	unless exists $changelog{'Maintainer'};
    ($MAINTAINER,$EMAIL) = ($changelog{'Maintainer'} =~ /^([^<]+) <(.*)>/);
    fatal "No distribution in changelog!"
	unless exists $changelog{'Distribution'};
    if ($vendor eq 'Ubuntu') {
	# In Ubuntu the development release regularly changes, don't just copy
	# the previous name.
	$DISTRIBUTION=get_ubuntu_devel_distro();
    } else {
	$DISTRIBUTION=$changelog{'Distribution'};
    }
    fatal "No changes in changelog!"
	unless exists $changelog{'Changes'};

    # Find the current package version
    if ($opt_news) {
	my $found_version = 0;
	my $found_urgency = 0;
	open PARSED, qq[dpkg-parsechangelog -l"$real_changelog_path" | ]
	    or fatal "Cannot execute dpkg-parsechangelog: $!";
	while (<PARSED>) {
	    chomp;
	    if (m%^Version:\s+(\S+)$%) {
		$VERSION = $1;
		$VERSION =~ s/~$//;
		$found_version = 1;
		last if $found_urgency;
	    } elsif (m%^Urgency:\s+(\S+)(\s|$)%) {
		$CL_URGENCY = $1;
		$found_urgency = 1;
		last if $found_version;
	    } elsif (m%^$%) {
		last;
	    }
	}
	close PARSED
	    or fatal "Problem executing dpkg-parsechangelog: $!";
	if ($?) { fatal "dpkg-parsechangelog failed!"; }
    }

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
	    fatal <<"EOF";
Found debian/changelog for package $PACKAGE in the directory
  $pwd
but this directory name does not match the package name according to the
regex  $check_dirname_regex.

To run $progname on this package, see the --check-dirname-level and
--check-dirname-regex options; run $progname --help for more info.
EOF
	}
    }
} else {
    # we're creating and we don't know much about our package
    if ($opt_d) {
	my $pwd = basename(cwd());
	# The directory name should be <package>-<version>
	my $version_chars = '0-9a-zA-Z+\.\-';
	if ($pwd =~ m/^([a-z0-9][a-z0-9+\-\.]+)-([0-9][$version_chars]*)$/) {
	    $PACKAGE=$1;
	    $VERSION="$2-1";  # introduce a Debian version of -1
	} elsif ($pwd =~ m/^[a-z0-9][a-z0-9+\-\.]+$/) {
	    $PACKAGE=$pwd;
	} else {
	    # don't know anything
	}
    }
    if ($opt_v) {
	$VERSION=$opt_v;
    }
    if ($opt_D) {
	$DISTRIBUTION=$opt_D;
    }
}

if ($opt_package) {
    if ($opt_package =~ m/^[a-z0-9][a-z0-9+\-\.]+$/) {
	$PACKAGE=$opt_package;
    } else {
	warn "$progname warning: illegal package name used with --package: $opt_package\n";
	$warnings++;
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
check_env_utf8('NAME');
check_env_utf8('DEBEMAIL');
check_env_utf8('EMAIL');
check_env_utf8('UBUMAIL');

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
if (exists $env{'UBUMAIL'} and $env{'UBUMAIL'} =~ /^(.*)\s+<(.*)>$/) {
    $env{'DEBFULLNAME'} = $1 unless exists $env{'DEBFULLNAME'};
    $env{'UBUMAIL'} = $2;
}

# Now use the gleaned values to detemine our MAINTAINER and EMAIL values
if (! $opt_m and ! $opt_M) {
    if (exists $env{'DEBFULLNAME'}) {
	$MAINTAINER = $env{'DEBFULLNAME'};
    } elsif (exists $env{'NAME'}) {
	$MAINTAINER = $env{'NAME'};
    } else {
	my @pw = getpwuid $<;
	if ($pw[6]) {
	    if (my $pw = decode_utf8($pw[6])) {
		$pw =~ s/,.*//;
		$MAINTAINER = $pw;
	    } else {
		warn "$progname warning: passwd full name field for uid $<\nis not UTF-8 encoded; ignoring\n";
		$warnings++;
	    }
	}
    }
    # Otherwise, $MAINTAINER retains its default value of the last
    # changelog entry

    # Email is easier
    if ($vendor eq 'Ubuntu' and exists $env{'UBUMAIL'}) { $EMAIL = $env{'UBUMAIL'}; }
    elsif (exists $env{'DEBEMAIL'}) { $EMAIL = $env{'DEBEMAIL'}; }
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
} # if (! $opt_m and ! $opt_M)

if ($opt_M) {
    if (-f 'debian/control') {
	if (have_lpdc()) {
	    my $parser = Parse::DebControl->new;
	    my $deb822 = $parser->parse_file('debian/control', {stripComments => 'true'});
	    my $maintainer = decode_utf8($deb822->[0]->{'Maintainer'});
	    if ($maintainer =~ /^(.*)\s+<(.*)>$/) {
		$MAINTAINER = $1;
		$EMAIL = $2;
	    } else {
		fatal "$progname: invalid debian/control Maintainer field value\n";
	    }
	} else {
	    fatal "$progname: unable to get maintainer from debian/control: $lpdc_broken\n";
	}
    } else {
	fatal "Missing file debian/control";
    }
}

#####

if ($opt_auto_nmu eq 'yes' and ! $opt_v and ! $opt_l and ! $opt_s and
    ! $opt_team and ! $opt_qa and ! $opt_R and ! $opt_bpo and ! $opt_bn and
    ! $opt_n and ! $opt_c and
    ! (exists $ENV{'CHANGELOG'} and length $ENV{'CHANGELOG'}) and ! $opt_M and
    ! $opt_create and ! $opt_a_passed and ! $opt_r and ! $opt_e and
    $vendor ne 'Ubuntu' and
    ! ($opt_release_heuristic eq 'changelog' and
       $changelog{'Distribution'} eq 'UNRELEASED' and ! $opt_i_passed)) {

    if (-f 'debian/control') {
	if (have_lpdc()) {
	    my $parser = new Parse::DebControl;
	    my $deb822 = $parser->parse_file('debian/control', {stripComments => 'true'});
	    my $uploader = decode_utf8($deb822->[0]->{'Uploaders'}) || '';
	    my $maintainer = decode_utf8($deb822->[0]->{'Maintainer'});
	    my @uploaders = split(/,\s*/, $uploader);

	    my $packager = "$MAINTAINER <$EMAIL>";

	    if ($maintainer !~ m/<packages\@qa\.debian\.org>/ and
		! grep { $_ eq $packager } ($maintainer, @uploaders) and
		$packager ne $changelog{'Maintainer'} and ! $opt_team) {
		$opt_n=1;
		$opt_a=0;
	    }
	} else {
	    warn "$progname: skipping automatic NMU detection: $lpdc_broken\n";
	}
    } else {
	fatal "Missing file debian/control";
    }
}
#####

# Do we need to generate "closes" entries?

my @closes_text = ();
my $initial_release = 0;
if (@closes and $opt_query) { # and we have to query the BTS
    if (!Devscripts::Debbugs::have_soap) {
	warn "$progname warning: libsoap-lite-perl not installed, so cannot query the bug-tracking system\n";
	$opt_query=0;
	$warnings++;
	# This will now go and execute the "if (@closes and ! $opt_query)" code
    }
    else
    {
	my $bugs = Devscripts::Debbugs::select( "src:" . $PACKAGE );
	my $statuses = Devscripts::Debbugs::status(
	    map {[bug => $_, indicatesource => 1]} @{$bugs} );
	if ($statuses eq "") {
	    warn "$progname: No bugs found for package $PACKAGE\n";
	}
	foreach my $close (@closes) {
	    if ($statuses and exists $statuses->{$close}) {
		my $title = $statuses->{$close}->{subject};
		my $pkg = $statuses->{$close}->{package};
		$title =~ s/^($pkg|$PACKAGE): //;
		push @closes_text, "Fix \"$title\" <explain what you changed and why> (Closes: \#$close)\n";
	    }
	    else { # not our package, or wnpp
		my $bug = Devscripts::Debbugs::status(
		    [bug => $close, indicatesource => 1] );
		if ($bug eq "") {
		    warn "$progname warning: unknown bug \#$close does not belong to $PACKAGE,\n  disabling closing changelog entry\n";
		    $warnings++;
		    push @closes_text, "Closes?? \#$close: UNKNOWN BUG IN WRONG PACKAGE!!\n";
		} else {
		    my $bugtitle = $bug->{$close}->{subject};
		    $bugtitle ||= '';
		    my $bugpkg = $bug->{$close}->{package};
		    $bugpkg ||= '?';
		    my $bugsrcpkg = $bug->{$close}->{source};
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
			    $initial_release = 1;
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
my $ARGS=join(' ', @ARGV);
my $TEXT=decode_utf8($ARGS);
my $EMPTY_TEXT=0;

if (@ARGV and ! $TEXT) {
    if ($ARGS) {
	warn "$progname warning: command-line changelog entry not UTF-8 encoded; ignoring\n";
	$TEXT='';
    } else {
	$EMPTY_TEXT = 1;
    }
}

# Get the date
my $date_cmd = ($opt_tz ? "TZ=$opt_tz " : "") . "date -R";
chomp(my $DATE=`$date_cmd`);

if ($opt_news && !$opt_i && !$opt_a) {
    if ($VERSION eq $changelog{'Version'} && !$opt_v && !$opt_l) {
	$opt_a = 1;
    } else {
	$opt_i = 1;
    }
}

# Are we going to have to figure things out for ourselves?
if (! $opt_i && ! $opt_v && ! $opt_d && ! $opt_a && ! $opt_e && ! $opt_r &&
    ! $opt_n && ! $opt_bn && ! $opt_qa && ! $opt_R && ! $opt_s && ! $opt_team &&
    ! $opt_bpo && ! $opt_l && ! $opt_create) {
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
		if (m%^(s|Successfully uploaded) (/.*/)?\Q$PACKAGE\E\_\Q$SVERSION\E\_[\w\-\+]+\.changes %) {
		   $opt_i = 1;
		   last;
		}
	    }
	    close UPFILE
		or fatal "Problems experienced reading .upload file: $!\n" .
			    "Please use an explicit -a, -i or -v option instead.";
	    if (! $opt_i) {
		warn "$progname warning: A successful upload of the current version was not logged\n" .
		    "in the upload log file; adding log entry to current version.\n";
		$opt_a = 1;
	    }
	}
    }
    elsif ($opt_release_heuristic eq 'changelog') {
	if ($changelog{'Distribution'} eq 'UNRELEASED') {
		$opt_a = 1;
	}
	elsif ($EMPTY_TEXT==1) {
		$opt_a = 1;
	} else {
		$opt_i = 1;
	}
    }
    else {
	fatal "Bad release heuristic value";
    }
}

# Open in anticipation....
unless ($opt_create) {
    open S, $changelog_path or fatal "Cannot open existing $changelog_path: $!";

    # Read the first stanza from the changelog file
    # We do this directly rather than reusing $changelog{'Changes'}
    # so that we have the verbatim changes rather than a (albeit very
    # slightly) reformatted version. See Debian bug #452806

    while(<S>) {
	last if /^ --/;

	$CHANGES .= $_;
    }

    chomp $CHANGES;

    # Reset file pointer
    seek(S, 0, 0);
}
open O, ">$changelog_path.dch"
    or fatal "Cannot write to temporary file: $!";
# Turn off form feeds; taken from perlform
select((select(O), $^L = "")[0]);

# Note that we now have to remove it
my $tmpchk=1;
my ($NEW_VERSION, $NEW_SVERSION, $NEW_UVERSION);
my $line;
my $optionsok=0;
my $merge=0;

if (($opt_i || $opt_n || $opt_bn || $opt_qa || $opt_R || $opt_s || $opt_team ||
     $opt_bpo || $opt_l || $opt_v || $opt_d ||
    ($opt_news && $VERSION ne $changelog{'Version'})) && ! $opt_create) {

    $optionsok=1;

    # Check that a given explicit version number is sensible.
    if ($opt_v || $opt_d) {
	if($opt_v) {
	    $NEW_VERSION=$opt_v;
	} else {
	    my $pwd = basename(cwd());
	    # The directory name should be <package>-<version>
	    my $version_chars = '0-9a-zA-Z+\.~';
	    $version_chars .= ':' if defined $EPOCH;
	    $version_chars .= '\-' if $UVERSION ne $SVERSION;
	    if ($pwd =~ m/^\Q$PACKAGE\E-([0-9][$version_chars]*)$/) {
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

	if (system("dpkg --compare-versions $VERSION le $NEW_VERSION" .
		  " 2>/dev/null 1>&2")) {
	    if ($opt_b or ($opt_allow_lower and $NEW_VERSION =~ /$opt_allow_lower/)) {
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
	if ($VERSION =~ /(.*?)([a-yA-Y][a-zA-Z]*|\d+)([+~])?$/i) {
	    my $extra=$3 || '';
	    my $useextra = 0;
	    my $end=$2;
	    my $start=$1;
	    # If it's not already an NMU make it so
	    # otherwise we can be safe if we behave like dch -i

	    if (($opt_n or $opt_s) and $vendor ne 'Ubuntu' and (
		($VERSION eq $UVERSION and not $start =~ /\+nmu/)
		or ($VERSION ne $UVERSION and not $start =~ /\.$/))) {

		if ($VERSION eq $UVERSION) {
		    # First NMU of a Debian native package
		    $end .= "+nmu1";
		} else {
		    $end += 0.1;
		}
	    } elsif ($opt_bn and not $start =~ /\+b/) {
		$end .= "+b1";
	    } elsif ($opt_qa and $start =~/(.*?)-(\d+)\.$/) {
		# Drop NMU revision when doing a QA upload
		my $upstream_version = $1;
		my $debian_revision = $2;
		$debian_revision++;
		$start = "$upstream_version-$debian_revision";
		$end = "";
	    } elsif ($opt_R and $vendor eq 'Ubuntu' and
	             not $start =~ /build/ and not $start =~ /ubuntu/) {
		$end .= "build1";
	    } elsif ($opt_bpo and not $start =~ /~bpo[0-9]+\+$/) {
		# If it's not already a backport make it so
		# otherwise we can be safe if we behave like dch -i
		$end .= "~bpo$latest_bpo_dist+1";
	    } elsif ($opt_l and not $start =~ /\Q$opt_l\E/) {
		# If it's not already a local package make it so
		# otherwise we can be safe if we behave like dch -i
		$end .= $opt_l."1";
	    } elsif (!$opt_news) {
		# Don't bump the version of a NEWS file in this case as we're
		# using the version from the changelog
		if (($opt_i or $opt_s) and $vendor eq 'Ubuntu' and
		     $start !~ /(ubuntu|~ppa)(\d+\.)*$/ and not $opt_U) {

		    if ($start =~ /build/) {
			# Drop buildX suffix in favor of ubuntu1
			$start =~ s/build//;
			$end = "";
		    }
		    $end .= "ubuntu1";
		} else {
		    $end++;
		}

		# Attempt to set the distribution for a backport correctly
		# based on the version of the previous backport
		if ($opt_bpo) {
		    my $previous_dist = $start;
		    $previous_dist =~ s/^.*~bpo([0-9]+)\+$/$1/;
		    if (defined $previous_dist and defined
			$bpo_dists{$previous_dist}) {
			$bpo_dist = $bpo_dists{$previous_dist} . '-backports';
		    } else {
			# Fallback to using the previous distribution
			$bpo_dist = $changelog{'Distribution'};
		    }
		}

		if(! ($opt_s or $opt_n or $vendor eq 'Ubuntu')) {
		    if ($start =~/(.*?)-(\d+)\.$/) {
			# Drop NMU revision
			my $upstream_version = $1;
			my $debian_revision = $2;
			$debian_revision++;
			$start = "$upstream_version-$debian_revision";
			$end = "";
		    }
		}

		if (! ($opt_qa or $opt_bpo or $opt_l)) {
		    $useextra = 1;
		}
	    }
	    $NEW_VERSION = "$start$end";
	    if ($useextra) {
		$NEW_VERSION .= $extra;
	    }
	    ($NEW_SVERSION=$NEW_VERSION) =~ s/^\d+://;
	    ($NEW_UVERSION=$NEW_SVERSION) =~ s/-[^-]*$//;
	} else {
	    fatal "Error parsing version number: $VERSION";
	}
    }

    if ($NEW_VERSION eq $NEW_UVERSION and $VERSION ne $UVERSION) {
	warn "$progname warning: New package version is Debian native whilst previous version was not\n";
    } elsif ($NEW_VERSION ne $NEW_UVERSION and $VERSION eq $UVERSION) {
	warn "$progname warning: Previous package version was Debian native whilst new version is not\n"
	    unless $opt_n or $opt_s;
    }

    if ($opt_bpo) {
	$bpo_dist ||= $bpo_dists{$latest_bpo_dist} . '-backports';
    }
    my $distribution = $opt_D || $bpo_dist || (($opt_release_heuristic eq 'changelog') ? "UNRELEASED" : $DISTRIBUTION);

    my $urgency = $opt_u;
    if ($opt_news) {
	$urgency ||= $CL_URGENCY;
    }
    $urgency ||= 'low';

    if (($opt_v or $opt_i or $opt_l or $opt_d) and
	$opt_release_heuristic eq "changelog" and
	$changelog{'Distribution'} eq "UNRELEASED" and
	$distribution eq "UNRELEASED") {

	$merge = 1;
    } else {
	print O "$PACKAGE ($NEW_VERSION) $distribution; urgency=$urgency\n\n";
	if ($opt_n && ! $opt_news) {
	    print O "  * Non-maintainer upload.\n";
	    $line = 1;
	} elsif ($opt_bn && ! $opt_news) {
	    my $arch = qx/dpkg-architecture -qDEB_BUILD_ARCH/; chomp ($arch);
	    print O "  * Binary-only non-maintainer upload for $arch; no source changes.\n";
	    $line = 1;
	} elsif ($opt_qa && ! $opt_news) {
	    print O "  * QA upload.\n";
	    $line = 1;
	} elsif ($opt_s && ! $opt_news) {
	    if ($vendor eq 'Ubuntu') {
		print O "  * SECURITY UPDATE:\n";
		print O "  * References\n";
	    } else {
		print O "  * Non-maintainer upload by the Security Team.\n";
	    }
	    $line = 1;
	} elsif ($opt_team && ! $opt_news) {
	    print O "  * Team upload.\n";
	    $line = 1;
	} elsif ($opt_bpo && ! $opt_news) {
	    print O "  * Rebuild for $bpo_dist.\n";
	    $line = 1;
	}
	if (@closes_text or $TEXT) {
	    foreach (@closes_text) { format_line($_, 1); }
	    if (length $TEXT) { format_line($TEXT, 1); }
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
}
if (($opt_r || $opt_a || $merge) && ! $opt_create) {
    # This means we just have to generate a new * entry in changelog
    # and if a multi-developer changelog is detected, add developer names.

    $NEW_VERSION=$VERSION unless $NEW_VERSION;
    $NEW_SVERSION=$SVERSION unless $NEW_SVERSION;
    $NEW_UVERSION=$UVERSION unless $NEW_UVERSION;

    # Read and discard maintainer line, see who made the
    # last entry, and determine whether there are existing
    # multi-developer changes by the current maintainer.
    $line=-1;
    my ($lastmaint, $nextmaint, $maintline, $count, $lastheader, $lastdist, $dist_indicator);
    my $savedline = $line;;
    while (<S>) {
	$line++;
	# Start of existing changes by the current maintainer
	if (/^  \[ $MAINTAINER \]$/ && $opt_multimaint_merge) {
	    # If there's more than one such block,
	    # we only care about the first
	    $maintline ||= $line;
	}
	elsif (/^  \[ (.*) \]$/ && defined $maintline) {
	    # Start of existing changes following those by the current
	    # maintainer
	    $nextmaint ||= $1;
	}
	elsif (m/^\w[-+0-9a-z.]* \(([^\(\) \t]+)\)((?:\s+[-+0-9a-z.]+)+)\;\s+urgency=(\w+)/i) {
	    if (defined $lastmaint) {
		$lastheader = $_;
		$lastdist = $2;
		$lastdist =~ s/^\s+//;
		undef $lastdist if $lastdist eq "UNRELEASED";
		# Revert to our previously saved position
		$line = $savedline;
		last;
	    }
	    else {
		my $tmpver = $1;
		$tmpver =~ s/^\s+//;
		if ($tmpver =~ m/~bpo(\d+)\+/ && exists $bpo_dists{$1}) {
		    $dist_indicator = "$bpo_dists{$1}-backports";
		}
	    }
	}
	elsif (/  \* (?:Upload to|Rebuild for) (\S+).*$/) {
	    ($dist_indicator = $1) =~ s/[!:.,;]$//;
	    chomp $dist_indicator;
	}
	elsif (/^ --\s+([^<]+)\s+/) {
	    $lastmaint=$1;
	    # Remember where we are so we can skip back afterwards
	    $savedline = $line;
	}

	if (defined $maintline && !defined $nextmaint) {
	    $maintline++;
	}
    }

    # Munging of changelog for multimaintainer mode.
    my $multimaint=0;
    if (! $opt_news) {
	my $lastmultimaint;

	# Parse the changelog for multi-maintainer maintainer lines of
	# the form [ Full Name ] and record the last of these.
	while ($CHANGES=~/.*\n^\s+\[\s+([^\]]+)\s+]\s*$/mg) {
	    $lastmultimaint=$1;
	}

	if ((! defined $lastmultimaint && defined $lastmaint &&
	     $lastmaint ne $MAINTAINER && $opt_multimaint)
	    ||
	    (defined $lastmultimaint && $lastmultimaint ne $MAINTAINER)
	    ||
	    (defined $nextmaint)
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

    # based on /usr/lib/dpkg/parsechangelog/debian
    if ($CHANGES =~ m/^\w[-+0-9a-z.]* \([^\(\) \t]+\)((?:\s+[-+0-9a-z.]+)+)\;\s+urgency=(\w+)/i) {
	my $distribution = $1;
	my $urgency = $2;
	if ($opt_news) {
	    $urgency = $CL_URGENCY;
	}
	$distribution =~ s/^\s+//;
	if ($opt_r) {
	    # Change the distribution from UNRELEASED for release
	    if ($distribution eq "UNRELEASED") {
		if ($dist_indicator and not $opt_D) {
		    $distribution = $dist_indicator;
		} elsif ($vendor eq 'Ubuntu') {
		    if ($opt_D) {
			$distribution = $opt_D;
		    } else {
			$distribution = get_ubuntu_devel_distro();
		    }
		} else {
		    $distribution = $opt_D || $lastdist || "unstable";
		}
	    } elsif ($opt_D) {
		warn "$progname warning: ignoring distribution passed to --release as changelog has already been released\n";
	    }
	    # Set the start-line to 1, as we don't know what they want to edit
	    $line=1;
	} else {
	    $distribution = $opt_D if $opt_D;
	}
	$urgency = $opt_u if $opt_u;
	$CHANGES =~ s/^(\w[-+0-9a-z.]* \([^\(\) \t]+\))(?:\s+[-+0-9a-z.]+)+\;\s+urgency=\w+/$PACKAGE ($NEW_VERSION) $distribution; urgency=$urgency/i;
    } else {
	warn "$progname: couldn't parse first changelog line, not touching it\n";
	$warnings++;
    }

    if (defined $maintline && defined $nextmaint) {
	# Output the lines up to the end of the current maintainer block
	$count=1;
	$line=$maintline;
	foreach (split /\n/, $CHANGES) {
	    print O $_ . "\n";
	    $count++;
	    last if $count==$maintline;
	}
    } else {
	# The first lines are as we have already found
	print O $CHANGES;
    };

    if (! $opt_r) {
	# Add a multi-maintainer header...
	if ($multimaint) {
	    # ...unless there already is one for this maintainer.
	    if (!defined $maintline) {
		print O "\n  [ $MAINTAINER ]\n";
		$line+=2;
	    }
	}

	if (@closes_text or $TEXT) {
	    foreach (@closes_text) { format_line($_, 0); }
	    if (length $TEXT) { format_line($TEXT, 0); }
	} elsif ($opt_news) {
	    print O "\n  \n";
	    $line++;
	} elsif (!$EMPTY_TEXT) {
	    print O "  * \n";
	}
    }

    if (defined $count) {
	# Output the remainder of the changes
	$count=1;
	foreach (split /\n/, $CHANGES) {
	    $count++;
	    next unless $count>$maintline;
	    print O $_ . "\n";
	}
    }

    if ($opt_t && $opt_a) {
	print O "\n -- $changelog{'Maintainer'}  $changelog{'Date'}\n";
    } else {
	print O "\n -- $MAINTAINER <$EMAIL>  $DATE\n";
    }

    if ($lastheader) {
	print O "\n$lastheader";
    }

    # Copy the rest of the changelog file to new one
    # Slurp the rest....
    local $/ = undef;
    print O <S>;
}
elsif ($opt_e && ! $opt_create) {
    # We don't do any fancy stuff with respect to versions or adding
    # entries, we just update the timestamp and open the editor

    print O $CHANGES;

    if ($opt_t) {
	print O "\n -- $changelog{'Maintainer'}  $changelog{'Date'}\n";
    } else {
	print O "\n -- $MAINTAINER <$EMAIL>  $DATE\n";
    }

    # Copy the rest of the changelog file to the new one
    $line=-1;
    while (<S>) { $line++; last if /^ --/; }
    # Slurp the rest...
    local $/ = undef;
    print O <S>;

    # Set the start-line to 0, as we don't know what they want to edit
    $line=0;
}
elsif ($opt_create) {
    if (! $initial_release and ! $opt_news and ! $opt_empty and
	! $TEXT and ! $EMPTY_TEXT) {
	push @closes_text, "Initial release. (Closes: \#XXXXXX)\n";
    }

    my $urgency = $opt_u;
    if ($opt_news) {
	$urgency ||= $CL_URGENCY;
    }
    $urgency ||= 'low';
    print O "$PACKAGE ($VERSION) $DISTRIBUTION; urgency=$urgency\n\n";

    if (@closes_text or $TEXT) {
	foreach (@closes_text) { format_line($_, 1); }
	if (length $TEXT) { format_line($TEXT, 1); }
    } elsif ($opt_news) {
	print O "  \n";
    } elsif ($opt_empty) {
	# Do nothing, but skip the empty entry
    } else { # this can't happen, but anyway...
	print O "  * \n";
    }

    print O "\n -- $MAINTAINER <$EMAIL>  $DATE\n";

    $line = 1;
}
elsif (!$optionsok) {
    fatal "Unknown changelog processing command line options - help!";
}

if (! $opt_create) {
    close S or fatal "Error closing $changelog_path: $!";
}
close O or fatal "Error closing temporary $changelog_path: $!";

if ($warnings) {
    if ($warnings>1) {
	warn "$progname: Did you see those $warnings warnings?  Press RETURN to continue...\n";
    } else {
	warn "$progname: Did you see that warning?  Press RETURN to continue...\n";
    }
    my $garbage = <STDIN>;
}

# Now Run the Editor; always run if doing "closes" to give a chance to check
if ((!$TEXT and !$EMPTY_TEXT and ! ($opt_create and $opt_empty)) or @closes_text or
    ($opt_create and ! ($PACKAGE ne 'PACKAGE' and $VERSION ne 'VERSION'))) {

    my $mtime = (stat("$changelog_path.dch"))[9];
    defined $mtime or fatal
	"Error getting modification time of temporary $changelog_path: $!";

    system("sensible-editor +$line $changelog_path.dch") == 0 or
	fatal "Error editing $changelog_path";

    my $newmtime = (stat("$changelog_path.dch"))[9];
    defined $newmtime or fatal
	"Error getting modification time of temporary $changelog_path: $!";
    if ($mtime == $newmtime && ! $opt_create &&
	(!$opt_r || ($opt_r && $opt_force_save_on_release))) {

	warn "$progname: $changelog_path unmodified; exiting.\n";
	exit 0;
    }
}

copy("$changelog_path.dch","$changelog_path") or
    fatal "Couldn't replace $changelog_path with new version: $!";

# Now find out what the new package version number is if we need to
# rename the directory

if ((basename(cwd()) =~ m%^\Q$PACKAGE\E-\Q$UVERSION\E$%) &&
    !$opt_p && !$opt_create) {
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

    fatal "No version number in debian/changelog!"
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
	    warn "$progname warning: Couldn't rename directory: $!\n";
	}
	# And check whether a new orig tarball exists
	my @origs = glob("../$PACKAGE\_$new_uversion.*");
	my $num_origs = grep { /^..\/\Q$PACKAGE\E_\Q$new_uversion\E\.orig\.tar\.$compression_re_file_ext$/ } @origs;
	if ($num_origs == 0) {
	    warn "$progname warning: no orig tarball found for the new version.\n";
	}
    }
}

exit 0;

{
    no warnings 'uninitialized';
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
}

my $linecount=0;
sub format_line {
    $CHGLINE=shift;
    my $newentry=shift;

    # Work around the fact that write() with formats
    # seems to assume that characters are single-byte
    # See http://rt.perl.org/rt3/Public/Bug/Display.html?id=33832
    # and Debian bugs #473769 and #541484
    # This relies on $CHGLINE being a sequence of unicode characters.  We can
    # compare how many unicode characters we have to how many bytes we have
    # when encoding to utf8 and therefore how many spaces we need to pad.
    my $count = length(encode_utf8($CHGLINE)) - length($CHGLINE);
    $CHGLINE .= " " x $count;

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

BEGIN {
    # Initialise the variable
    $tmpchk=0;
}

END {
    if ($tmpchk) {
	unlink "$changelog_path.dch" or
	    warn "$progname warning: Could not remove $changelog_path.dch\n";
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
