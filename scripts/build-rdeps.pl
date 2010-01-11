#!/usr/bin/perl
#   Copyright (C) Patrick Schoenfeld
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

build-rdeps - find packages that depend on a specific package to build (reverse build depends)

=head1 SYNOPSIS

B<build-rdeps> I<package>

=head1 DESCRIPTION

B<build-rdeps> searches for all packages that build-depend on the specified package.

=head1 OPTIONS

=over 4

=item B<-u> B<--update>

Run apt-get update before searching for build-depends.

=item B<-s> B<--sudo>

Use sudo when running apt-get update. Has no effect if -u is omitted.

=item B<--distribution>

Select another distribution, which is searched for build-depends.

=item B<--only-main>

Ignore contrib and non-free

=item B<--exclude-component>

Ignore the given component (e.g. main, contrib, non-free).

=item B<--origin>

Restrict the search to only the specified origin (such as "Debian").

=item B<-m> B<--print-maintainer>

Print the value of the maintainer field for each package.

=item B<-d> B<--debug>

Run the debug mode

=item B<--help>

Show the usage information.

=item B<--version>

Show the version information.

=back

=head1 REQUIREMENTS

The tool requires apt Sources files to be around for the checked components.
In the default case this means that in /var/lib/apt/lists files need to be
around for main, contrib and non-free.

In practice this means one needs to add one deb-src line for each component,
e.g.

deb-src http://<mirror>/debian <dist> main contrib non-free

and run apt-get update afterwards or use the update option of this tool.

=cut

use warnings;
use strict;
use File::Basename;
use File::Find;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
my $progname = basename($0);
my $version = '1.0';
my $dctrl = "/usr/bin/grep-dctrl";
my $sources_path = "/var/lib/apt/lists/";
my $release_pattern = '(.*_dists_(sid|unstable))_Release$';
my %seen_origins;
my @source_files;
my $opt_debug;
my $opt_update;
my $opt_sudo;
my $opt_maintainer;
my $opt_mainonly;
my $opt_distribution;
my $opt_origin = 'Debian';
my @opt_exclude_components;

if (!(-x $dctrl)) {
	die "$progname: Fatal error. grep-dctrl is not available.\nPlease install the 'dctrl-tools' package.\n";
}

sub version {
	print <<"EOT";
This is $progname $version, from the Debian devscripts package, v. ###VERSION###
This code is copyright by Patrick Schoenfeld, all rights reserved.
It comes with ABSOLUTELY NO WARRANTY. You are free to redistribute this code
under the terms of the GNU General Public License, version 2 or later.
EOT
exit (0);
}

sub usage {
	print <<"EOT";
usage: $progname packagename
       $progname --help
       $progname --version

Searches for all packages that build-depend on the specified package.

Options:
   -u, --update                   Run apt-get update before searching for build-depends.
                                  (needs root privileges)
   -s, --sudo                     Use sudo when running apt-get update
                                  (has no effect when -u is ommitted)
   -d, --debug                    Enable the debug mode
   -m, --print-maintainer         Print the maintainer information (experimental)
   --distribution distribution    Select a distribution to search for build-depends
                                  (Default: unstable)
   --origin origin                Select an origin to search for build-depends
                                  (Default: Debian)
   --only-main                    Ignore contrib and non-free
   --exclude-component COMPONENT  Ignore the specified component (can be given multiple times)

EOT
version;
}

# Sub to test if a given section shall be included in the result
sub test_for_valid_component {
    if ($opt_mainonly and /(contrib|non-free)/) {
	return -1;
    }
    foreach my $component (@opt_exclude_components) {
	if ($_ =~ /$component/) {
	    return -1;
	}
    }

    print STDERR "DEBUG: Component ($_) may not be excluded.\n" if ($opt_debug);
    return 0;
}

# Scan Release files and add appropriate Sources files
sub readrelease {
    my ($file, $base) = @_;
    open(RELEASE, '<', "$sources_path/$file");
    while (<RELEASE>) {
	if (/^Origin:\s*(.+)\s*$/) {
	    my $origin = $1;
	    # skip undesired (non-specified or already seen) origins
	    if (($opt_origin && $origin !~ /^\s*\Q$opt_origin\E\s*$/)
	        || $seen_origins{$origin}) {
		last;
	    }
	    $seen_origins{$origin} = 1;
	}
	elsif (/^(?:MD5|SHA)\w+:/) {
	    # from a list of checksums, grab names of Sources files
	    while (<RELEASE>) {
		last unless /^ /;
		if (/([^ ]+\/Sources)$/) {
		    addsources($base, $1);
		}
	    }
	    last;
	}
    }
    close(RELEASE);
}

