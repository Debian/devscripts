#! /usr/bin/perl -w

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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


# We will do simple option processing.  The calling syntax of this
# program is:
#
#   debuild [<debuild options>] binary|binary-arch|binary-indep|clean ...
# or
#   debuild [<debuild options>] [<dpkg-buildpackage options>]
#            [--lintian-opts <lintian options>] [--linda-opts <linda options>]
#
# In the first case, debuild will simply run debian/rules with the
# given parameter.  Available options are listed in usage() below.
#
# In the second case, the behaviour is to run dpkg-buildpackage and
# then to run lintian and/or linda on the resulting .changes file.
# (Running lintian only is the default.)  Lintian and linda options
# may be specified after --lintian-opts and --linda-opts respectively;
# all following options will be passed only to lintian/linda.
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
use 5.008;
use File::Basename;
use filetest 'access';
use Cwd;
use IO::Handle;  # for flushing
use vars qw(*BUILD *OLDOUT *OLDERR);  # prevent a warning

my $progname=basename($0);
my $modified_conf_msg;
my @warnings;

# Predeclare functions
sub system_withecho(@);
sub run_hook ($$);
sub fileomitted (\@$);
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
                (default: 'PACKAGE(-.*)?')

        --help, -h    display this message

        --version     show version and copyright information

