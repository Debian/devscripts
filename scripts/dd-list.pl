#!/usr/bin/perl
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
# along with this program. If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;
use FileHandle;
use Getopt::Long qw(:config gnu_getopt);
use Dpkg::Version;
use Dpkg::IPC;

my $uncompress;

BEGIN {
    $uncompress = eval {
	require IO::Uncompress::AnyUncompress;
	IO::Uncompress::AnyUncompress->import('$AnyUncompressError');
	1;
    };
}

my $version='###VERSION###';

sub normalize_package {
    my $name = shift;
    # Remove any arch-qualifier
    $name =~ s/:.*//;
    return lc($name);
}

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

    -z, --uncompress
        Try to uncompress the --dctrl input before parsing.  Supported
        compression formats are gz, bzip2 and xz.

    -s, --sources SOURCES_FILE
        Read package information from given SOURCES_FILE instead of all files
        matching /var/lib/apt/lists/*_source_Sources.  Can be specified
        multiple times.  The files can be gz, bzip2 or xz compressed.

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
my $opt_uncompress=0;
my $print_binary=0;
GetOptions(
    "help|h" => sub { help(); exit },
    "stdin|i" => \$use_stdin,
    "dctrl|d" => \$use_dctrl,
    "sources|s:s@" => \$source_files,
    "uploaders|u!" => \$show_uploaders,
    'z|uncompress' => \$opt_uncompress,
    "print-binary|b" => \$print_binary,
    "version" => sub { print "dd-list version $version\n" })
or do {
    help();
    exit(1);
};

if ($opt_uncompress && !$uncompress) {
    warn "You must have the libio-compress-perl package installed to use the -z option.\n";
    exit 1;
}

my %dict;
my $errors=0;
my %package_name;

sub parsefh
{
    my ($fh, $fname, $check_package) = @_;
    local $/="\n\n";
    my $package_names;
    if ($check_package) {
	$package_names = sprintf '(?:^| )(%s)(?:,|$)',
				 join '|',
				 map { "\Q$_\E" }
				 keys %package_name;
    }
    my %sources;
    while (<$fh>) {
	my ($package, $source, $binaries, $maintainer, @uploaders);

	# These source packages are only kept around because of stale binaries
	# on old archs or due to Built-Using relationships.
	if (/^Extra-Source-Only:\s+yes/m) {
	    next;
	}

	# Binary is shown in _source_Sources and contains all binaries produced by
	# that source package
	if (/^Binary:\s+(.*(?:\n .*)*)$/m) {
	    $binaries = $1;
	    $binaries =~ s/\n//;
	}
	# Package is shown both in _source_Sources and _binary-*.  It is the
	# name of the package, source or binary respectively, being described
	# in that control stanza
	if (/^Package:\s+(.*)$/m) {
	    $package=$1;
	}
	# Source is shown in _binary-* and specifies the source package which
	# produced the binary being described
	if (/^Source:\s+(.*)$/m) {
	    $source=$1;
	}
	if (/^Maintainer:\s+(.*)$/m) {
	    $maintainer=$1;
	}
	if (/^Uploaders:\s+(.*(?:\n .*)*)$/m) {
	    my $matches=$1;
	    $matches =~ s/\n//g;
	    @uploaders = split /(?<=>)\s*,\s*/, $matches;
	}
	my $version = '0~0~0';
	if (/^Version:\s+(.*)$/m) {
	    $version = $1;
	}

	if (defined $maintainer
	    && (defined $package || defined $source || defined $binaries)) {
	    $source ||= $package;
	    $binaries ||= $package;
	    my @names;
	    if ($check_package) {
		my @pkgs;
		if (@pkgs = ($binaries =~ m/$package_names/g)) {
		    $sources{$source}{$version}{binaries} = [@pkgs];
		}
		elsif ($source !~ m/$package_names/) {
		    next;
		}
	    }
	    else {
		$sources{$source}{$version}{binaries} = [$binaries];
	    }
	    $sources{$source}{$version}{maintainer} = $maintainer;
	    $sources{$source}{$version}{uploaders} = [@uploaders];
	}
	else {
	    warn "E: parse error in stanza $. of $fname\n";
	    $errors=1;
	}
    }

    for my $source (keys %sources) {
	my @versions = sort map { Dpkg::Version->new($_) } keys %{$sources{$source}};
	my $version = $versions[-1];
	my $srcinfo = $sources{$source}{$version};
	my @names;
	if ($check_package) {
	    $package_name{$source}--;
	    $package_name{$_}-- for @{$srcinfo->{binaries}};
	}
	@names = $print_binary ? @{$srcinfo->{binaries}} : $source;
	push @{$dict{$srcinfo->{maintainer}}}, @names;
	if ($show_uploaders && @{$srcinfo->{uploaders}}) {
	    foreach my $uploader (@{$srcinfo->{uploaders}}) {
		push @{$dict{$uploader}}, map "$_ (U)", @names;
	    }
	}
    }
}

if ($use_dctrl) {
    my $fh;
    if ($uncompress) {
	$fh = IO::Uncompress::AnyUncompress->new('-')
	    or die "E: Unable to decompress STDIN: $AnyUncompressError\n";
    }
    else {
	$fh = \*STDIN;
    }
    parsefh($fh, 'STDIN');
}
else {
    my @packages;
    if ($use_stdin) {
	while (my $line = <STDIN>) {
	    chomp $line;
	    $line =~ s/^\s+|\s+$//g;
	    push @packages, split(' ', $line);
	}
    }
    else {
	@packages = @ARGV;
    }
    for my $name (@packages) {
	$package_name{normalize_package($name)} = 1;
    }

    my $apt_version;
    spawn(exec => ['dpkg-query', '-W', '-f', '${source:Version}', 'apt'],
	  to_string => \$apt_version,
	  wait_child => 1,
	  nocheck => 1);

    my $useAptHelper = 0;
    if (defined $apt_version)
    {
	$useAptHelper = version_compare_relation($apt_version, REL_GE, '1.1.8');
    }

    unless (@{$source_files}) {
	if ($useAptHelper)
	{
	    my ($sources, $err);
	    spawn(exec => ['apt-get', 'indextargets', '--format', '$(FILENAME)',
			   'Created-By: Sources'],
		  to_string => \$sources,
		  error_to_string => \$err,
		  wait_child => 1,
		  nocheck => 1);
	    if ($? >> 8)
	    {
		die "Unable to get list of Sources files from apt: $err\n";
	    }

	    $source_files = [split(/\n/, $sources)];
	}
	else
	{
	    $source_files = [glob('/var/lib/apt/lists/*_source_Sources')];
	}
    }

    foreach my $source (@{$source_files}) {
	my $fh;
	if ($useAptHelper)
	{
	    my $good = open($fh, '-|', '/usr/lib/apt/apt-helper', 'cat-file', $source);
	    if (!$good)
	    {
		warn "E: Couldn't run apt-helper to get contents of '$source': $!\n";
		$errors = 1;
		next;
	    }
	}
	else
	{
	    if ($opt_uncompress || ($uncompress && $source =~ m/\.(?:gz|bz2|xz)$/)) {
		$fh = IO::Uncompress::AnyUncompress->new($source);
	    }
	    else {
		$fh = FileHandle->new("<$source");
	    }
	    unless (defined $fh) {
		warn "E: Couldn't open $source\n";
		$errors = 1;
		next;
	    }
	}
	parsefh($fh, $source, 1);
	close $fh;
    }
}

foreach my $developer (sort_developers(keys %dict)) {
    print "$developer\n";
    my %seen;
    foreach my $package (sort @{$dict{$developer}}) {
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
