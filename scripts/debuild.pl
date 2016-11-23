#!/usr/bin/perl

# Perl version of Christoph Lameter's build program, renamed debuild.
# Written by Julian Gilbey, December 1998.

# Copyright 1999-2003, Julian Gilbey <jdg@debian.org>
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

# We will do simple option processing.  The calling syntax of this
# program is:
#
#   debuild [<debuild options>] binary|binary-arch|binary-indep|clean ...
# or
#   debuild [<debuild options>] [<dpkg-buildpackage options>]
#            [--lintian-opts <lintian options>]
#
# In the first case, debuild will simply run debian/rules with the
# given parameter.  Available options are listed in usage() below.
#
# In the second case, the behaviour is to run dpkg-buildpackage and
# then to run lintian on the resulting .changes file.
# Lintian options may be specified after --lintian-opts; all following
# options will be passed only to lintian.
#
# As this may be running setuid, we make sure to clean out the
# environment before we perform the build, subject to any -e etc.
# options.  Also wise for building the packages, anyway.
# We don't put /usr/local/bin in the PATH as Debian
# programs will presumably be built without the use of any locally
# installed programs.  This could be changed, but in which case,
# please add /usr/local/bin at the END so that you don't get any
# unexpected behaviour.

# We will try to preserve the locale variables, but if it turns out that
# this harms the package building process, we will clean them out too.
# Please file a bug report if this is the case!

use strict;
use warnings;
use 5.008;
use File::Basename;
use filetest 'access';
use Cwd;
use Dpkg::Changelog::Parse qw(changelog_parse);
use Dpkg::IPC;
use IO::Handle;  # for flushing
use vars qw(*BUILD *OLDOUT *OLDERR);  # prevent a warning

my $progname=basename($0);
my $modified_conf_msg;
my @warnings;

# Predeclare functions
sub system_withecho(@);
sub run_hook ($$);
sub fatal($);

