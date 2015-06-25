#! /usr/bin/perl

# Copyright Bill Allombert <ballombe@debian.org> 2001.
# Modifications copyright 2002 Julian Gilbey <jdg@debian.org>

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

package Devscripts::Packages;

use strict;
use warnings;
use Carp;
use Dpkg::Control;

BEGIN{
  use Exporter   ();
  use vars       qw(@EXPORT @ISA %EXPORT_TAGS);
  @EXPORT=qw(PackagesToFiles FilesToPackages PackagesMatch InstalledPackages);
  @ISA=qw(Exporter);
  %EXPORT_TAGS=();
}

=head1 NAME

Devscript::Packages - Interface to the dpkg package database

=head1 SYNOPSIS

use Devscript::Packages;

@files=PackagesToFiles(@packages);

@packages=FilesToPackages(@files);

@packages=PackagesMatch($regexp);

$packages_hashref=InstalledPackages($sources);

=head1 DESCRIPTION


PackagesToFiles: Return a list of files contained in a list of packages.

FilesToPackages: Return a list of packages containing at least
one file in a list of files, taking care to handle diversions correctly.

PackagesMatch: list of packages whose status match regexp.

InstalledPackages: ref to hash with keys being installed packages
(status = install ok installed).  If $sources is true, then include
the corresponding source packages as well in the list.

=cut

my $multiarch;

sub multiarch ()
{
    if (!defined $multiarch) {
	$multiarch = (system('dpkg --assert-multi-arch >/dev/null 2>&1') >> 8) == 0;
    }
    return $multiarch;
}

# input: a list of packages names.
# output: list of files they contain.

sub PackagesToFiles (@)
{
    return () if @_ == 0;

    my %files=();

    # We fork and use an exec, so that we don't have to worry how long an
    # input string the shell can handle.

    my $pid;
    my $sleep_count=0;
    do {
	$pid = open(DPKG, "-|");
	unless (defined $pid) {
	    carp("cannot fork: $!");
	    croak("bailing out") if $sleep_count++ > 6;
	    sleep 10;
	}
    } until defined $pid;

    if ($pid) {   # parent
	while (<DPKG>) {
	    chomp;
	    next if /^package diverts others to: / or -d $_;
	    $files{$_} = 1;
	}
	close DPKG or croak("dpkg -L failed: $!");
    } else {      # child
	# We must use C locale, else diversion messages may be translated.
	$ENV{'LC_ALL'}='C';
	exec('dpkg', '-L', @_)
	    or croak("can't exec dpkg -L: $!");
    }

    return keys %files;
}


# This basically runs a dpkg -S with a few bells and whistles
#
# input:  a list of files.
# output: list of packages they belong to.

