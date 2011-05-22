# Based vaguely on the deprecated dpkg-perl package modules
# Dpkg::Package::List and Dpkg::Package::Package.
# This module creates an object which holds package names and dependencies
# (just Depends and Pre-Depends).
# It can also calculate the total set of subdependencies using the
# fulldepends method.
#
# Copyright 2002 Julian Gilbey <jdg@debian.org>
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
use Carp;
require 5.006_000;

package Devscripts::PackageDeps;

# This reads in a package file list, such as /var/lib/dpkg/status,
# and parses it.

# Syntax: new Devscripts::PackageDeps($filename)

sub new ($$)
{
    my $this = shift;
    my $class = ref ($this) || $this;
    my $filename = shift;

    my $self = {};

    if (! defined $filename) {
	croak ("requires filename as parameter");
    }

    bless ($self, $class);
    $self->parse ($filename);
    return $self;
}


# Internal function

sub parse ($$)
{
    my $self = shift;
    my $filename = shift;

    if (! defined $filename) {
	croak("requires filename as parameter");
    }
    open PACKAGE_FILE, $filename or
	croak("Unable to load $filename: $!");

    local $/;
    $/="";  # Split on blank lines

 PACKAGE_ENTRY:
    while (<PACKAGE_FILE>) {
	if (/^\s*$/) { next; }

	# So we've got a package
	my $pkg;
	my @deps = ();

	chomp;
	s/\n\s+/\376\377/g; # fix continuation lines
	s/\376\377\s*\376\377/\376\377/og;

	while (/^(\S+):\s*(.*?)\s*$/mg) {
	    my ($key, $value) = (lc $1, $2);
	    $value =~ s/\376\377/\n /g;
	    if ($key eq 'package') { $pkg = $value; }
	    elsif ($key =~ /^(pre-)?depends$/) {
		$value =~ s/\(.*?\)//g;  # ignore versioning information
		$value =~ tr/ \t//d;  # remove spaces
		my @dep_pkgs = split /,/, $value;
		foreach my $dep_pkg (@dep_pkgs) {
		    my @dep_pkg_alts = split /\|/, $dep_pkg;
		    if (@dep_pkg_alts == 1) { push @deps, $dep_pkg_alts[0]; }
		    else { push @deps, \@dep_pkg_alts; }
		}
	    }
	    elsif ($key eq 'status') {
		unless ($value =~ /^\S+\s+\S+\s+(\S+)$/) {
		    warn "Unrecognised Status line in $filename:\nStatus: $value\n";
		}
		my $status = $1;
		# Hopefully, the system is in a nice state...
		# Ignore broken packages and removed but not purged packages
		next PACKAGE_ENTRY unless
		    $status eq 'installed' or $status eq 'unpacked';
	    }
	}

	$self->{$pkg} = \@deps;
    }
    close PACKAGE_FILE or
	croak("Problems encountered reading $filename: $!");
}


# Get direct dependency information for a specified package
# Returns an array or array ref depending on context

# Syntax: $obj->dependencies($package)

sub dependencies ($$)
{
    my $self = shift;
    my $pkg = shift;

    if (! defined $pkg) {
	croak("requires package as parameter");
    }

    if (! exists $self->{$pkg}) {
	return undef;
    }

    return wantarray ?
	@{$self->{$pkg}} : $self->{$pkg};
}


# Get full dependency information for a specified package or packages,
# including the packages themselves.
#
# This only follows the first of sets of alternatives, and ignores
# dependencies on packages which do not appear to exist.
# Returns an array or array ref

# Syntax: $obj->full_dependencies(@packages)

sub full_dependencies ($@)
{
    my $self = shift;
    my @toprocess = @_;
    my %deps;

    return wantarray ? () : [] unless @toprocess;

    while (@toprocess) {
	my $next = shift @toprocess;
	$next = $$next[0] if ref $next;
	# Already seen?
	next if exists $deps{$next};
	# Known package?
	next unless exists $self->{$next};
	# Mark it as a dependency
	$deps{$next} = 1;
	push @toprocess, @{$self->{$next}};
    }

    return wantarray ? keys %deps : [ keys %deps ];
}


