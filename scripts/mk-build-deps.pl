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

B<mk-build-deps> --help|--version

B<mk-build-deps> [options] <control file | package name> [...]

=head1 DESCRIPTION

Given a package name and/or control file, B<mk-build-deps>
will use B<equivs> to generate a binary package which may be installed to
satisfy the build-dependencies of the given package.

=head1 OPTIONS

=over 4

=item B<-i>, B<--install>

Install the generated packages and its build-dependencies.

=item B<-t>, B<--tool>

When installing the generated package use the specified tool.
(default: apt-get)

=item B<-r>, B<--remove>

Remove the package file after installing it. Ignored if used without
the install switch.

=item B<-h>, B<--help>

Show a summary of options.

=item B<-v>, B<--version>

Show version and copyright information.

=back

=head1 AUTHOR

B<mk-build-deps> is copyright by Vincent Fourmond and was modified for the
devscripts package by Adam D. Barratt <adam@adam-barratt.org.uk>.

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License, version 2 or later.

=cut

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use Pod::Usage;

my $progname = basename($0);
my $opt_install;
my $opt_remove=0;
my ($opt_help, $opt_version);
my $control;
my $install_tool;
my @packages;
my @deb_files;

my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
my %config_vars = (
		    'MKBUILDDEPS_TOOL' => 'apt-get',
		    'MKBUILDDEPS_REMOVE_AFTER_INSTALL' => 'no'
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
	or $config_vars{'MKBUILDDEPS_TOOL'}='/usr/bin/apt-get';
$config_vars{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'} =~ /^(yes|no)$/
	or $config_vars{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'}='no';

$install_tool = $config_vars{'MKBUILDDEPS_TOOL'};

if ($config_vars{'MKBUILDDEPS_REMOVE_AFTER_INSTALL'} =~ /yes/) {
	$opt_remove=1;
}


GetOptions("help|h" => \$opt_help,
           "version|v" => \$opt_version,
           "install|i" => \$opt_install,
           "remove|r" => \$opt_remove,
           "tool|t=s" => \$install_tool,
           )
    or pod2usage({ -exitval => 1, -verbose => 0 });

pod2usage({ -exitval => 0, -verbose => 1 }) if ($opt_help);
if ($opt_version) { version(); exit 0; }

if (!@ARGV) {
    if (-r 'debian/control') {
	push(@ARGV, 'debian/control');
    }
}

pod2usage({ -exitval => 1, -verbose => 0 }) unless @ARGV;

system("command -v equivs-build >/dev/null 2>&1");
if ($?) {
    die "$progname: You must have equivs installed to use this program.\n";
}

while ($control = shift) {
    my $name;
    my $build_deps = "";
    my $version;
    my $last_line_build_deps;

    if (-r $control and -f $control) {
	open CONTROL, $control;
    }
    else {
	open CONTROL, "apt-cache showsrc $control |";
    }

    while (<CONTROL>) {
	next if /^#|^\s*$/;
	if (/^(?:Package|Source):\s*(\S+)/ && !$name) {
	    $name = $1;
	}
	if (/^Version:\s*(\S+)/) {
	    $version = $1;
	}
	if (/^Build-Depends(?:-Indep)?:\s*(.*)/) {
	    $build_deps .= $build_deps ? ", $1" : $1;
	    $last_line_build_deps = 1;
	}
	elsif (/^(\S+):/) {
	    $last_line_build_deps = 0;
	}
	elsif(/^\s+(.*)/ && $last_line_build_deps) {
	    $build_deps .= $1;
	}
    }
    close CONTROL;

    # Now, running equivs-build:

    die "$progname: Unable to find package name in '$control'\n" unless $name;
    die "$progname: Unable to find build-deps for $name\n" unless $build_deps;

    open EQUIVS, "| equivs-build -"
	or die "$progname: Failed to execute equivs-build: $!\n";
    print EQUIVS "Section: devel\n" .
	"Priority: optional\n".
	"Standards-Version: 3.7.3\n\n".
	"Package: ".$name."-build-deps\n".
	"Depends: $build_deps\n";
    print EQUIVS "Version: $version\n" if $version;

    print EQUIVS "Description: build-dependencies for $name\n" .
	" Depencency package to build the '$name' package\n";

    close EQUIVS;

    push @packages, $name;

}

use Text::ParseWords;

if ($opt_install) {
    for my $package (@packages) {
	my $file = glob "${package}-build-deps_*.deb";
	push @deb_files, $file;
    }

    system 'dpkg', '--unpack', @deb_files;
    system shellwords($install_tool), '-f', 'install';

    if ($opt_remove) {
	foreach my $file (@deb_files) {
	    unlink $file;
	}
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