sub usage
{
    print <<"EOF";
First usage method:
  $progname [<debuild options>] binary|binary-arch|binary-indep|clean ...
    to run debian/rules with given parameter(s).  Options here are
        --no-conf, --noconf      Don\'t read devscripts config files;
                                 must be the first option given
        --rootcmd=<gain-root-command>, -r<gain-root-command>
                                 Command used to become root if $progname
                                 not setuid root; default=fakeroot

        --preserve-envvar=<envvar>, -e<envvar>
                                 Preserve environment variable <envvar>

        --preserve-env           Preserve all environment vars (except PATH)

        --set-envvar=<envvar>=<value>, -e<envvar>=<value>
                                 Set environment variable <envvar> to <value>

        --prepend-path=<value>   Prepend <value> to the sanitised PATH

        -d                       Skip checking of build dependencies
        -D                       Force checking of build dependencies (default)

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

        --help, -h    display this message

        --version     show version and copyright information

Second usage method:
  $progname [<debuild options>] [<dpkg-buildpackage options>]
             [--lintian-opts <lintian options>]
    to run dpkg-buildpackage and then run lintian on the resulting
    .changes file.

    Additional debuild options available in this case are:

        --lintian           Run lintian (default)
        --no-lintian        Do not run lintian
        --[no-]tgz-check    Do [not] check for an .orig.tar.gz before running
                            dpkg-buildpackage if we have a Debian revision
                            (Default: check)
        --username          Run debrsign instead of debsign, using the
                            supplied credentials

        --dpkg-buildpackage-hook=HOOK
        --clean-hook=HOOK
        --dpkg-source-hook=HOOK
        --build-hook=HOOK
        --binary-hook=HOOK
        --dpkg-genchanges-hook=HOOK
        --final-clean-hook=HOOK
        --lintian-hook=HOOK
        --signing-hook=HOOK
        --post-dpkg-buildpackage-hook=HOOK
                            These hooks run at the various stages of the
                            dpkg-buildpackage run.  For details, see the
                            debuild manpage.  They default to nothing, and
                            can be reset to nothing with --foo-hook=''
        --clear-hooks       Clear all hooks

    For available dpkg-buildpackage and lintian options, see their
    respective manpages.

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

sub version
{
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999-2003 by Julian Gilbey <jdg\@debian.org>,
all rights reserved.
Based on a shell-script program by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

# Start by reading configuration files and then command line
# The next stuff is somewhat boilerplate and somewhat not.
# It's complicated by the fact that the config files are in shell syntax,
# and we don't want to have to write a general shell parser in Perl.
# So we'll get the shell to do the work.  Yuck.
# We allow DEBUILD_PRESERVE_ENVVARS="VAR1,VAR2,VAR3"
# and DEBUILD_SET_ENVVAR_VAR1=VAL1, DEBUILD_SET_ENVVAR_VAR2=VAR2.

# Set default values before we start
my $preserve_env=0;
my %save_vars;
my $root_command='';
my $run_lintian=1;
my @dpkg_extra_opts=();
my @lintian_extra_opts=();
my @lintian_opts=();
my $checkbuilddep;
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.+)?';
my $logging=0;
my $tgz_check=1;
my $prepend_path='';
my $username='';
my @hooks = (qw(dpkg-buildpackage clean dpkg-source build binary dpkg-genchanges
		final-clean lintian signing post-dpkg-buildpackage));
my %hook;
$hook{@hooks} = ('') x @hooks;


# First handle private options from cvs-debuild
my ($cvsdeb_file, $cvslin_file);
if (@ARGV and $ARGV[0] eq '--cvs-debuild') {
    shift;
    $check_dirname_level=0;  # no need to check dirnames if we're being
                             # called from cvs-debuild
    if (@ARGV and $ARGV[0] eq '--cvs-debuild-deb') {
	shift;
	$cvsdeb_file=shift;
	unless ($cvsdeb_file =~ m%^/dev/fd/\d+$%) {
	    fatal "--cvs-debuild-deb is an internal option and should not be used";
	}
    }
    if (@ARGV and $ARGV[0] eq '--cvs-debuild-lin') {
	shift;
	$cvslin_file = shift;
	unless ($cvslin_file =~ m%^/dev/fd/\d+$%) {
	    fatal "--cvs-debuild-lin is an internal option and should not be used";
	}
    }
    if (defined $cvsdeb_file) {
	local $/;
	open DEBOPTS, $cvsdeb_file
	    or fatal "can't open cvs-debuild debuild options file: $!";
	my $opts = <DEBOPTS>;
	close DEBOPTS;

	unshift @ARGV, split(/\0/,$opts,-1);
    }
    if (defined $cvslin_file) {
	local $/;
	open LINOPTS, $cvslin_file
	    or fatal "can't open cvs-debuild lin* options file: $!";
	my $opts = <LINOPTS>;
	close LINOPTS;

	push @ARGV, split(/\0/,$opts,-1);
    }
}

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DEBUILD_PRESERVE_ENV' => 'no',
		       'DEBUILD_PRESERVE_ENVVARS' => '',
		       'DEBUILD_LINTIAN' => 'yes',
		       'DEBUILD_ROOTCMD' => 'fakeroot',
		       'DEBUILD_TGZ_CHECK' => 'yes',
		       'DEBUILD_DPKG_BUILDPACKAGE_HOOK' => '',
		       'DEBUILD_CLEAN_HOOK' => '',
		       'DEBUILD_DPKG_SOURCE_HOOK' => '',
		       'DEBUILD_BUILD_HOOK' => '',
		       'DEBUILD_BINARY_HOOK' => '',
		       'DEBUILD_DPKG_GENCHANGES_HOOK' => '',
		       'DEBUILD_FINAL_CLEAN_HOOK' => '',
		       'DEBUILD_LINTIAN_HOOK' => '',
		       'DEBUILD_SIGNING_HOOK' => '',
		       'DEBUILD_PREPEND_PATH' => '',
		       'DEBUILD_POST_DPKG_BUILDPACKAGE_HOOK' => '',
		       'DEBUILD_SIGNING_USERNAME' => '',
		       'DEVSCRIPTS_CHECK_DIRNAME_LEVEL' => 1,
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.+)?',
		       );
    my %config_default = %config_vars;
    my $dpkg_opts_var = 'DEBUILD_DPKG_BUILDPACKAGE_OPTS';
    my $lintian_opts_var = 'DEBUILD_LINTIAN_OPTS';

    my $shell_cmd;
    # Set defaults
    $shell_cmd .= qq[unset `set | grep "^DEBUILD_" | cut -d= -f1`;\n];
    foreach my $var (keys %config_vars) {
	$shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    foreach my $var ($dpkg_opts_var, $lintian_opts_var) {
	$shell_cmd .= "$var='';\n";
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    foreach my $var ($dpkg_opts_var, $lintian_opts_var) {
	$shell_cmd .= "eval set -- \$$var;\n";
	$shell_cmd .= "echo \">>> $var BEGIN <<<\";\n";
	$shell_cmd .= 'while [ $# -gt 0 ]; do printf "%s\n" "$1"; shift; done;' . "\n";
	$shell_cmd .= "echo \">>> $var END <<<\";\n";
    }
    # Not totally efficient, but never mind
    $shell_cmd .= 'for var in `set | grep "^DEBUILD_SET_ENVVAR_" | cut -d= -f1`; do ';
    $shell_cmd .= 'eval echo $var=\$$var; done;' . "\n";
    # print STDERR "Running shell command:\n$shell_cmd";
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    # print STDERR "Shell output:\n${shell_out}End shell output\n";
    my @othervars;
    (@config_vars{keys %config_vars}, @othervars) = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'DEBUILD_PRESERVE_ENV'} =~ /^(yes|no)$/
	or $config_vars{'DEBUILD_PRESERVE_ENV'}='no';
    $config_vars{'DEBUILD_LINTIAN'} =~ /^(yes|no)$/
	or $config_vars{'DEBUILD_LINTIAN'}='yes';
    $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} =~ /^[012]$/
	or $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'}=1;
    $config_vars{'DEBUILD_TGZ_CHECK'} =~ /^(yes|no)$/
	or $config_vars{'DEBUILD_TGZ_CHECK'}='yes';

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }

    # What did we find?
    $preserve_env = $config_vars{'DEBUILD_PRESERVE_ENV'} eq 'yes' ? 1 : 0;
    if ($config_vars{'DEBUILD_PRESERVE_ENVVARS'} ne '') {
	my @preserve_vars = split /\s*,\s*/,
	    $config_vars{'DEBUILD_PRESERVE_ENVVARS'};
	foreach my $index (0 .. $#preserve_vars) {
	    my $var = $preserve_vars[$index];
	    if ($var =~ /\*$/) {
		$var =~ s/([^.])\*$/$1.\*/;
		my @vars = grep /^$var$/, keys %ENV;
		push @preserve_vars, @vars;
		delete $preserve_vars[$index];
	    }
	}
	@preserve_vars = map {$_ if defined $_} @preserve_vars;
	@save_vars{@preserve_vars} = (1) x scalar @preserve_vars;
    }
    $run_lintian = $config_vars{'DEBUILD_LINTIAN'} eq 'no' ? 0 : 1;
    $root_command = $config_vars{'DEBUILD_ROOTCMD'};
    $tgz_check = $config_vars{'DEBUILD_TGZ_CHECK'} eq 'yes' ? 1 : 0;
    $prepend_path = $config_vars{'DEBUILD_PREPEND_PATH'};
    $username = $config_vars{'DEBUILD_SIGNING_USERNAME'};
    $check_dirname_level = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
    $check_dirname_regex = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_REGEX'};
    for my $hookname (@hooks) {
	my $config_name = uc "debuild_${hookname}_hook";
	$config_name =~ tr/-/_/;
	$hook{$hookname} = $config_vars{$config_name};
    }

    # Now parse the opts lists
    if (shift @othervars ne ">>> $dpkg_opts_var BEGIN <<<") {
	fatal "internal error: dpkg opts list missing proper header";
    }
    while (($_ = shift @othervars) ne ">>> $dpkg_opts_var END <<<"
	   and @othervars) {
	push @dpkg_extra_opts, $_;
    }
    if (! @othervars) {
	fatal "internal error: dpkg opts list missing proper trailer";
    }
    if (@dpkg_extra_opts) {
	$modified_conf_msg .= "  $dpkg_opts_var='" . join(" ", @dpkg_extra_opts) . "'\n";
    }

    if (shift @othervars ne ">>> $lintian_opts_var BEGIN <<<") {
	fatal "internal error: lintian opts list missing proper header";
    }
    while (($_ = shift @othervars) ne ">>> $lintian_opts_var END <<<"
	   and @othervars) {
	push @lintian_extra_opts, $_;
    }
    if (! @othervars) {
	fatal "internal error: lintian opts list missing proper trailer";
    }
    if (@lintian_extra_opts) {
	$modified_conf_msg .= "  $lintian_opts_var='" . join(" ", @lintian_extra_opts) . "'\n";
    }

    # And what is left should be any ENV settings
    foreach my $confvar (@othervars) {
	$confvar =~ /^DEBUILD_SET_ENVVAR_([^=]*)=(.*)$/ or next;
	$ENV{$1}=$2;
	$save_vars{$1}=1;
	$modified_conf_msg .= "  $1='$2'\n";
    }

    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;
}


