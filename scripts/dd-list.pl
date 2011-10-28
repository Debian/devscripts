#!/usr/bin/perl -w
#
# dd-list: Generate a list of maintainers of packages.
#
# Written by Joey Hess <joeyh@debian.org>
# Modifications by James McCoy <jamessan@debian.org>
# Based on a python implementation by Lars Wirzenius.
# Copyright 2005 Lars Wirzenius, Joey Hess
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

use strict;
use FileHandle;
use Getopt::Long qw(:config gnu_getopt);

my $version='###VERSION###';

sub sort_developers {
    return map { $_->[0] }
	   sort { $a->[1] cmp $b->[1] }
	   map { [$_, uc] } @_;
}

sub help {
	print <<"EOF"
Usage: dd-list [options] [package ...]

    -h, --help
        Print this help text.

    -i, --stdin
        Read package names from the standard input.

    -d, --dctrl
        Read package list in Debian control data from standard input.

    -s, --sources SOURCES_FILE
        Read package information from given SOURCES_FILE instead of all files
        matching /var/lib/apt/lists/*_source_Sources.  Can be specified
        multiple times.

    -u, --uploaders
        Also list Uploaders of packages, not only the listed Maintainers
        (this is the default behaviour, use --nouploaders to prevent this).

    -nou, --nouploaders
        Only list package Maintainers, do not list Uploaders.

    -b, --print-binary
        If binary package names are given as input, print these names
        in the output instead of corresponding source packages.

    -V, --version
        Print version (it\'s $version by the way).
EOF
}

my $use_stdin=0;
my $use_dctrl=0;
my $source_files=[];
my $show_uploaders=1;
my $print_binary=0;
GetOptions(
    "help" => sub { help(); exit },
    "stdin|i" => \$use_stdin,
    "dctrl|d" => \$use_dctrl,
    "sources|s:s@" => \$source_files,
    "uploaders|u!" => \$show_uploaders,
    "print-binary|b" => \$print_binary,
    "version" => sub { print "dd-list version $version\n" })
or do {
    help();
    exit(1);
};

my %dict;
my $errors=0;
my %package_name;

sub parsefh
{
    my ($fh, $fname, $check_package) = @_;
    local $/="\n\n";
    while (<$fh>) {
	my ($package, $maintainer, $uploaders, @uploaders);

	if (/^Package:\s+(.*)$/m) {
	    $package=$1;
	}
	if (/^Source:\s+(.*)$/m && ! $print_binary ) {
	    $package=$1;
	}
	if (/^Maintainer:\s+(.*)$/m) {
	    $maintainer=$1;
	}
	if (/^Uploaders:\s+(.*)$/m) {
	    $uploaders=$1;
	    @uploaders = split /(?<=>)\s*,\s*/, $uploaders;
	}

	if (defined $maintainer && defined $package) {
	    if ($check_package && !exists $package_name{$package}) {
		next;
	    }
	    push @{$dict{$maintainer}}, $package;
	    if ($show_uploaders && defined $uploaders) {
		foreach my $uploader (@uploaders) {
		    push @{$dict{$uploader}}, "$package (U)";
		}
	    }
	}
	else {
	    warn "E: parse error in stanza $. of $fname\n";
	    $errors=1;
	}
    }
}

if ($use_dctrl) {
    parsefh(\*STDIN, 'STDIN');
}
else {
    if ($use_stdin) {
	while (<STDIN>) {
	    chomp;
	    s/^\s+//;
	    s/\s+$//;
	    map { $package_name{lc($_)} = 1 } split ' ', $_;
	}
    }
    else {
	map { $package_name{lc($_)} = 1 } @ARGV;
    }

    unless (@{$source_files}) {
	$source_files = [glob('/var/lib/apt/lists/*_source_Sources')];
    }

    foreach my $source (@{$source_files}) {
	my $fh = FileHandle->new("<$source");
	unless (defined $fh) {
	    warn "E: Couldn't open $fh\n";
	    $errors = 1;
	    next;
	}
	parsefh($fh, $source, 1);
	$fh->close;
    }
}

foreach my $developer (sort_developers(keys %dict)) {
    print "$developer\n";
    my %seen;
    foreach my $package (sort @{$dict{$developer}}) {
	$package_name{$package}--;
	next if $seen{$package};
	$seen{$package}=1;
	print "   $package\n";
    }
    print "\n";
}

foreach my $package (grep { $package_name{$_} > 0 } keys %package_name) {
    warn "E: Unknown package: $package\n";
    $errors = 1;
}

exit($errors);
