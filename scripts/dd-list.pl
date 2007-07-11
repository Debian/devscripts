#!/usr/bin/perl -w
#
# dd-list: Generate a list of maintainers of packages.
#
# Written by Joey Hess <joeyh@debian.org>
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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use Getopt::Long;

my $version='###VERSION###';

sub get_developers_given_package {
	my ($package_name,$print_binary) = @_;
	
	my $developer;
	my $print_name;
	my $uploaders;
	my @uploaders;
	open (F, "apt-cache showsrc '$package_name' |");
	while (<F>) {
		chomp;
		if (/^Maintainer: (.*)/) {
			$developer=$1;
		}
		elsif (/^Uploaders: (.*)/) {
			$uploaders=$1;
			@uploaders = split /\s*,\s*/, $uploaders;
			
		}
		elsif (/^Package: (.*)/) {
			$print_name = $print_binary ? $package_name : $1 ;
		}
	}
	close F;
	return ($developer, \@uploaders, $print_name);
}

sub parse_developer {
	my $developer=shift;

	my ($name, $domain) = $developer=~/^(.*)\s+<.*@(.*)>\s*$/i;
	if (defined $domain && $domain !~ /^(lists(\.alioth)?\.debian\.org|teams\.debian\.net)$/) {
		return join " ", reverse split " ", $name;
	}
	elsif (defined $name) {
		return $name;
	}
	else {
		return $developer;
	}
}

sub sort_developers {
	sort { uc(parse_developer($a)) cmp uc(parse_developer($b)) } @_;
}

sub help {
	print <<"EOF"
Usage: dd-list [options] [package ...]

    -h, --help
        Print this help text.
        
    -i, --stdin
        Read package names from the standard input.

    -d, --dctrl
        Read Debian control data from standard input.

    -u, --uploaders
        Also list Uploaders of packages, not only the listed maintainers
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
my $show_uploaders=1;
my $print_binary=0;
if (! GetOptions(
	"help" => sub { help(); exit },
	"stdin|i" => \$use_stdin,
	"dctrl|d" => \$use_dctrl,
	"uploaders|u!" => \$show_uploaders,
	"print-binary|b" => \$print_binary,
	"version" => sub { print "dd-list version $version\n" })) {
	exit(1);
}

my %dict;
my $errors=0;

if ($use_dctrl) {
	local $/="\n\n";
	while (<>) {
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
			@uploaders = split /\s*,\s*/, $uploaders;
		}

		if (defined $maintainer && defined $package) {
			push @{$dict{$maintainer}}, $package;
			if ($show_uploaders && defined $uploaders) {
				foreach my $uploader (@uploaders) {
					push @{$dict{$uploader}}, "$package (U)";
				}
			}
		}
		else {
			print STDERR "E: parse error in stanza $.\n";
			$errors=1;
		}
	}
}
else {
	my @package_names;
	if ($use_stdin) {
		while (<>) {
			chomp;
			s/^\s+//;
			s/\s+$//;
			push @package_names, split ' ', $_;
		}
	}
	else {
		@package_names=@ARGV;
	}

	foreach my $package_name (@package_names) {
		my ($developer, $uploaders, $print_name)=get_developers_given_package($package_name,$print_binary);
		if (defined $developer) {
			push @{$dict{$developer}}, $print_name;
			if ($show_uploaders && @$uploaders) {
				foreach my $uploader (@$uploaders) {
					push @{$dict{$uploader}}, "$print_name (U)";
				}
			}
		}
		else {
			print STDERR "E: Unknown package: $package_name\n";
			$errors=1;
		}
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

exit($errors);
