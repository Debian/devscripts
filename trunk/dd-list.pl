#!/usr/bin/perl
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

use warnings;
use strict;
use Getopt::Long;

my $version='###VERSION###';

sub get_developer_given_package {
	my $package_name=shift;
	
	my $developer;
	my $source_name;
	open (F, "apt-cache showsrc '$package_name' |");
	while (<F>) {
		chomp;
		if (/^Maintainer: (.*)/) {
			$developer=$1;
		}
		elsif (/^Package: (.*)/) {
			$source_name=$1;
		}
	}
	close F;
	return ($developer, $source_name);
}

sub parse_developer {
	my $developer=shift;

	my ($name, $domain)=$developer=~/^(.*)\s+<.*@(.*)>\s*$/i;
	if (defined $domain && $domain ne 'lists.debian.org') {
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
	sort { parse_developer($a) cmp parse_developer($b) } @_;
}

sub help {
	print <<"EOF"
Usage: dd-list [-hiV] [--help] [--stdin] [--version] [package ...]

    -h, --help
        Print this help text.
        
    -i, --stdin
        Read package names from the standard input.
       
    -V, --version
        Print version (it's $version by the way).
EOF
}

my $use_stdin=0;
if (! GetOptions(
	"help" => sub { help(); exit },
	"stdin|i" => \$use_stdin,
	"version" => sub { print "dd-list version $version\n" })) {
	exit(1);
}

my @package_names;
if ($use_stdin) {
	while (<>) {
		chomp;
		s/^\s+//;
		s/\s+$//;
		push @package_names, $_;
	}
}
else {
	@package_names=@ARGV;
}

my $errors=0;
my %dict;

foreach my $package_name (@package_names) {
	my ($developer, $source_name)=get_developer_given_package($package_name);
	if (defined $developer) {
		push @{$dict{$developer}}, $source_name;
	}
	else {
		print STDERR "E: Unknown package: $package_name\n";
		$errors=1;
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
