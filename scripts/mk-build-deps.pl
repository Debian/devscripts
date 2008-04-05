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

B<mk-build-deps> <control file | package name> [...]

=head1 DESCRIPTION

Given a package name and/or control file, B<mk-build-deps>
will use B<equivs> to generate a binary package which may be installed to
satisfy the build-dependencies of the given package.

=head1 OPTIONS

=over 4

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

my $progname = basename($0);
my ($opt_help, $opt_version);
my $control;

GetOptions("help|h" => \$opt_help,
           "version|v" => \$opt_version,
           )
    or die "Usage: $progname <control file | package name> [...]\nRun $progname --help for more details\n";

if ($opt_help) { help(); exit 0; }
if ($opt_version) { version(); exit 0; }

die "Usage: $progname <control file | package name> [...]\nRun $progname --help for more details\n" unless @ARGV;

system("command -v equivs-build >/dev/null 2>&1");
if ($?) {
    die "$progname: You must have equivs installed to use this program.\n";
}

while ($control = shift) {
    my $name;
    my $build_deps = "";
    my $version;
    my $last_line_build_deps;

    if( -r $control) {
	open CONTROL, $control;
    }
    else {
	open CONTROL, "apt-cache showsrc $control |";
    }

    while (<CONTROL>) {
	if (/^Package:\s*(\S+)/ && !$name) {
	    $name = $1;
	}
	if (/^Version:\s*(\S+)/) {
	    $version = $1;
	}
	if (/^Build-Depends(?:-Indep)?:\s*(.*)/) {
	    $build_deps .= $1;
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
}

sub help {
   print <<"EOF";
Usage: $progname <control file> | <package name> [...]
Valid options are:
   --help, -h             Display this message
   --version, -v          Display version and copyright info
EOF
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