# We first check @dpkg_extra_opts for options which may affect us;
# these were set in a configuration file, so they have lower
# precedence than command line settings.  The options we care about
# at this stage are: -r and those which affect the checkbuilddep setting

foreach (@dpkg_extra_opts) {
    /^-r(.*)$/ and $root_command=$1, next;
    $_ eq '-d' and $checkbuilddep=0, next;
    $_ eq '-D' and $checkbuilddep=1, next;
}

# Check @ARGV for debuild options.
my @preserve_vars = qw(TERM HOME LOGNAME PGPPATH GNUPGHOME GPG_AGENT_INFO
		     DBUS_SESSION_BUS_ADDRESS GPG_TTY FAKEROOTKEY LANG DEBEMAIL);
@save_vars{@preserve_vars} = (1) x scalar @preserve_vars;
{
    no locale;
    while (my $arg=shift) {
	my $savearg = $arg;
	my $opt = '';

	$arg =~ /^(-h|--help)$/ and usage(), exit 0;
	$arg eq '--version' and version(), exit 0;

	# Let's do the messy case first
	if ($arg eq '--preserve-envvar') {
	    unless (defined ($opt = shift)) {
		fatal "--preserve-envvar requires an argument,\nrun $progname --help for usage information";
	    }
	    $savearg .= " $opt";
	}
	elsif ($arg =~ /^--preserve-envvar=(.*)/) {
	    $arg = '--preserve-envvar';
	    $opt = $1;
	}
	elsif ($arg eq '--set-envvar') {
	    unless (defined ($opt = shift)) {
		fatal "--set-envvar requires an argument,\nrun $progname --help for usage information";
	    }
	    $savearg .= " $opt";
	}
	elsif ($arg =~ /^--set-envvar=(.*)/) {
	    $arg = '--set-envvar';
	    $opt = $1;
	}
	# dpkg-buildpackage now has a -e option, so we have to be
	# careful not to confuse the two; their option will always have
	# the form -e<maintainer email> or similar
	elsif ($arg eq '-e') {
	    unless (defined ($opt = shift)) {
		fatal "-e requires an argument,\nrun $progname --help for usage information";
	    }
	    $savearg .= " $opt";
	    if ($opt =~ /^\w+\*?$/) { $arg = '--preserve-envvar'; }
	    else { $arg = '--set-envvar'; }
	}
	elsif ($arg =~ /^-e(\w+\*?)$/) {
	    $arg = '--preserve-envvar';
	    $opt = $1;
	}
	elsif ($arg =~ /^-e(\w+=.*)$/) {
	    $arg = '--set-envvar';
	    $opt = $1;
	}
	elsif ($arg =~ /^-e/) {
	    # seems like a dpkg-buildpackage option, so stop parsing
	    unshift @ARGV, $arg;
	    last;
	}

	if ($arg eq '--preserve-envvar') {
	    if ($opt =~ /^\w+$/) {
		$save_vars{$opt}=1;
	    } elsif ($opt =~ /^\w+\*$/) {
		$opt =~ s/([^.])\*$/$1.\*/;
		my @vars = grep /^$opt$/, keys %ENV;
		@save_vars{@vars} = (1) x scalar @vars;
	    } else {
		push @warnings,
		    "Ignoring unrecognised/malformed option: $savearg";
	    }
	    next;
	}
	if ($arg eq '--set-envvar') {
	    if ($opt =~ /^(\w+)=(.*)$/) {
		$ENV{$1}=$2;
		$save_vars{$1}=1;
	    } else {
		push @warnings,
		    "Ignoring unrecognised/malformed option: $savearg";
	    }
	    next;
	}

	$arg eq '--preserve-env' and $preserve_env=1, next;
	if ($arg eq '-E') {
	    push @warnings,
	        "-E is deprecated in debuild, as dpkg-buildpackage now uses it.\nPlease use --preserve-env instead in future.\n";
	    $preserve_env=1;
	    next;
	}
	$arg eq '--no-lintian' and $run_lintian=0, next;
	$arg eq '--lintian' and $run_lintian=1, next;
	if ($arg eq '--rootcmd') {
	    unless (defined ($root_command = shift)) {
		fatal "--rootcmd requires an argument,\nrun $progname --help for usage information";
	    }
	    next;
	}
	$arg =~ /^--rootcmd=(.*)/ and $root_command=$1, next;
	if ($arg eq '-r') {
	    unless (defined ($opt = shift)) {
		fatal "-r requires an argument,\nrun $progname --help for usage information";
	    }
	    $root_command=$opt;
	    next;
	}
	$arg eq '--tgz-check' and $tgz_check=1, next;
	$arg =~ /^--no-?tgz-check$/ and $tgz_check=0, next;
	$arg =~ /^-r(.*)/ and $root_command=$1, next;
	if ($arg =~ /^--check-dirname-level=(.*)$/) {
	    $arg = '--check-dirname-level';
	    unshift @ARGV, $1;
	} # fall through and let the next one handle it ;-)
	if ($arg eq '--check-dirname-level') {
	    unless (defined ($opt = shift)) {
		fatal "--check-dirname-level requires an argument,\nrun $progname --help for usage information";
	    }
	    if ($opt =~ /^[012]$/) { $check_dirname_level = $opt; }
	    else {
		fatal "unrecognised --check-dirname-level value (allowed are 0,1,2)";
	    }
	    next;
	}
	if ($arg eq '--check-dirname-regex') {
	    unless (defined ($opt = shift)) {
		fatal "--check-dirname-regex requires an argument,\nrun $progname --help for usage information";
	    }
	    $check_dirname_regex = $opt;
	    next;
	}
	if ($arg =~ /^--check-dirname-regex=(.*)$/) {
	    $check_dirname_regex = $1;
	    next;
	}

	if ($arg eq '--prepend-path') {
	    unless (defined ($opt = shift)) {
		fatal "--prepend-path requires an argument,\nrun $progname --help for usage information";
	    }
	    $prepend_path = $opt;
	    next;
	}
	if ($arg =~ /^--prepend-path=(.*)$/) {
	    $prepend_path = $1;
	    next;
	}

 	if ($arg eq '--username') {
	    unless (defined ($opt = shift)) {
		fatal "--username requires an argument,\nrun $progname --help for usage information";
	    }
	    $username = $opt;
	    next;
	}
	if ($arg =~ /^--username=(.*)$/) {
	    $username = $1;
	    next;
	}

	if ($arg =~ /^--no-?conf$/) {
	    fatal "$arg is only acceptable as the first command-line option!";
	}
	$arg eq '-d' and $checkbuilddep=0, next;
	$arg eq '-D' and $checkbuilddep=1, next;

	# hooks...
	if ($arg =~ /^--(.*)-hook$/) {
	    my $argkey = $1;
	    unless (exists $hook{$argkey}) {
		fatal "unknown hook $arg,\nrun $progname --help for usage information";
	    }
	    unless (defined ($opt = shift)) {
		fatal "$arg requires an argument,\nrun $progname --help for usage information";
	    }
	    $hook{$argkey} = $opt;
	    next;
	}

	if ($arg =~ /^--(.*?)-hook=(.*)/) {
	    my $argkey = $1;
	    my $opt = $2;

	    unless (exists $hook{$argkey}) {
		fatal "unknown hook option $arg,\nrun $progname --help for usage information";
	    }

	    $hook{$argkey} = $opt;
	    next;
	}

	if ($arg =~ /^--hook-(sign|done)=(.*)$/) {
	    my $name = $1;
	    my $opt = $2;
	    unless (defined($opt)) {
		fatal "$arg requires an argmuent,\nrun $progname --help for usage information";
	    }
	    if ($name eq 'sign') {
		$hook{signing} = $opt;
	    }
	    else {
		$hook{'post-dpkg-buildpackage'} = $opt;
	    }
	    next;
	}

	if ($arg eq '--clear-hooks') { $hook{@hooks} = ('') x @hooks; next; }

	# Not a debuild option, so give up.
	unshift @ARGV, $arg;
	last;
    }
}