sub FilesToPackages (@)
{
    return () if @_ == 0;

    # We fork and use an exec, so that we don't have to worry how long an
    # input string the shell can handle.

    my @dpkg_out;
    my $pid;
    my $sleep_count=0;
    do {
	$pid = open(DPKG, "-|");
	unless (defined $pid) {
	    carp("cannot fork: $!");
	    croak("bailing out") if $sleep_count++ > 6;
	    sleep 10;
	}
    } until defined $pid;

    if ($pid) {   # parent
	while (<DPKG>) {
	    # We'll process it later
	    chomp;
	    push @dpkg_out, $_;
	}
	if (! close DPKG) {
	    # exit status of 1 just indicates unrecognised files
	    if ($? & 0xff || $? >> 8 != 1) {
		carp("warning: dpkg -S exited with signal " . ($? & 0xff) . " and status " . ($? >> 8));
	    }
	}
    } else {      # child
	# We must use C locale, else diversion messages may be translated.
	$ENV{'LC_ALL'}='C';
	open STDERR, '>& STDOUT';  # Capture STDERR as well
	exec('dpkg', '-S', @_)
	    or croak("can't exec dpkg -S: $!");
    }


    my %packages=();
    foreach my $curfile (@_) {
	my $pkgfrom;
	foreach my $line (@dpkg_out) {
	    # We want to handle diversions nicely.
	    # Ignore local diversions
	    if ($line =~ /^local diversion from: /) {
		# Do nothing
	    }
	    elsif ($line =~ /^local diversion to: (.+)$/) {
		if ($curfile eq $1) {
		    last;
		}
	    }
	    elsif ($line =~ /^diversion by (\S+) from: (.+)$/) {
		if ($curfile eq $2) {
		    # So the file we're looking has been diverted
		    $pkgfrom=$1;
		}
	    }
	    elsif ($line =~ /^diversion by (\S+) to: (.+)$/) {
		if ($curfile eq $2) {
		    # So the file we're looking is a diverted file
		    # We shouldn't see it again
		    $packages{$1} = 1;
		    last;
		}
	    }
	    elsif ($line =~ /^dpkg: \Q$curfile\E not found\.$/) {
		last;
	    }
	    elsif ($line =~ /^dpkg-query: no path found matching pattern \Q$curfile\E\.$/) {
		last;
	    }
	    elsif ($line =~ /^(.*): \Q$curfile\E$/) {
		my @pkgs = split /,\s+/, $1;
		if (@pkgs == 1 || !grep /:/, @pkgs) {
		    # Only one package, or all Multi-Arch packages
		    map { $packages{$_} = 1 } @pkgs;
		}
		else {
		    # We've got a file which has been diverted by some package
		    # or is Multi-Arch and so is listed in two packages.  If it
		    # was diverted, the *diverting* package is the one with the
		    # file that was actually used.
		    my $found=0;
		    foreach my $pkg (@pkgs) {
			if ($pkg eq $pkgfrom) {
			    $packages{$pkgfrom} = 1;
			    $found=1;
			    last;
			}
		    }
		    if (! $found) {
			carp("Something wicked happened to the output of dpkg -S $curfile");
		    }
		}
		# Prepare for the next round
		last;
	    }
	}
    }

    return keys %packages;
}


# Return a list of packages whose status entries match a given pattern

sub PackagesMatch ($)
{
    my $match=$_[0];
    my @matches=();

    open STATUS, '/var/lib/dpkg/status'
	or croak("Can't read /var/lib/dpkg/status: $!");

    my $ctrl;
    while (defined($ctrl = Dpkg::Control->new())
	   && $ctrl->parse(\*STATUS, '/var/lib/dpkg/status')) {
	if ("$ctrl" =~ m/$match/m) {
	    my $package = $ctrl->{Package};
	    if ($ctrl->{Architecture} ne 'all' && multiarch) {
		$package .= ":$ctrl->{Architecture}";
	    }
	    push @matches, $package;
	}
	undef $ctrl;
    }

    close STATUS or croak("Problem reading /var/lib/dpkg/status: $!");
    return @matches;
}


# Which packages are installed (Package and Source)?

sub InstalledPackages ($)
{
    my $source = $_[0];

    open STATUS, '/var/lib/dpkg/status'
	or croak("Can't read /var/lib/dpkg/status: $!");

    my $ctrl;
    my %matches;
    while (defined($ctrl = Dpkg::Control->new(type => CTRL_FILE_STATUS))
	   && $ctrl->parse(\*STATUS, '/var/lib/dpkg/status')) {
	if ($ctrl->{Status} !~ /^install\s+ok\s+installed$/) {
	    next;
	}
	if ($source) {
	    if (exists $ctrl->{Source}) {
		$matches{$ctrl->{Source}} = 1;
	    }
	}
	if (exists $ctrl->{Package}) {
	    $matches{$ctrl->{Package}} = 1;
	    if ($ctrl->{Architecture} ne 'all' && multiarch) {
		$matches{"$ctrl->{Package}:$ctrl->{Architecture}"} = 1;
	    }
	}
	undef $ctrl;
    }

    close STATUS or croak("Problem reading /var/lib/dpkg/status: $!");

    return \%matches;
}

1;

=head1 AUTHOR

Bill Allombert <ballombe@debian.org>

=head1 COPYING

Copyright 2001 Bill Allombert <ballombe@debian.org>
Modifications copyright 2002 Julian Gilbey <jdg@debian.org>
dpkg-depcheck is free software, covered by the GNU General Public License, and
you are welcome to change it and/or distribute copies of it under
certain conditions.  There is absolutely no warranty for dpkg-depcheck.

=cut