# Add a *_Sources file if test_for_valid_component likes it
sub addsources {
    my ($base, $filename) = @_;
    # main/source/Sources
    $filename =~ s/\//_/g;
    # -> ftp.debian.org_..._main_source_Sources
    $filename = "${base}_${filename}";
    if (test_for_valid_component($filename) == 0) {
	push(@source_files, $filename);
	print STDERR "DEBUG: Added source file: $_\n" if ($opt_debug);
    }
}

sub findreversebuilddeps {
	my ($package, $source_file) = @_;
	my %packages;
	my $depending_package;
	my $count=0;
	my $maintainer_info='';

	open(PACKAGES, "$dctrl -F Build-Depends,Build-Depends-Indep $package -s Package,Build-Depends,Build-Depends-Indep,Maintainer $source_file|");

	while(<PACKAGES>) {
		chomp;
		print STDERR "$_\n" if ($opt_debug);
		if (/Package: (.*)$/) {
			$depending_package = $1;
			$packages{$depending_package}->{'Build-Depends'} = 0;
		}

		if (/Maintainer: (.*)$/) {
			if ($depending_package) {
				$packages{$depending_package}->{'Maintainer'} = $1;
			}
		}

		if (/Build-Depends: (.*)$/ or /Build-Depends-Indep: (.*)$/) {
			if ($depending_package) {
				print STDERR "$1\n" if ($opt_debug);
				if ($1 =~ /^(.*\s)?$package([\s,]|$)/) {
					$packages{$depending_package}->{'Build-Depends'} = 1;
				}
			}

		}
	}

	while($depending_package = each(%packages)) {
		if ($packages{$depending_package}->{'Build-Depends'} != 1) {
			print STDERR "Ignoring package $depending_package because its not really build depending on $package.\n" if ($opt_debug);
			next;
		}
		if ($opt_maintainer) {
			$maintainer_info = "($packages{$depending_package}->{'Maintainer'})";
		}

		$count+=1;
		print "$depending_package $maintainer_info \n";

	}

	if ($count == 0) {
		print "No reverse build-depends found for $package.\n\n"
	}
	else {
		print "\nFound a total of $count reverse build-depend(s) for $package.\n\n";
	}
}

if ($#ARGV < 0) { usage; exit(0); }


Getopt::Long::Configure('bundling');
GetOptions(
	"u|update" => \$opt_update,
	"s|sudo" => \$opt_sudo,
	"m|print-maintainer" => \$opt_maintainer,
	"distribution=s" => \$opt_distribution,
	"only-main" => \$opt_mainonly,
	"exclude-component=s" => \@opt_exclude_components,
	"origin=s" => \$opt_origin,
	"d|debug" => \$opt_debug,
	"h|help" => sub { usage; },
	"v|version" => sub { version; }
);

my $package = shift;

if (!$package) {
	die "$progname: missing argument. expecting packagename\n";
}

print STDERR "DEBUG: Package => $package\n" if ($opt_debug);

if ($opt_update) {
	print STDERR "DEBUG: Updating apt-cache before search\n" if ($opt_debug);
	my @cmd;
	if ($opt_sudo) {
		print STDERR "DEBUG: Using sudo to become root\n" if ($opt_debug);
		push(@cmd, 'sudo');
	}
	push(@cmd, 'apt-get', 'update');
	system @cmd;
}

if ($opt_distribution) {
	print STDERR "DEBUG: Setting distribution to $opt_distribution\n" if ($opt_debug);
	$release_pattern = '(.*_dists_' . $opt_distribution . ')_Release$';
}

# Find sources files
find(sub { readrelease($_, $1) if /$release_pattern/ }, $sources_path);

if (($#source_files+1) <= 0) {
	die "$progname: unable to find sources files.\nDid you forget to run apt-get update (or add --update to this command)?";
}

foreach my $source_file (@source_files) {
	if ($source_file =~ /main/) {
		print "Reverse Build-depends in main:\n";
		print "------------------------------\n\n";
		findreversebuilddeps($package, "$sources_path/$source_file");
	}

	if ($source_file =~ /contrib/) {
		print "Reverse Build-depends in contrib:\n";
		print "---------------------------------\n\n";
		findreversebuilddeps($package, "$sources_path/$source_file");
	}

	if ($source_file =~ /non-free/) {
		print "Reverse Build-depends in non-free:\n";
		print "----------------------------------\n\n";
		findreversebuilddeps($package, "$sources_path/$source_file");
	}
}

=head1 LICENSE

This code is copyright by Patrick Schoenfeld
<schoenfeld@debian.org>, all rights reserved.
This program comes with ABSOLUTELEY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.

=head1 AUTHOR

Patrick Schoenfeld <schoenfeld@debian.org>

=cut