if ($save_vars{'PATH'}) {
    # Untaint PATH.  Very dangerous in general, but anyone running this
    # as root can do anything anyway.
    $ENV{'PATH'} =~ /^(.*)$/;
    $ENV{'PATH'} = $1;
} else {
    $ENV{'PATH'} = "/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/X11";
    $ENV{'PATH'} = join(':', $prepend_path, $ENV{'PATH'}) if $prepend_path;
}
$save_vars{'PATH'}=1;
$ENV{'TERM'}='dumb' unless exists $ENV{'TERM'};

# Store a few variables for safe keeping.
my %store_vars;
foreach my $var (('DBUS_SESSION_BUS_ADDRESS', 'DISPLAY', 'GNOME_KEYRING_SOCKET', 'GPG_AGENT_INFO', 'SSH_AUTH_SOCK', 'XAUTHORITY')) {
    $store_vars{$var} = $ENV{$var} if defined $ENV{$var};
}

unless ($preserve_env) {
    foreach my $var (keys %ENV) {
	delete $ENV{$var} unless
	    $save_vars{$var} or $var =~ /^(LC|DEB)_[A-Z_]+$/
	    or $var =~ /^(C(PP|XX)?|LD|F)FLAGS(_APPEND)?$/;
    }
}

umask 022;

