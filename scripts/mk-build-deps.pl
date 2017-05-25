#!/usr/bin/perl

# mk-build-deps: make a dummy package to satisfy build-deps of a package
# Copyright 2008 by Vincent Fourmond
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

# Changes:
# * (Vincent Fourmond 4/4/2008): now take Build-Depends-Indep
#   into consideration

=head1 NAME

mk-build-deps - build a package satisfying a package's build-dependencies

=head1 SYNOPSIS

B<mk-build-deps> B<--help>|B<--version>

B<mk-build-deps> [I<options>] I<control file> | I<package name> ...

=head1 DESCRIPTION

Given a I<package name> and/or I<control file>, B<mk-build-deps>
will use B<equivs> to generate a binary package which may be installed to
satisfy all the build dependencies of the given package.

If B<--build-dep> and/or B<--build-indep> are given, then the resulting binary
package(s) will depend solely on the Build-Depends/Build-Depends-Indep
dependencies, respectively.

=head1 OPTIONS

=over 4

=item B<-i>, B<--install>

Install the generated packages and its build-dependencies.

=item B<-t>, B<--tool>

When installing the generated package use the specified tool.
(default: B<apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends>)

=item B<-r>, B<--remove>

Remove the package file after installing it. Ignored if used without
the B<--install> switch.

=item B<-a> I<foo>, B<--arch> I<foo>

Set the architecture of the produced binary package to I<foo>. If this option
is not given, fall back to the value given by B<--host-arch>. If neither this
option nor B<--host-arch> are given but the Build-Depends contain architecture
restrictions, use the value printed by `dpkg-architecture -qDEB_HOST_ARCH`.
Otherwise, use I<all>.

The package architecture must be equal to the host architecture except if the
package architecture is I<all>.

The package architecture cannot be I<all> if the build and host architecture
differ.

=item B<--host-arch> I<foo>

Set the host architecture the binary package is built for. This defaults to
the value printed by `dpkg-architecture -qDEB_HOST_ARCH`. Use this option to
create a binary package that is able to satisfy crossbuild dependencies.

If this option is used together with B<--arch>, then they must be equal except
if the value of B<--arch> is I<all>.

If B<--arch> is not given, then this option also sets the package architecture.

=item B<--build-arch> I<foo>

Set the build architecture the binary package is built for. This defaults to
the value printed by `dpkg-architecture -qDEB_BUILD_ARCH`. Use this option to
create a binary package that is able to satisfy crossbuild dependencies.

=item B<-B>, B<--build-dep>

Generate a package which only depends on the source package's Build-Depends
dependencies.

=item B<-A>, B<--build-indep>

Generate a package which only depends on the source package's
Build-Depends-Indep dependencies.

=item B<-h>, B<--help>

Show a summary of options.

=item B<-v>, B<--version>

Show version and copyright information.

=item B<-s>, B<--root-cmd>

Use the specified tool to gain root privileges before installing.
Ignored if used without the B<--install> switch.

=back

=head1 AUTHOR

B<mk-build-deps> is copyright by Vincent Fourmond and was modified for the
devscripts package by Adam D. Barratt <adam@adam-barratt.org.uk>.

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License, version 2 or later.

=cut

use 5.01;
use strict;
use warnings;
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use File::Basename;
use Pod::Usage;
use Dpkg::Control;
use Dpkg::Version;
use Dpkg::IPC;
use Dpkg::Deps;
use FileHandle;
use Text::ParseWords;

my $progname = basename($0);
my $opt_install;
my $opt_remove=0;
my ($opt_help, $opt_version, $opt_arch, $opt_dep, $opt_indep, $opt_hostarch, $opt_buildarch);
my $control;
my $install_tool;
my $root_cmd;
my @packages;