# Given a set of packages, find a minimal set with respect to the
# pre-partial order of dependency.
#
# This is vaguely based on the dpkg-mindep script by
# Bill Allombert <ballombe@debian.org>.  It only follows direct
# dependencies, and does not attempt to follow indirect dependencies.
#
# This respects the all packages in sets of alternatives.
# Returns: (\@minimal_set, \%dependencies)
# where the %dependencies hash is of the form
#   non-minimal package => depending package

# Syntax: $obj->min_dependencies(@packages)

sub min_dependencies ($@)
{
    my $self = shift;
    my @pkgs = @_;
    my @min_pkgs = ();
    my %dep_pkgs = ();

    return (\@min_pkgs, \%dep_pkgs) unless @pkgs;

    # We create a directed graph: the %forward_deps hash records arrows
    # pkg A depends on pkg B; the %reverse_deps hash records the
    # reverse arrows
    my %forward_deps;
    my %reverse_deps;

    # Initialise
    foreach my $pkg (@pkgs) {
	$forward_deps{$pkg} = {};
	$reverse_deps{$pkg} = {};
    }

    foreach my $pkg (@pkgs) {
	next unless exists $self->{$pkg};
	my @pkg_deps = @{$self->{$pkg}};
	while (@pkg_deps) {
	    my $dep = shift @pkg_deps;
	    if (ref $dep) {
		unshift @pkg_deps, @$dep;
		next;
	    }
	    if (exists $forward_deps{$dep}) {
		$forward_deps{$pkg}{$dep} = 1;
		$reverse_deps{$dep}{$pkg} = 1;
	    }
	}
    }

    # We start removing packages from the tree if they have no dependencies.
    # Once we have no such packages left, we must have mutual or cyclic
    # dependencies, so we pick a random one to remove and then start again.
    # We continue this until there are no packages left in the graph.
 PACKAGE:
    while (scalar keys %forward_deps) {
	foreach my $pkg (keys %forward_deps) {
	    if (scalar keys %{$forward_deps{$pkg}} == 0) {
		# Great, no dependencies!
		if (scalar keys %{$reverse_deps{$pkg}}) {
		    # This package is depended upon, so we can remove it
		    # with care
		    foreach my $dep_pkg (keys %{$reverse_deps{$pkg}}) {
			# take the first mentioned package for the
			# recorded list of depended-upon packages
			$dep_pkgs{$pkg} ||= $dep_pkg;
			delete $forward_deps{$dep_pkg}{$pkg};
		    }
		} else {
		    # This package is not depended upon, so it must
		    # go into our mindep list
		    push @min_pkgs, $pkg;
		}
		# Now remove this node
		delete $forward_deps{$pkg};
		delete $reverse_deps{$pkg};
		next PACKAGE;
	    }
	}

	# Oh, we didn't find any package which didn't depend on any other.
	# We'll pick a random one, then.  At least *some* package must
	# be depended upon in this situation; let's pick one of these.
	foreach my $pkg (keys %forward_deps) {
	    next unless scalar keys %{$reverse_deps{$pkg}} > 0;

	    foreach my $dep_pkg (keys %{$forward_deps{$pkg}}) {
		delete $reverse_deps{$dep_pkg}{$pkg};
	    }
	    foreach my $dep_pkg (keys %{$reverse_deps{$pkg}}) {
		# take the first mentioned package for the
		# recorded list of depended-upon packages
		$dep_pkgs{$pkg} ||= $dep_pkg;
		delete $forward_deps{$dep_pkg}{$pkg};
	    }

	    # Now remove this node
	    delete $forward_deps{$pkg};
	    delete $reverse_deps{$pkg};
	    # And onto the next package
	    goto PACKAGE;
	}

	# Ouch!  We shouldn't ever get here
	croak("Couldn't determine mindeps; this can't happen!");
    }

    return (\@min_pkgs, \%dep_pkgs);
}

1;