# Start by duping STDOUT and STDERR
open OLDOUT, ">&", \*STDOUT or fatal "can't dup stdout: $!\n";
open OLDERR, ">&", \*STDERR or fatal "can't dup stderr: $!\n";

# Look for the debian changelog
my $chdir = 0;
until (-r 'debian/changelog') {
    $chdir = 1;
    chdir '..' or fatal "can't chdir ..: $!";
    if (cwd() eq '/') {
	fatal "cannot find readable debian/changelog anywhere!\nAre you in the source code tree?";
    }
}

# Find the source package name and version number
my %changelog;
my $c = changelog_parse();
@changelog{'Source', 'Version'} = @{$c}{'Source', 'Version'};

fatal "no package name in changelog!"
    unless exists $changelog{'Source'};
my $pkg = $changelog{'Source'};
fatal "no version number in changelog!"
    unless exists $changelog{'Version'};
my $version = $changelog{'Version'};
(my $sversion=$version) =~ s/^\d+://;
(my $uversion=$sversion) =~ s/-[a-z0-9+\.]+$//i;

# Is the directory name acceptable?
if ($check_dirname_level ==  2 or
    ($check_dirname_level == 1 and $chdir)) {
    my $re = $check_dirname_regex;
    $re =~ s/PACKAGE/\\Q$pkg\\E/g;
    my $gooddir;
    if ($re =~ m%/%) { $gooddir = eval "cwd() =~ /^$re\$/;"; }
    else { $gooddir = eval "basename(cwd()) =~ /^$re\$/;"; }

    if (! $gooddir) {
	my $pwd = cwd();
	die <<"EOF";
$progname: found debian/changelog for package $pkg in the directory
  $pwd
but this directory name does not match the package name according to the
regex  $check_dirname_regex.

To run $progname on this package, see the --check-dirname-level and
--check-dirname-regex options; run $progname --help for more info.
EOF
    }
}


if (! -f "debian/rules")
{
    my $cwd = cwd();
    fatal "found debian/changelog in directory\n  $cwd\nbut there's no debian/rules there!  Are you in the source code tree?";
}

if ( ! -x _ ) {
    push @warnings, "Making debian/rules executable!\n";
    chmod 0755, "debian/rules" or
	fatal "couldn't make debian/rules executable: $!";
}

