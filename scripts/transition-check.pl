#!/usr/bin/perl -w

# transition-check: Check whether a given source package is involved
# in a current transition for which uploads have been blocked by the
# Debian release team
#
# Copyright 2008 Adam D. Barratt
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

transition-check - check a package list for involvement in transitions

=head1 SYNOPSIS

B<transition-check> B<--help|--version>

B<transition-check> [B<-f|--filename>=I<FILENAME>] [I<source package list>]

=head1 DESCRIPTION

B<transition-check> checks whether any of the listed source packages
are involved in a transition for which uploads to unstable are currently
blocked.

If neither a filename nor a list of packages is supplied, B<transition-check>
will use the source package name from I<debian/control>.

=head1 OPTIONS

=over 4

=item B<-f> B<--filename>=I<filename>

Read a source package name from I<filename>, which should be a Debian
package control file or .changes file, and add that package to the list
of packages to check.

=back

=head1 EXIT STATUS

The exit status indicates whether any of the packages examined were found to
be involved in a transition.

=over 4

=item 0

Either B<--help> or B<--version> was used, or none of the packages examined
was involved in a transition.

=item 1

At least one package examined is involved in a current transition.

=back

=head1 LICENSE

This code is copyright by Adam D. Barratt <adam@adam-barratt.org.uk>,
all rights reserved.

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License, version 2 or later.

=head1 AUTHOR

Adam D. Barratt <adam@adam-barratt.org.uk>

=cut

use warnings;
use strict;
use Getopt::Long;
use File::Basename;

my $progname = basename($0);

my ($opt_help, $opt_version, @opt_filename);

GetOptions("help|h" => \$opt_help,
           "version|v" => \$opt_version,
           "filename|f=s" => sub {push (@opt_filename, $_[1]);},
           )
    or die "Usage: $progname [options] source_package_list\nRun $progname --help for more details\n";

if ($opt_help) { help(); exit 0; }
if ($opt_version) { version(); exit 0; }

my ($lwp_broken, $yaml_broken);
my $ua;

sub have_lwp() {
    return ($lwp_broken ? 0 : 1) if defined $lwp_broken;
    eval {
        require LWP;
        require LWP::UserAgent;
    };

    if ($@) {
        if ($@ =~ m%^Can\'t locate LWP%) {
            $lwp_broken="the libwww-perl package is not installed";
        } else {
            $lwp_broken="couldn't load LWP::UserAgent: $@";
        }
    }
    else { $lwp_broken=''; }
    return $lwp_broken ? 0 : 1;
}

sub have_yaml() {
    return ($yaml_broken ? 0 : 1) if defined $yaml_broken;
    eval {
        require YAML::Syck;
    };

    if ($@) {
        if ($@ =~ m%^Can\'t locate YAML%) {
            $yaml_broken="the libyaml-syck-perl package is not installed";
        } else {
            $yaml_broken="couldn't load YAML::Syck: $@";
        }
    }
    else { $yaml_broken=''; }
    return $yaml_broken ? 0 : 1;
}

sub init_agent {
  $ua = new LWP::UserAgent;  # we create a global UserAgent object
  $ua->agent("LWP::UserAgent/Devscripts");
  $ua->env_proxy;
}

if (@opt_filename or ! @ARGV) {
    @opt_filename = ("debian/control") unless @opt_filename;

    foreach my $filename (@opt_filename) {
	my $message;

	if (! @ARGV) {
	    $message = "No package list supplied and unable";
	} else {
	    $message = "Unable";
	}

	$message .= " to open $filename";
	open FILE, $filename or die "$progname: $message: $!\n";
	while (<FILE>) {
	    if (/^(?:Source): (.*)/) {
		push (@ARGV, $1);
		last;
	    }
	}

	close FILE;
    }
}

die "$progname: Unable to retrieve transition information: $lwp_broken\n"
    unless have_lwp;

init_agent() unless $ua;
my $request = HTTP::Request->new('GET', 'http://ftp-master.debian.org/testing/hints/transitions.yaml');
my $response = $ua->request($request);
if (!$response->is_success) {
    die "$progname: Failed to retrieve transitions list: $!\n";
}

die "$progname: Unable to parse transition information: $yaml_broken\n"
    unless have_yaml();

my $yaml = YAML::Syck::Load($response->content);
my $packagelist = join("|", map {qq/\Q$_\E/} @ARGV);
my $found = 0;

foreach my $transition(keys(%{$yaml})) {
    my $data = $yaml->{$transition};

    my @affected = grep /^($packagelist)$/, @{$data->{packages}};

    if (@affected) {
	print "\n\n" if $found;
	$found = 1;
	print "The following packages are involved in the $transition transition:\n";
	print map {qq(  - $_\n)} @affected;

	print "\nDetails of this transition:\n"
	    . "  - Reason: $data->{reason}\n"
	    . "  - Release team contact: $data->{rm}\n";
    }
}

if (!$found) {
    print "$progname: No packages examined are currently blocked\n";
}

exit $found;

sub help {
   print <<"EOF";
Usage: $progname [options] source_package_list
Valid options are:
   --help, -h             Display this message
   --version, -v          Display version and copyright info
   --filename, -f         Read source package information from the specified
                          filename (which should be a Debian package control
                          file or changes file)
EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
Copyright (C) 2008 by Adam D. Barratt <adam\@adam-barratt.org.uk>,

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2, or (at your option) any
later version.
EOF
}