my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
my %config_vars = (
		    'MKBUILDDEPS_TOOL' => '/usr/bin/apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends',
		    'MKBUILDDEPS_REMOVE_AFTER_INSTALL' => 'no',
		    'MKBUILDDEPS_ROOTCMD' => '',
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
$config_vars{'MKBUILDDEPS_TOOL'} =~ /./
	or $config_vars{'MKBUILDDEPS_TOOL'}=$config_default{'MKBUILDDEPS_TOOL'};
$config_vars{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'} =~ /^(yes|no)$/
	or $config_vars{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'}=$config_default{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'};
$config_vars{'MKBUILDDEPS_ROOTCMD'} =~ /./
	or $config_vars{'MKBUILDDEPS_ROOTCMD'}=$config_default{'MKBUILDDEPS_ROOTCMD'};

$install_tool = $config_vars{'MKBUILDDEPS_TOOL'};

if ($config_vars{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'} =~ /yes/) {
	$opt_remove=1;
}

sub usage {
    my ($exitval) = @_;

    my $verbose = $exitval ? 0 : 1;
    pod2usage({ -exitval => 'NOEXIT', -verbose => $verbose });

    if ($verbose) {
	my $modified_conf_msg;
	foreach my $var (sort keys %config_vars) {
	    if ($config_vars{$var} ne $config_default{$var}) {
		$modified_conf_msg .= "  $var=$config_vars{$var}\n";
	    }
	}
	$modified_conf_msg ||= "  (none)\n";
	chomp $modified_conf_msg;
	print <<EOF;
Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
    }

    exit $exitval;
}

GetOptions("help|h" => \$opt_help,
           "version|v" => \$opt_version,
           "install|i" => \$opt_install,
           "remove|r" => \$opt_remove,
           "tool|t=s" => \$install_tool,
           "arch|a=s" => \$opt_arch,
           "host-arch=s" => \$opt_hostarch,
           "build-arch=s" => \$opt_buildarch,
           "build-dep|B" => \$opt_dep,
           "build-indep|A" => \$opt_indep,
           "root-cmd|s=s" => \$root_cmd,
           )
    or usage(1);

usage(0) if ($opt_help);

if ($opt_version) { version(); exit 0; }

if (!@ARGV) {
    if (-r 'debian/control') {
	push(@ARGV, 'debian/control');
    }
}

usage(1) unless @ARGV;

system("command -v equivs-build >/dev/null 2>&1");
if ($?) {
    die "$progname: You must have equivs installed to use this program.\n";
}

while ($control = shift) {
    my ($name, $fh, $descr, $pid);
    if (-r $control and -f $control) {
	open $fh, $control;
	unless (defined $fh) {
	    warn "Unable to open $control: $!\n";
	    next;
	}
	$name = 'Source';
	$descr = "control file `$control'";
    }
    else {
	$fh = FileHandle->new();
	$pid = spawn(exec => ['apt-cache', 'showsrc', $control],
		     from_file => '/dev/null',
		     to_pipe => $fh);
	unless (defined $pid) {
	    warn "Unable to run apt-cache: $!\n";
	    next;
	}
	$name = 'Package';
	$descr = "`apt-cache showsrc $control'";
    }

    my (@pkgInfo, @versions);
    until (eof $fh) {
	my $ctrl = Dpkg::Control->new(allow_pgp => 1, type => CTRL_UNKNOWN);
	# parse() dies if the file isn't syntactically valid and returns undef
	# if there simply weren't any fields parsed
	unless ($ctrl->parse($fh, $descr)) {
	    warn "$progname: Unable to find package name in $descr\n";
	    next;
	}
	unless (exists $ctrl->{$name}) {
	    next;
	}
	my $args = '';
	my $arch = 'all';
	my ($build_deps, $build_dep, $build_indep);
	my ($build_conflicts, $conflict_arch, $conflict_indep);

	if (exists $ctrl->{'Build-Depends'}) {
	    $build_dep = $ctrl->{'Build-Depends'};
	    $build_dep =~ s/\n/ /g;
	    $build_deps = $build_dep;
	}
	if (exists $ctrl->{'Build-Depends-Indep'}) {
	    $build_indep = $ctrl->{'Build-Depends-Indep'};
	    $build_indep =~ s/\n/ /g;
	    $build_deps .= ', ' if $build_deps;
	    $build_deps .= $build_indep;
	}
	if (exists $ctrl->{'Build-Conflicts'}) {
	    $conflict_arch = $ctrl->{'Build-Conflicts'};
	    $conflict_arch =~ s/\n/ /g;
	    $build_conflicts = $conflict_arch;
	}
	if (exists $ctrl->{'Build-Conflicts-Indep'}) {
	    $conflict_indep = $ctrl->{'Build-Conflicts-Indep'};
	    $conflict_indep =~ s/\n/ /g;
	    $build_conflicts .= ', ' if $build_conflicts;
	    $build_conflicts .= $conflict_indep;
	}

	die "$progname: Unable to find build-deps for $ctrl->{$name}\n" unless $build_deps;

	if (exists $ctrl->{Version}) {
	    push(@versions, $ctrl->{Version});
	}
	elsif ($name eq 'Source') {
	    (my $changelog = $control) =~ s@control$@changelog@;
	    if (-f $changelog) {
		require Dpkg::Changelog::Parse;
		my $log = Dpkg::Changelog::Parse::changelog_parse(file => $changelog);
		if ($ctrl->{$name} eq $log->{$name}) {
		    $ctrl->{Version} = $log->{Version};
		    push(@versions, $log->{Version});
		}
	    }
	}

	# Only build a package with both B-D and B-D-I in Depends if the
	# B-D/B-D-I specific packages weren't requested
	if (!($opt_dep || $opt_indep)) {
	    push(@pkgInfo,
		 { depends => $build_deps,
		   conflicts => $build_conflicts,
		   name => $ctrl->{$name},
		   type => 'build-deps',
		   version => $ctrl->{Version} });
	    next;
	}
	if ($opt_dep) {
	    push(@pkgInfo,
		 { depends => $build_dep,
		   conflicts => $conflict_arch,
		   name => $ctrl->{$name},
		   type => 'build-deps-depends',
		   version => $ctrl->{Version} });
	}
	if ($opt_indep) {
	    push(@pkgInfo,
		 { depends => $build_indep,
		   conflicts => $conflict_indep,
		   name => $ctrl->{$name},
		   type => 'build-deps-indep',
		   version => $ctrl->{Version} });
	}
    }
    wait_child($pid, nocheck => 1) if defined $pid;
    # Only use the newest version.  We'll only have this if processing showsrc
    # output or a dsc file.
    if (@versions) {
	@versions = map { $_->[0] }
		    sort { $b->[1] <=> $a->[1] }
		    map { [$_, Dpkg::Version->new($_)] } @versions;
	push(@packages, map { build_equiv($_) }
			grep { $versions[0] eq $_->{version} } @pkgInfo);
    }
    elsif (@pkgInfo) {
	push(@packages, build_equiv($pkgInfo[0]));
    }
    else {
	die "$progname: Unable to find package name in $descr\n";
    }
}

if ($opt_install) {
    my @root;
    if ($root_cmd) {
	push(@root, shellwords($root_cmd));
    }

    my (@pkg_names, @deb_files, %uniq);
    for my $package (@packages) {
	if ($uniq{$package->{deb_file}}++ == 0) {
	    push @pkg_names, $package->{package};
	    push @deb_files, $package->{deb_file};
	}
    }

    system @root, 'dpkg', '--unpack', @deb_files;
    die("$progname: dpkg --unpack failed\n") if ( ($?>>8) != 0 );
    system @root, shellwords($install_tool), '-f', 'install';
    my $err = $? >> 8;
    if (!$err) {
	# $install_tool succeeded. Did the packages get installed? It's
	# possible that they didn't because $install_tool may have realized
	# that installation was impossible, and it could have given up,
	# successfully.
	for (my $i = 0; $i < @pkg_names; $i++) {
	    my $pkg = $pkg_names[$i];
	    my $status;
	    spawn(exec => ['dpkg-query', '-W', '-f', '${db:Status-Status}', $pkg],
	          to_string => \$status,
	          error_to_file => '/dev/null',
	          nocheck => 1,
	          wait_child => 1);
	    if ($status ne 'installed' || ($? >> 8)) {
		# Restore system to previous state, since $install_tool wasn't
		# able to resolve a proper way to get the build-dep packages
		# installed
		warn "$progname: Unable to install $pkg";
		$err = 1;
	    }
	    elsif ($opt_remove) {
		unlink $deb_files[$i];
	    }
	}
	if ($err) {
	    die "$progname: Unable to install all build-dep packages\n";
	}
    }
    else {
	# Restore system to previous state, since $install_tool wasn't able to
	# resolve a proper way to get the build-dep packages installed
	system @root, 'dpkg', '--remove', @pkg_names;
	die("$progname: Unable to install all build-dep packages\n");
    }
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
Copyright (C) 2008 Vincent Fourmond

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2, or (at your option) any
later version.
EOF
}

sub build_equiv
{
    my ($opts) = @_;
    my $args = '';

    my $packagearch = 'all';

    if (defined $opt_arch) {
	$packagearch = $opt_arch;
    } elsif (defined $opt_hostarch) {
	$packagearch = $opt_hostarch;
    } elsif ($opts->{depends} =~ m/\[|\]/) {
	chomp($packagearch = `dpkg-architecture -qDEB_HOST_ARCH`);
    }
    if ($packagearch ne "all") {
	$args .= "--arch=$packagearch ";
    }

    chomp(my $buildarch = `dpkg-architecture -qDEB_BUILD_ARCH`);
    if (defined $opt_buildarch) {
	$buildarch = $opt_buildarch;
    }

    chomp(my $hostarch = `dpkg-architecture -qDEB_HOST_ARCH`);
    if (defined $opt_hostarch) {
	$hostarch = $opt_hostarch;
    }

    if ($packagearch eq "all") {
	if ($buildarch ne $hostarch) {
	    die "build architecture \"$buildarch\" is unequal host architecture \"$hostarch\" in which case the package architecture must not be \"all\" (but \"$hostarch\" instead)\n";
	}
    } elsif ($packagearch ne $hostarch) {
	die "The package architecture must be equal to the host architecture except if the package architecture is \"all\"\n";
    }

    my $build_profiles = [ split /\s+/, ($ENV{'DEB_BUILD_PROFILES'} // "") ];

    my $positive = deps_parse($opts->{depends} // "",
	reduce_arch => 1,
	host_arch => $hostarch,
	build_arch => $buildarch,
	build_dep => 1,
	reduce_profiles => 1,
	build_profiles => $build_profiles);
    my $negative = deps_parse($opts->{conflicts} // "",
	reduce_arch => 1,
	host_arch => $hostarch,
	build_arch => $buildarch,
	build_dep => 1,
	union => 1,
	reduce_profiles => 1,
	build_profiles => $build_profiles);

    # either remove :native for native builds or replace it by the build
    # architecture
    my $handle_native_archqual = sub {
        my ($dep) = @_;
        if ($dep->{archqual} && $dep->{archqual} eq "native") {
            if ($hostarch eq $buildarch) {
                $dep->{archqual} = undef;
            } else {
                $dep->{archqual} = $buildarch;
            }
        }
        return 1;
    };
    deps_iterate($positive, $handle_native_archqual);
    deps_iterate($negative, $handle_native_archqual);

    my $pkgname;
    my $buildess = "build-essential:$buildarch";
    if ($buildarch eq $hostarch) {
	$pkgname = "$opts->{name}-$opts->{type}";
    } else {
	$pkgname = "$opts->{name}-cross-$opts->{type}";
	$buildess .= ", crossbuild-essential-$hostarch:$buildarch";
    }

    my $readme = '/usr/share/devscripts/README.mk-build-deps';
    open EQUIVS, "| equivs-build $args-"
	or die "$progname: Failed to execute equivs-build: $!\n";
    print EQUIVS "Section: devel\n" .
    "Priority: optional\n".
    "Standards-Version: 3.7.3\n\n".
    "Package: $pkgname\n".
    "Architecture: $packagearch\n".
    "Depends: $buildess, $positive\n";

    print EQUIVS "Conflicts: $negative\n" if $negative;

    # Allow the file not to exist to ease testing
    print EQUIVS "Readme: $readme\n" if -r $readme;

    my $version = $opts->{version} || '1.0';
    print EQUIVS "Version: $version\n";

    print EQUIVS "Description: build-dependencies for $opts->{name}\n" .
    " Dependency package to build the '$opts->{name}' package\n";

    close EQUIVS;

    my $v = Dpkg::Version->new($version);
    # The version in the .deb filename will not contain the epoch
    $version = $v->as_string(omit_epoch => 1);
    my $deb_file = "${pkgname}_${version}_${packagearch}.deb";
    return {
	package => $pkgname,
	deb_file => $deb_file
    };
}