Second usage method:
  $progname [<debuild options>] [<dpkg-buildpackage options>]
             [--lintian-opts <lintian options>] [--linda-opts <linda options>]
    to run dpkg-buildpackage and then run lintian and/or linda on the
    resulting .changes file.

    Additional debuild options available in this case are:

        --lintian           Run lintian (default)
        --linda             Run linda
        --no-lintian        Do not run lintian
        --no-linda          Do not run linda (default)
        --[no-]tgz-check    Do [not] check for an .orig.tar.gz before running
                            dpkg-buildpackage if we have a Debian revision
                            (Default: check) 

        --dpkg-buildpackage-hook=HOOK
        --clean-hook=HOOK
        --dpkg-source-hook=HOOK
        --build-hook=HOOK
        --binary-hook=HOOK
        --final-clean-hook=HOOK
        --lintian-hook=HOOK
        --signing-hook=HOOK
        --post-dpkg-buildpackage-hook=HOOK
                            These hooks run at the various stages of the
                            dpkg-buildpackage run.  For details, see the
                            debuild manpage.  They default to nothing, and
                            can be reset to nothing with --foo-hook=''
	--clear-hooks       Clear all hooks

    For available dpkg-buildpackage and lintian/linda options, see their
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
my $run_linda=0;
my $lintian_exists=0;
my $linda_exists=0;
my @dpkg_extra_opts=();
my @lintian_extra_opts=();
my @lintian_opts=();
my @linda_extra_opts=();
my @linda_opts;
my $checkbuilddep=1;
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.*)?';
my $logging=0;
my $tgz_check=1;
my @hooks = (qw(dpkg-buildpackage clean dpkg-source build binary final-clean
		lintian signing post-dpkg-buildpackage));
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
		       'DEBUILD_LINDA' => 'no',
		       'DEBUILD_ROOTCMD' => 'fakeroot',
		       'DEBUILD_TGZ_CHECK' => 'yes',
		       'DEBUILD_DPKG_BUILDPACKAGE_HOOK' => '',
		       'DEBUILD_CLEAN_HOOK' => '',
		       'DEBUILD_DPKG_SOURCE_HOOK' => '',
		       'DEBUILD_BUILD_HOOK' => '',
		       'DEBUILD_BINARY_HOOK' => '',
		       'DEBUILD_FINAL_CLEAN_HOOK' => '',
		       'DEBUILD_LINTIAN_HOOK' => '',
		       'DEBUILD_SIGNING_HOOK' => '',
		       'DEBUILD_POST_DPKG_BUILDPACKAGE_HOOK' => '',
		       'DEVSCRIPTS_CHECK_DIRNAME_LEVEL' => 1,
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.*)?',
		       );
    my %config_default = %config_vars;
    my $dpkg_opts_var = 'DEBUILD_DPKG_BUILDPACKAGE_OPTS';
    my $lintian_opts_var = 'DEBUILD_LINTIAN_OPTS';
    my $linda_opts_var = 'DEBUILD_LINDA_OPTS';

    my $shell_cmd;
    # Set defaults
    $shell_cmd .= qq[unset `set | grep "^DEBUILD_" | cut -d= -f1`;\n];
    foreach my $var (keys %config_vars) {
	$shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    foreach my $var ($dpkg_opts_var, $lintian_opts_var, $linda_opts_var) {
	$shell_cmd .= "$var='';\n";
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    foreach my $var ($dpkg_opts_var, $lintian_opts_var, $linda_opts_var) {
	$shell_cmd .= "eval set -- \$$var;\n";
	$shell_cmd .= "echo \">>> $var BEGIN <<<\";\n";
	$shell_cmd .= 'while [ $# -gt 0 ]; do echo $1; shift; done;' . "\n";
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
    $config_vars{'DEBUILD_LINDA'} =~ /^(yes|no)$/
	or $config_vars{'DEBUILD_LINDA'}='no';
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
	@save_vars{@preserve_vars} = (1) x scalar @preserve_vars;
    }
    $run_lintian = $config_vars{'DEBUILD_LINTIAN'} eq 'no' ? 0 : 1;
    $run_linda = $config_vars{'DEBUILD_LINDA'} eq 'yes' ? 1 : 0;
    $root_command = $config_vars{'DEBUILD_ROOTCMD'};
    $tgz_check = $config_vars{'DEBUILD_TGZ_CHECK'} eq 'yes' ? 1 : 0;
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

    if (shift @othervars ne ">>> $linda_opts_var BEGIN <<<") {
	fatal "internal error: linda opts list missing proper header";
    }
    while (($_ = shift @othervars) ne ">>> $linda_opts_var END <<<"
	   and @othervars) {
	push @linda_extra_opts, $_;
    }
    if (! @othervars) {
	fatal "internal error: linda opts list missing proper trailer";
    }
    if (@linda_extra_opts) {
	$modified_conf_msg .= "  $linda_opts_var='" . join(" ", @linda_extra_opts) . "'\n";
    }

    # And what is left should be any ENV settings
    foreach my $envvar (@othervars) {
	$envvar =~ /^DEBUILD_SET_ENVVAR_([^=]*)=(.*)$/ or next;
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
    /^-a(.*)/ and $_ ne '-ap' and $checkbuilddep=0, next;
    $_ eq '-S' and $checkbuilddep=0, next;
}

# Check @ARGV for debuild options.
my @preserve_vars = qw(TERM HOME LOGNAME PGPPATH GNUPGHOME GPG_AGENT_INFO
		     GPG_TTY FAKEROOTKEY LANG);
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
	    if ($opt =~ /^\w+$/) { $arg = '--preserve-envvar'; }
	    else { $arg = '--set-envvar'; }
	}
	elsif ($arg =~ /^-e(\w+)$/) {
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
	$arg eq '--no-linda' and $run_linda=0, next;
	$arg eq '--linda' and $run_linda=1, next;
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
	if ($arg eq '--ignore-dirname') {
	    fatal "--ignore-dirname has been replaced by --check-dirname-level and\n--check-dirname-regex; run $progname --help for more details";
	}
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
    $ENV{'PATH'} = "/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/X11"
}
$save_vars{'PATH'}=1;
$ENV{'TERM'}='dumb' unless exists $ENV{'TERM'};

unless ($preserve_env) {
    foreach my $var (keys %ENV) {
	delete $ENV{$var} unless
	    $save_vars{$var} or $var =~ /^(LC|DEB(SIGN)?)_[A-Z_]+$/;
    }
}

umask 022;

# Start by duping STDOUT and STDERR
open OLDOUT, ">&STDOUT" or fatal "can't dup stdout: $!\n";
open OLDERR, ">&STDERR" or fatal "can't dup stderr: $!\n";

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
open PARSED, q[dpkg-parsechangelog | grep '^\(Source\|Version\):' |]
    or fatal "cannot execute dpkg-parsechangelog | grep: $!";
while (<PARSED>) {
    chomp;
    if (/^(\S+):\s(.+?)\s*$/) { $changelog{$1}=$2; }
    else {
	fatal "don't understand dpkg-parsechangelog output: $_";
    }
}

close PARSED
    or fatal "problem executing dpkg-parsechangelog | grep: $!";
if ($?) { fatal "dpkg-parsechangelog | grep failed!" }

fatal "no package name in changelog!"
    unless exists $changelog{'Source'};
my $pkg = $changelog{'Source'};
fatal "no version number in changelog!"
    unless exists $changelog{'Version'};
my $version = $changelog{'Version'};

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

# Now let's look at our options, if any.  The first task is to decide
# which version of debuild we wish to run.  The rule is as follows: we
# want to run the first version (calling debian/rules explicitly) if
# there is at most one initial -r... argument, and all of the others
# are one of binary, binary-arch, binary-indep or clean.  We run the
# second version otherwise.  Note that the -r option is the only one
# stripped from the argument list.

my $command_version='rules';

if (@ARGV == 0) { $command_version='dpkg'; }
else {
    foreach (@ARGV) {
	if ( ! /^(binary|binary-indep|binary-arch|clean)$/) {
	    $command_version='dpkg';
	    last;
	}
    }
}

if ($command_version eq 'dpkg') {
    # We're going to emulate dpkg-buildpackage and possibly lintian/linda.
    # This will allow us to run hooks.
    # However, if dpkg-cross is installed (as evidenced by the presence
    # of /usr/bin/dpkg-cross), then we call the "real" dpkg-buildpackage,
    # which is actually dpkg-cross's version.  We lose the facility for
    # hooks in this case, but we're not going to emulate dpkg-cross as well!

    my $dpkg_cross = (-x '/usr/bin/dpkg-cross' ? 1 : 0);
    if ($dpkg_cross) {
	# check hooks
	my @skip_hooks = ();
	for my $hookname (qw(clean dpkg-source build binary dpkg-genchanges
			     final-clean)) {
	    if ($hook{$hookname}) { push @skip_hooks, $hookname; }
	}
	if (@skip_hooks) {
	    warn "$progname: dpkg-cross appears to be present on your system, and you have\nset up some hooks which will not be run (" .
		join(", ", @skip_hooks) . ");\ndo you wish to continue? (y/n) ";
	    my $ans = <STDIN>;
	    exit 1 unless $ans =~ /^y/i;
	}
    }

    # Our first task is to parse the command line options.

    # And before we get too excited, does lintian/linda even exist?
    if ($run_lintian) {
	system("command -v lintian >/dev/null 2>&1") == 0
	    and $lintian_exists=1;
    }
    if ($run_linda) {
	system("command -v linda >/dev/null 2>&1") == 0
	    and $linda_exists=1;
    }

    # dpkg-buildpackage variables explicitly initialised in dpkg-buildpackage
    my $signsource=1;
    my $signchanges=1;
    my $cleansource=0;
    my $binarytarget='binary';
    my $sourcestyle='';
    my $since='';
    my $maint='';
    my $desc='';
    my $noclean=0;
    my $usepause=0;
    my $warnable_error=0;  # OK, dpkg-buildpackage defines this but doesn't
                           # use it.  We'll keep it around just in case it
                           # does one day...
    my @passopts=();

    # extra dpkg-buildpackage variables not initialised there
    my $diffignore='';
    my @tarignore=();
    my $sourceonly='';
    my $binaryonly='';
    my $targetarch='';
    my $targetgnusystem='';
    my $changedby='';

    # and one for us
    my @debsign_opts = ();
    # and one for dpkg-cross if needed
    my @dpkg_opts = qw(-us -uc);

    # Parse dpkg-buildpackage options
    # First process @dpkg_extra_opts from above

    foreach (@dpkg_extra_opts) {
	$_ eq '-h' and
	    warn "You have a -h option in your configuration file!  Ignoring.\n", next;
	/^-r/ and next;  # already been processed
	/^-p/ and push(@debsign_opts, $_), next;  # Key selection options
	/^-k/ and push(@debsign_opts, $_), next;  # Ditto
	/^-[dD]$/ and next;  # already been processed
	/^-s(pgp|gpg)$/ and push(@debsign_opts, $_), next;  # Key selection
	$_ eq '-us' and $signsource=0, next;
	$_ eq '-uc' and $signchanges=0, next;
	$_ eq '-ap' and $usepause=1, next;
	/^-a(.*)/ and $targetarch=$1, push(@dpkg_opts, $_), next;
	    # Explained below; no implied -d here, as already done
	/^-s[iad]$/ and $sourcestyle=$_, push(@dpkg_opts, $_), next;
	/^-i/ and $diffignore=$_, push(@dpkg_opts, $_), next;
	/^-I/ and push(@tarignore, $_), push(@dpkg_opts, $_), next;
	$_ eq '-tc' and $cleansource=1, push(@dpkg_opts, $_), next;
	/^-t(.*)/ and $targetgnusystem=$1, push(@dpkg_opts, $_), next; # Ditto	
	$_ eq '-nc' and $noclean=1, $binaryonly ||= '-b', push(@dpkg_opts, $_),
	    next;
	$_ eq '-b' and $binaryonly=$_, push(@dpkg_opts, $_), next;
	$_ eq '-B' and $binaryonly=$_, $binarytarget='binary-arch',
	    push(@dpkg_opts, $_), next;
	$_ eq '-S' and $sourceonly=$_, push(@dpkg_opts, $_), next;
	    # Explained below, no implied -d
	/^-v(.*)/ and $since=$1, push(@dpkg_opts, $_), next;
	/^-m(.*)/ and $maint=$1, push(@debsign_opts, $_), push(@dpkg_opts, $_),
	    next;
	/^-e(.*)/ and $changedby=$1, push(@debsign_opts, $_),
	    push(@dpkg_opts, $_), next;
	/^-C(.*)/ and $desc=$1, push(@dpkg_opts, $_), next;
	$_ eq '-W' and $warnable_error=1, push(@passopts, $_),
	    push(@dpkg_opts, $_), next;
	$_ eq '-E' and $warnable_error=0, push(@passopts, $_),
	    push(@dpkg_opts, $_), next;
	# dpkg-cross specific option
	if (/^-M/ and $dpkg_cross) { push(@dpkg_opts, $_), next; }
	fatal "unknown dpkg-buildpackage option in configuration file: $_";
    }

    while ($_=shift) {
	$_ eq '-h' and usage(), exit 0;
	/^-r(.*)/ and $root_command=$1, next;
	/^-p/ and push(@debsign_opts, $_), next;  # Key selection options
	/^-k/ and push(@debsign_opts, $_), next;  # Ditto
	$_ eq '-d' and $checkbuilddep=0, next;
	$_ eq '-D' and $checkbuilddep=1, next;
	/^-s(pgp|gpg)$/ and push(@debsign_opts, $_), next;  # Key selection
	$_ eq '-us' and $signsource=0, next;
	$_ eq '-uc' and $signchanges=0, next;
	$_ eq '-ap' and $usepause=1, next;
	/^-a(.*)/ and $targetarch=$1, $checkbuilddep=0, push(@dpkg_opts, $_),
	    next;
	/^-s[iad]$/ and $sourcestyle=$_, push(@dpkg_opts, $_), next;
	/^-i/ and $diffignore=$_, push(@dpkg_opts, $_), next;
	/^-I/ and push(@tarignore, $_), push(@dpkg_opts, $_), next;
	$_ eq '-tc' and $cleansource=1, push(@dpkg_opts, $_), next;
	/^-t(.*)/ and $targetgnusystem=$1, $checkbuilddep=0, next;
	$_ eq '-nc' and $noclean=1, $binaryonly ||= '-b', push(@dpkg_opts, $_),
	    next;
	$_ eq '-b' and $binaryonly=$_, push(@dpkg_opts, $_), next;
	$_ eq '-B' and $binaryonly=$_, $binarytarget='binary-arch',
	    push(@dpkg_opts, $_), next;
	$_ eq '-S' and $sourceonly=$_, $checkbuilddep=0, push(@dpkg_opts, $_),
	    next;
	/^-v(.*)/ and $since=$1, push(@dpkg_opts, $_), next;
	/^-m(.*)/ and $maint=$1, push(@debsign_opts, $_), push(@dpkg_opts, $_),
	    next;
	/^-e(.*)/ and $changedby=$1, push(@debsign_opts, $_),
	    push(@dpkg_opts, $_), next;
	/^-C(.*)/ and $desc=$1, push(@dpkg_opts, $_), next;
	$_ eq '-W' and $warnable_error=1, push(@passopts, $_),
	    push(@dpkg_opts, $_), next;
	$_ eq '-E' and $warnable_error=0, push(@passopts, $_),
	    push(@dpkg_opts, $_), next;
	# dpkg-cross specific option
	if (/^-M/ and $dpkg_cross) { push(@dpkg_opts, $_), next; }

	# these non-dpkg-buildpackage options make us stop
	if ($_ eq '-L' or $_ eq '--lintian' or /^--(lintian|linda)-opts$/) {
	    unshift @ARGV, $_;
	    last;
	}
	fatal "unknown dpkg-buildpackage/debuild option: $_";
    }

    if ($sourceonly and $binaryonly) {
	fatal "cannot combine dpkg-buildpackage options $sourceonly and $binaryonly";
    }

    # Pick up lintian/linda options if necessary
    if (($run_lintian || $run_linda) && @ARGV) {
	# Check that option is sensible
    LIN_OPTS:
	while (@ARGV) {
	    my $whichlin = shift;
	    if ($whichlin eq '-L' or $whichlin eq '--lintian') {
		push @warnings,
		    "the $whichlin option is deprecated for indicating the start\nof lintian options, please use --lintian-opts instead\n  (I substituted -L with --lintian-opts this time)";
		$whichlin = '--lintian-opts';
	    }
	    if ($whichlin eq '--lintian-opts') {
		if (! $run_lintian) {
		    push @warnings,
		        "$whichlin option given but not running lintian!";
		}
		while ($_=shift) {
		    if (/^--(lintian|linda)-opts$/) {
			unshift @ARGV, $_;
			next LIN_OPTS;
		    }
		    push @lintian_opts, $_;
		}
	    }
	    elsif ($whichlin eq '--linda-opts') {
		if (! $run_linda) {
		    push @warnings,
		        "$whichlin option given but not running linda!";
		}
		while ($_=shift) {
		    if (/^--(lintian|linda)-opts$/) {
			unshift @ARGV, $_;
			next LIN_OPTS;
		    }
		    push @linda_opts, $_;
		}
	    }
	}
    }

    if ($< != 0) {
	$root_command ||= 'fakeroot';
	# Only fakeroot is a default, so that's the only one we'll
	# check for
	if ($root_command eq 'fakeroot') {
	    system('fakeroot true 2>/dev/null');
	    if ($? >> 8 != 0) {
		fatal "problem running fakeroot: either install the fakeroot package,\nuse a -r option to select another root command program to use or\nrun me as root!";
	    }
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

    # We need to do the arch, sversion, pv, pva stuff to figure out
    # what the changes file will be called,
    my ($sversion, $uversion, $dsc, $changes, $build);
    my $arch;
    if ($sourceonly) {
	$arch = 'source';
    } else {
	$arch=`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`;
	chomp $arch;
	fatal "couldn't determine host architecture!?" if ! $arch;
    }

    ($sversion=$version) =~ s/^\d+://;
    ($uversion=$sversion) =~ s/-[a-z0-9+\.]+$//i;
    $dsc="${pkg}_${sversion}.dsc";
    my $origtgz="${pkg}_${uversion}.orig.tar.gz";
    if ($tgz_check and $uversion ne $sversion and ! -f "../$origtgz") {
	warn "This package has a Debian revision number but there does not seem to be\nan appropriate .orig.tar.gz in the parent directory; continue anyway? (y/n) ";
	my $ans = <STDIN>;
	exit 1 unless $ans =~ /^y/i;
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

    run_hook('dpkg-buildpackage', 1);

    if ($dpkg_cross) {
	unshift @dpkg_opts, ($checkbuilddep ? "-D" : "-d");
	unshift @dpkg_opts, "-r$root_command" if $root_command;
	system_withecho('dpkg-buildpackage', @dpkg_opts);

	chdir '..' or fatal "can't chdir: $!";
	# We're using dpkg-cross, we could now have foo_1.2_i386+sparc.changes
	# so can't just set $changes = "${pkg}_${sversion}_${arch}.changes"
	my @changes = glob("${pkg}_${sversion}_*.changes");
	if (@changes == 0) {
	    fatal "couldn't find a .changes file!";
	} elsif (@changes == 1) {
	    $changes = $changes[0];
	} else {
	    # put newest first
	    @changes = sort { -M $a <=> -M $b } @changes;
	    $changes = $changes[0];
	}
    } else {
	# Not using dpkg-cross, so we emulate dpkg-buildpackage ourselves
	# We emulate the version found in dpkg-buildpackage-snapshot in
	# the source package

	# First dpkg-buildpackage action: run dpkg-checkbuilddeps
	if ($checkbuilddep) {
	    if ($binarytarget eq 'binary-arch') {
		system('dpkg-checkbuilddeps -B');
	    } else {
		system('dpkg-checkbuilddeps');
	    }
	    if ($?>>8) {
		# Horrible non-Perlish formatting here, but emacs formatting
		# dies miserably if this paragraph is done as a here-document.
		# And even the documented hack doesn't work here :(
		fatal "You do not appear to have all build dependencies properly met, aborting.\n" .
		    "(Use -d flag to override.)\n" .
		    "If you have the pbuilder package installed you can run\n" .
		    "/usr/lib/pbuilder/pbuilder-satisfydepends as root to install the\n" .
		    "required packages, or you can do it manually using dpkg or apt using\n" .
		    "the error messages just above this message.\n";
	    }
	}

	run_hook('clean', ! $noclean);

	# Next dpkg-buildpackage action: clean
	unless ($noclean) {
	    if ($< == 0) {
		system_withecho('debian/rules', 'clean');
	    } else {
		system_withecho($root_command, 'debian/rules', 'clean');
	    }
	}

	run_hook('dpkg-source', ! $binaryonly);

	# Next dpkg-buildpackage action: dpkg-source
	if (! $binaryonly) {
	    my $dirn = basename(cwd());
	    my @cmd = (qw(dpkg-source));
	    push @cmd, @passopts;
	    push @cmd, $diffignore if $diffignore;
	    push @cmd, @tarignore;
	    push @cmd, "-b", $dirn;
	    chdir '..' or fatal "can't chdir ..: $!";
	    system_withecho(@cmd);	
	    chdir $dirn or fatal "can't chdir $dirn: $!";
	}

	run_hook('build', ! $sourceonly);

	# Next dpkg-buildpackage action: build and binary targets
	if (! $sourceonly) {
	    system_withecho('debian/rules', 'build');
	
	    run_hook('binary', 1);

	    if ($< == 0) {
		system_withecho('debian/rules', $binarytarget);
	    } else {
		system_withecho($root_command, 'debian/rules', $binarytarget);
	    }
	} elsif ($hook{'binary'}) {
	    push @warnings, "$progname: not running binary hook '$hook{'binary'}' as -S option used\n";
	}

	# We defer the signing the .dsc file until after dpkg-genchanges has
	# been run

	run_hook('dpkg-genchanges', 1);

	# Because of our messing around with STDOUT and wanting to pass
	# arguments safely to dpkg-genchanges means that we're gonna have to
	# do it manually :(
	my @cmd = ('dpkg-genchanges');
	foreach ($binaryonly, $sourceonly, $sourcestyle) {
	    push @cmd, $_ if $_;
	}
	push @cmd, "-m$maint" if $maint;
	push @cmd, "-e$changedby" if $changedby;
	push @cmd, "-v$since" if $since;
	push @cmd, "-C$desc" if $desc;
	print STDERR " ", join(" ", @cmd), "\n";
	
	open GENCHANGES, "-|", @cmd or fatal "can't exec dpkg-genchanges: $!";
	my @changefilecontents;
	@changefilecontents = <GENCHANGES>;
	close GENCHANGES
	    or warn "$progname: dpkg-genchanges failed!\n", exit ($?>>8);
	open CHANGES, "> ../$changes"
	    or fatal "can't open ../$changes for writing: $!";
	print CHANGES @changefilecontents;
	close CHANGES
	    or fatal "problem writing to ../$changes: $!";

	run_hook('final-clean', $cleansource);

	# Final dpkg-buildpackage action: clean target again
	if ($cleansource) {
	    if ($< == 0) {
		system_withecho('debian/rules', 'clean');
	    } else {
		system_withecho($root_command, 'debian/rules', 'clean');
	    }
	}


	# identify the files listed in $changes; this will be used for the
	# emulation of the dpkg-buildpackage fileomitted() function

	my @files;
	my $infiles=0;
	foreach (@changefilecontents) {
	    /^Files:/ and $infiles=1, next;
	    next unless $infiles;
	    last if /^[^ ]/; # no need to go further
	    # so we're looking at a filename with lots of info before it
	    / (\S+)$/ and push @files, $1;
	}

	my $srcmsg;

	if (fileomitted @files, '\.deb') {
	    # source only upload
	    if (fileomitted @files, '\.diff\.gz') {
		$srcmsg='source only upload: Debian-native package';
	    } elsif (fileomitted @files, '\.orig\.tar\.gz') {
		$srcmsg='source only, diff-only upload (original source NOT included)';
	    } else {
		$srcmsg='source only upload (original source is included)';
	    }
	} else {
	    if (fileomitted @files, '\.dsc') {
		$srcmsg='binary only upload (no source included)'
	    } elsif (fileomitted @files, '\.diff\.gz') {
		$srcmsg='full upload; Debian-native package (full source is included)';
	    } elsif (fileomitted @files, '\.orig\.tar\.gz') {
		$srcmsg='binary and diff upload (original source NOT included)';
	    } else {
		$srcmsg='full upload (original source is included)';
	    }
	}

	print "dpkg-buildpackage (debuild emulation): $srcmsg\n";

	chdir '..' or fatal "can't chdir: $!";
    } # end of debuild dpkg-buildpackage emulation

    run_hook('lintian', (($run_lintian && $lintian_exists) ||
			 ($run_linda && $linda_exists)) );
    
    if ($run_lintian && $lintian_exists) {
	$<=$>=$uid;  # Give up on root privileges if we can
	$(=$)=$gid;
	print "Now running lintian...\n";
	# The remaining items in @ARGV, if any, are lintian options
	system('lintian', @lintian_extra_opts, @lintian_opts, $changes);
	print "Finished running lintian.\n";
    }
    if ($run_linda && $linda_exists) {
	$<=$>=$uid;  # Give up on root privileges if we can
	$(=$)=$gid;
	print "Now running linda...\n";
	# The remaining items in @ARGV, if any, are linda options
	system('linda', @linda_extra_opts, @linda_opts, $changes);
	print "Finished running linda.\n";
    }

    # They've insisted.  Who knows why?!
    if (($signchanges or $signsource) and $usepause) {
	print "Press the return key to start signing process\n";
	<STDIN>;
    }

    run_hook('signing', ($signchanges || (! $sourceonly and $signsource)) );

    if ($signchanges) {
	print "Now signing changes and any dsc files...\n";
	system('debsign', @debsign_opts, $changes) == 0
	    or fatal "running debsign failed";
    }
    elsif (! $sourceonly and $signsource) {
	print "Now signing dsc file...\n";
	system('debsign', @debsign_opts, $dsc) == 0
	    or fatal "running debsign failed";
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
    open STDOUT, ">&OLDOUT";
    open STDERR, ">&OLDERR";
    exit 0;
}
else {
    # Running debian/rules.  Do dpkg-checkbuilddeps first
    if ($checkbuilddep) {
	if ($ARGV[0] eq 'binary-arch') {
	    system('dpkg-checkbuilddeps -B');
	} else {
	    system('dpkg-checkbuilddeps');
	}
	if ($?>>8) {
	    fatal <<"EOT";
You do not appear to have all build dependencies properly met.
If you have the pbuilder package installed, you can run
/usr/lib/pbuilder/pbuilder-satisfydepends as root to install the
required packages, or you can do it manually using dpkg or apt using
the error messages just above this message.
EOT
	}
    }

    # Don't try to use the root command if we are already running as root
    if ( $< == 0 ) {
	system ('debian/rules', @ARGV) == 0
	    or fatal "couldn't exec debian/rules: $!";
    }
    else {
	# So we'll use the selected or default root command
	system ($root_command, 'debian/rules', @ARGV) == 0
	    or fatal "couldn't exec $root_command debian/rules: $!";
    }

    # Any warnings?
    if (@warnings) {
	my $warns = @warnings > 1 ? "s" : "";
	warn "Warning$warns generated by debuild:\n" .
	    join("\n", @warnings) . "\n";
    }
    exit 0;
}

###### Subroutines

sub system_withecho(@) {
    print STDERR " ", join(" ", @_), "\n";
    system(@_);
    if ($?>>8) {
	fatal "@_ failed";
    }
}

sub fileomitted (\@$) {
    my ($files, $pat) = @_;
    return (scalar(grep { /$pat$/ } @$files) == 0);
}

sub run_hook ($$) {
    my ($hook, $act) = @_;
    return unless $hook{$hook};

    print STDERR " Running $hook-hook\n";
    my $hookcmd = $hook{$hook};
    $act = $act ? 1 : 0;
    my %per=("%"=>"%", "p"=>$pkg, "v"=>$version, "a"=>$act);
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
	open STDOUT, ">&OLDOUT";
	open STDERR, ">&OLDERR";
    }
    die $msg;
}