# Pick up superuser privileges if we are running set[ug]id root
my $uid=$<;
if ( $< != 0 && $> == 0 ) { $< = $> }
my $gid=$(;
if ( $( != 0 && $) == 0 ) { $( = $) }

# Our first task is to parse the command line options.

# dpkg-buildpackage variables explicitly initialised in dpkg-buildpackage
my $signsource=1;
my $signchanges=1;
my $binarytarget='binary';
my $since='';
my $usepause=0;

# extra dpkg-buildpackage variables not initialised there
my $sourceonly='';
my $binaryonly='';
my $targetarch='';
my $targetgnusystem='';

my $dirn = basename(cwd());

# and one for us
my @debsign_opts = ();
# and one for dpkg-buildpackage if needed
my @dpkg_opts = qw(-us -uc);

my %debuild2dpkg = (
    'dpkg-buildpackage' => 'init',
    'clean' => 'preclean',
    'dpkg-source' => 'source',
    'build' => 'build',
    'binary' => 'binary',
    'dpkg-genchanges' => 'changes',
    'postclean' => 'final-clean',
    'lintian' => 'check',
);

for my $h_name (@hooks) {
    if (exists $debuild2dpkg{$h_name} && $hook{$h_name}) {
	push(@dpkg_opts,
	    sprintf('--hook-%s=%s', $debuild2dpkg{$h_name}, $hook{$h_name}));
	delete $hook{$h_name};
    }
}

# Parse dpkg-buildpackage options
# First process @dpkg_extra_opts from above

foreach (@dpkg_extra_opts) {
    $_ eq '-h' and
	warn "You have a -h option in your configuration file!  Ignoring.\n", next;
    /^-r/ and next;  # already been processed
    /^-p/ and push(@debsign_opts, $_), next;  # Key selection options
    /^-k/ and push(@debsign_opts, $_), next;  # Ditto
    /^-[dD]$/ and next;  # already been processed
    $_ eq '-us' and $signsource=0, next;
    $_ eq '-uc' and $signchanges=0, next;
    $_ eq '-ap' and $usepause=1, next;
    /^-a(.*)/ and $targetarch=$1, push(@dpkg_opts, $_), next;
    /^-t(.*)/ and $targetgnusystem=$1, push(@dpkg_opts, $_), next; # Ditto
    $_ eq '-b' and $binaryonly=$_, $binarytarget='binary',
	push(@dpkg_opts, $_), next;
    $_ eq '-B' and $binaryonly=$_, $binarytarget='binary-arch',
	push(@dpkg_opts, $_), next;
    $_ eq '-A' and $binaryonly=$_, $binarytarget='binary-indep',
	push(@dpkg_opts, $_), next;
    $_ eq '-S' and $sourceonly=$_, push(@dpkg_opts, $_), next;
    $_ eq '-F' and $binarytarget='binary', push(@dpkg_opts, $_), next;
    $_ eq '-G' and $binarytarget='binary-arch', push(@dpkg_opts, $_), next;
    $_ eq '-g' and $binarytarget='binary-indep', push(@dpkg_opts, $_), next;
    if (/^--build=(.*)$/) {
	my $argstr = $_;
	my @builds = split(/,/, $1);
	my ($binary, $source);
	for my $build (@builds) {
	    if ($build =~ m/^(?:binary|full)$/) {
		$source++ if $1 eq 'full';
		$binary++;
		$binarytarget = 'binary';
	    }
	    elsif ($build eq 'any') {
		$binary++;
		$binarytarget = 'binary-arch';
	    }
	    elsif ($build eq 'all') {
		$binary++;
		$binarytarget = 'binary-indep';
	    }
	}
	$binaryonly = (!$source && $binary);
	$sourceonly = ($source && !$binary);
	push(@dpkg_opts, $argstr);
    }
    /^-v(.*)/ and $since=$1, push(@dpkg_opts, $_), next;
    /^-m(.*)/ and push(@debsign_opts, $_), push(@dpkg_opts, $_), next;
    /^-e(.*)/ and push(@debsign_opts, $_), push(@dpkg_opts, $_), next;
    push (@dpkg_opts, $_);
}

while ($_=shift) {
    $_ eq '-h' and usage(), exit 0;
    /^-r(.*)/ and $root_command=$1, next;
    /^-p/ and push(@debsign_opts, $_), next;  # Key selection options
    /^-k/ and push(@debsign_opts, $_), next;  # Ditto
    $_ eq '-us' and $signsource=0, next;
    $_ eq '-uc' and $signchanges=0, next;
    $_ eq '-ap' and $usepause=1, next;
    /^-a(.*)/ and $targetarch=$1, push(@dpkg_opts, $_),
	next;
    /^-t(.*)/ and $targetgnusystem=$1, next;
    $_ eq '-b' and $binaryonly=$_, $binarytarget='binary',
	push(@dpkg_opts, $_), next;
    $_ eq '-B' and $binaryonly=$_, $binarytarget='binary-arch',
	push(@dpkg_opts, $_), next;
    $_ eq '-A' and $binaryonly=$_, $binarytarget='binary-indep',
	push(@dpkg_opts, $_), next;
    $_ eq '-S' and $sourceonly=$_, push(@dpkg_opts, $_), next;
    $_ eq '-F' and $binarytarget='binary', push(@dpkg_opts, $_), next;
    $_ eq '-G' and $binarytarget='binary-arch', push(@dpkg_opts, $_), next;
    $_ eq '-g' and $binarytarget='binary-indep', push(@dpkg_opts, $_), next;
    if (/^--build=(.*)$/) {
	my $argstr = $_;
	my @builds = split(/,/, $1);
	my ($binary, $source);
	for my $build (@builds) {
	    if ($build =~ m/^(?:binary|full)$/) {
		$source++ if $1 eq 'full';
		$binary++;
		$binarytarget = 'binary';
	    }
	    elsif ($build eq 'any') {
		$binary++;
		$binarytarget = 'binary-arch';
	    }
	    elsif ($build eq 'all') {
		$binary++;
		$binarytarget = 'binary-indep';
	    }
	}
	$binaryonly = (!$source && $binary);
	$sourceonly = ($source && !$binary);
	push(@dpkg_opts, $argstr);
    }
    /^-v(.*)/ and $since=$1, push(@dpkg_opts, $_), next;
    /^-m(.*)/ and push(@debsign_opts, $_), push(@dpkg_opts, $_), next;
    /^-e(.*)/ and push(@debsign_opts, $_), push(@dpkg_opts, $_), next;

    # these non-dpkg-buildpackage options make us stop
    if ($_ eq '--lintian-opts') {
	unshift @ARGV, $_;
	last;
    }
    push (@dpkg_opts, $_);
}

# Pick up lintian options if necessary
if (@ARGV) {
    # Check that option is sensible
    if ($ARGV[0] eq '--lintian-opts') {
	if (! $run_lintian) {
	    push @warnings,
		"$ARGV[0] option given but not running lintian!";
	}
	shift;
	push(@lintian_opts, @ARGV);
    }
    else {
	# It must be a debian/rules target
	push(@dpkg_opts, '--target', @ARGV);
    }
}

if ($signchanges==1 and $signsource==0) {
    push @warnings,
	"I will sign the .dsc file anyway as a signed .changes file was requested\n";
    $signsource=1;  # may not be strictly necessary, but for clarity!
}

# Next dpkg-buildpackage steps:
# mustsetvar package/version have been done above; we've called the
# results $pkg and $version
# mustsetvar maintainer is only needed for signing, so we leave that
# to debsign or dpkg-sig
# Call to dpkg-architecture to set DEB_{BUILD,HOST}_* environment
# variables
my @dpkgarch = 'dpkg-architecture';
if ($targetarch) {
    push @dpkgarch, "-a${targetarch}";
}
if ($targetgnusystem) {
    push @dpkgarch, "-t${targetgnusystem}";
}
push @dpkgarch, '-f';

my $archinfo;
spawn(exec => [@dpkgarch],
      to_string => \$archinfo,
      wait_child => 1);
foreach (split /\n/, $archinfo) {
    /^(.*)=(.*)$/ and $ENV{$1} = $2;
}

# We need to do the arch, pv, pva stuff to figure out
# what the changes file will be called,
my ($arch, $dsc, $changes, $build);
if ($sourceonly) {
    $arch = 'source';
} elsif ($binarytarget eq 'binary-indep') {
    $arch = 'all';
} else {
    $arch = $ENV{DEB_HOST_ARCH};
}

# Handle dpkg source format "3.0 (git)" packages (no tarballs)
if ( -r "debian/source/format" ) {
    open FMT, "debian/source/format" or die $!;
    my $srcfmt = <FMT>; close FMT; chomp $srcfmt;
    if ( $srcfmt eq "3.0 (git)" ) { $tgz_check = 0; }
}

$dsc = "${pkg}_${sversion}.dsc";
my $orig_prefix = "${pkg}_${uversion}.orig.tar";
my $origdir = basename(cwd()) . ".orig";
if (! $binaryonly and $tgz_check and $uversion ne $sversion
    and ! -f "../${orig_prefix}.bz2" and ! -f "../${orig_prefix}.lzma"
    and ! -f "../${orig_prefix}.gz" and ! -f "../${orig_prefix}.xz"
    and ! -d "../$origdir") {
    print STDERR "This package has a Debian revision number but there does"
	. " not seem to be\nan appropriate original tar file or .orig"
	. " directory in the parent directory;\n(expected one of"
	. " ${orig_prefix}.gz, ${orig_prefix}.bz2,\n${orig_prefix}.lzma, "
	. " ${orig_prefix}.xz or $origdir)\ncontinue anyway? (y/n) ";
    my $ans = <STDIN>;
    exit 1 unless $ans =~ /^y/i;
}

# Convert debuild-specific _APPEND variables to those recognized by
# dpkg-buildpackage
my @buildflags = qw(CPPFLAGS CFLAGS CXXFLAGS FFLAGS LDFLAGS);
foreach my $flag (@buildflags) {
    if (exists $ENV{"${flag}_APPEND"}) {
	$ENV{"DEB_${flag}_APPEND"} = delete $ENV{"${flag}_APPEND"};
    }
}

# We'll need to be a bit cleverer to determine the changes file name;
# see below
$build="${pkg}_${sversion}_${arch}.build";
$changes="${pkg}_${sversion}_${arch}.changes";
open BUILD, "| tee ../$build" or fatal "couldn't open pipe to tee: $!";
$logging=1;
close STDOUT;
close STDERR;
open STDOUT, ">&BUILD" or fatal "can't reopen stdout: $!";
open STDERR, ">&BUILD" or fatal "can't reopen stderr: $!";

if (defined($checkbuilddep)) {
    unshift @dpkg_opts, ($checkbuilddep ? "-D" : "-d");
}
if ($run_lintian) {
    push(@dpkg_opts, '--check-command=lintian',
	map { "--check-option=$_" } @lintian_opts);
}
unshift @dpkg_opts, "-r$root_command" if $root_command;
system_withecho('dpkg-buildpackage', @dpkg_opts);

chdir '..' or fatal "can't chdir: $!";

open CHANGES, '<', $changes or fatal "can't open $changes for reading: $!";
my @changefilecontents = <CHANGES>;
close CHANGES;

# check Ubuntu merge Policy: When merging with Debian, -v must be used
# and the remaining changes described
my $ch = join "\n", @changefilecontents;
if ($sourceonly && $version =~ /ubuntu1$/ && $ENV{'DEBEMAIL'} =~ /ubuntu/ &&
    $ch =~ /(merge|sync).*Debian/i) {
    push (@warnings, "Ubuntu merge policy: when merging Ubuntu packages with Debian, -v must be used") unless $since;
    push (@warnings, "Ubuntu merge policy: when merging Ubuntu packages with Debian, changelog must describe the remaining Ubuntu changes")
	unless $ch =~ /Changes:.*(remaining|Ubuntu)(.|\n )*(differen|changes)/is;
}

# They've insisted.  Who knows why?!
if (($signchanges or $signsource) and $usepause) {
    print "Press the return key to start signing process\n";
    <STDIN>;
}

run_hook('signing', ($signchanges || (! $sourceonly and $signsource)) );

if ($signchanges) {
    foreach my $var (keys %store_vars) {
	$ENV{$var} = $store_vars{$var};
    }
    print "Now signing changes and any dsc files...\n";
    if ($username) {
	system('debrsign', @debsign_opts, $username, $changes) == 0
	    or fatal "running debrsign failed";
    } else {
	system('debsign', @debsign_opts, $changes) == 0
	    or fatal "running debsign failed";
    }
}
elsif (! $sourceonly and $signsource) {
    print "Now signing dsc file...\n";
    if ($username) {
	system('debrsign', @debsign_opts, $username, $dsc) == 0
	    or fatal "running debrsign failed";
    } else {
	system('debsign', @debsign_opts, $dsc) == 0
	    or fatal "running debsign failed";
    }
}

run_hook('post-dpkg-buildpackage', 1);

# Any warnings?
if (@warnings) {
    # Don't know why we need this, but seems that we do, otherwise,
    # the warnings get muddled up with the other output.
    IO::Handle::flush(\*STDOUT);

    my $warns = @warnings > 1 ? "S" : "";
    warn "\nWARNING$warns generated by $progname:\n" .
	join("\n", @warnings) . "\n";
}
# close the logging process
close STDOUT;
close STDERR;
close BUILD;
open STDOUT, ">&", \*OLDOUT;
open STDERR, ">&", \*OLDERR;
exit 0;

###### Subroutines

sub system_withecho(@) {
    print STDERR " ", join(" ", @_), "\n";
    system(@_);
    if ($?>>8) {
	fatal "@_ failed";
    }
}

sub run_hook ($$) {
    my ($hook, $act) = @_;
    return unless $hook{$hook};

    print STDERR " Running $hook-hook\n";
    my $hookcmd = $hook{$hook};
    $act = $act ? 1 : 0;
    my %per=("%"=>"%", "p"=>$pkg, "v"=>$version, "s"=>$sversion, "u"=>$uversion, "a"=>$act);
    $hookcmd =~ s/\%(.)/exists $per{$1} ? $per{$1} :
	(warn ("Unrecognised \% substitution in hook: \%$1\n"), "\%$1")/eg;

    system_withecho($hookcmd);

    if ($?>>8) {
	warn "$progname: $hook-hook failed\n";
	exit ($?>>8);
    }
}

sub fatal($) {
    my ($pack,$file,$line);
    ($pack,$file,$line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    # redirect stderr before we die...
    if ($logging) {
	close STDOUT;
	close STDERR;
	close BUILD;
	open STDOUT, ">&", \*OLDOUT;
	open STDERR, ">&", \*OLDERR;
    }
    die $msg;
}
