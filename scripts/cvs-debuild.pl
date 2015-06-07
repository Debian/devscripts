#!/usr/bin/perl

# A wrapper for cvs-buildpackage to use debuild, still giving access
# to all of debuild's functionality.

# Copyright 2003, Julian Gilbey <jdg@debian.org>
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


# We will do simple option processing.  The calling syntax of this
# program is:
#
# cvs-debuild [<debuild options>] [<cvs-buildpackage options>]
#           [--lintian-opts <lintian options>]
#
# cvs-debuild will run cvs-buildpackage, using debuild as the
# package-building program, passing the debuild and lintian options to
# it.  For details of these options, and more information on debuild in
# general, refer to debuild(1).

use 5.006;
use strict;
use warnings;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempfile /;
use Fcntl;

my $progname=basename($0);

# Predeclare functions
sub fatal($);

sub usage
{
    print <<"EOF";
  $progname [<debuild options>] [<cvs-buildpackage options>]
             [--lintian-opts <lintian options>]
  to run cvs-buildpackage using debuild as the package building program

  Accepted debuild options, see debuild(1) or debuild --help for more info:
    --no-conf, --noconf
    --lintian, --no-lintian
    --rootcmd=<gain-root-command>, -r<gain-root-command>
    --preserve-envvar=<envvar>, -e<envvar>
    --set-envvar=<envvar>=<value>, -e<envvar>=<value>
    --preserve-env
    --check-dirname-level=<value>, --check-dirname-regex=<regex>
    -d, -D

    --help            display this message
    --version         show version and copyright information
  All cvs-buildpackage options are accepted, as are all lintian options.

  Note that any cvs-buildpackage options (command line or configuration file)
  for setting a root command will override any debuild configuration file
  options for this.

Default settings modified by devscripts configuration files:
  (no configuration files are read by $progname)
For information on default debuild settings modified by the
configuration files, run:  debuild --help
EOF
}

sub version
{
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2003 by Julian Gilbey <jdg\@debian.org>,
all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

# First check we can execute cvs-buildpackage
unless (system("command -v cvs-buildpackage >/dev/null 2>&1") == 0) {
    fatal "can't run cvs-buildpackage; have you installed it?";
}

# We start by parsing the command line to collect debuild and
# lintian options.  We stash them away in temporary files,
# which we will pass to debuild.

my (@debuild_opts, @cvs_opts, @lin_opts);
{
    no locale;
    # debuild opts first
    while (@ARGV) {
	my $arg=shift;
	$arg eq '--help' and usage(), exit 0;
	$arg eq '--version' and version(), exit 0;

	# rootcmd gets passed on to cvs-buildpackage
	if ($arg eq '-r' or $arg eq '--rootcmd') {
	    push @cvs_opts, '-r' . shift;
	    next;
	}
	if ($arg =~ /^(?:-r|--rootcmd=)(.*)$/) {
	    push @cvs_opts, "-r$1";
	    next;
	}

	# other debuild options are stashed
	if ($arg =~ /^--(no-?conf|(no-?)?lintian)$/) {
	    push @debuild_opts, $arg;
	    next;
	}
	if ($arg =~ /^--preserve-env$/) {
	    push @debuild_opts, $arg;
	    next;
	}
	if ($arg =~ /^--check-dirname-(level|regex)$/) {
	    push @debuild_opts, $arg, shift;
	    next;
	}
	if ($arg =~ /^--check-dirname-(level|regex)=/) {
	    push @debuild_opts, $arg;
	    next;
	}
	if ($arg =~ /^--(preserve|set)-envvar$/) {
	    push @debuild_opts, $arg, shift;
	    next;
	}
	if ($arg =~ /^--(preserve|set)-envvar=/) {
	    push @debuild_opts, $arg;
	    next;
	}
	# dpkg-buildpackage now has a -e option, so we have to be
	# careful not to confuse the two; their option will always have
	# the form -e<maintainer email> or similar
	if ($arg eq '-e') {
	    push @debuild_opts, $arg, shift;
	    next;
	}
	if ($arg =~ /^-e(\w+(=.*)?)$/) {
	    push @debuild_opts, $arg;
	    next;
	}
	if ($arg eq '-d' or $arg eq '-D') {
	    push @debuild_opts, $arg;
	    next;
	}
	# Anything else matching /^-e/ is a dpkg-buildpackage option,
	# and we've also now considered all debuild options.
	# So now handle cvs-buildpackage options
	unshift @ARGV, $arg;
	last;
    }

    while (@ARGV) {
	my $arg=shift;
	if ($arg eq '-L' or $arg eq '--lintian') {
	    fatal "$arg argument not recognised; use --lintian-opts instead";
	}
	if ($arg =~ /^--lin(tian|da)-opts$/) {
	    push @lin_opts, $arg;
	    last;
	}
	push @cvs_opts, $arg;
    }

    if (@ARGV) {
	push @lin_opts, @ARGV;
    }
}

# So we've now got three arrays, and we'll have to store the debuild
# options in temporary files
my $debuild_cmd='debuild --cvs-debuild';
my ($fhdeb, $fhlin);
if (@debuild_opts) {
    $fhdeb = tempfile("cvspreXXXXXX", UNLINK => 1)
	or fatal "cannot create temporary file: $!";
    fcntl $fhdeb, Fcntl::F_SETFD(), 0
	or fatal "disabling close-on-exec for temporary file: $!";
    print $fhdeb join("\0", @debuild_opts);
    $debuild_cmd .= ' --cvs-debuild-deb /dev/fd/' . fileno($fhdeb);
}
if (@lin_opts) {
    $fhlin = tempfile("cvspreXXXXXX", UNLINK => 1)
	or fatal "cannot create temporary file: $!";
    fcntl $fhlin, Fcntl::F_SETFD(), 0
	or fatal "disabling close-on-exec for temporary file: $!";
    print $fhlin join("\0", @lin_opts);
    $debuild_cmd .= ' --cvs-debuild-lin /dev/fd/' . fileno($fhlin);
}

# Now we can run cvs-buildpackage
my $status = system('cvs-buildpackage', '-C'.$debuild_cmd, @cvs_opts);

if ($status & 255) {
    die "cvs-debuild: cvs-buildpackage terminated abnormally: " .
	sprintf("%#x",$status) . "\n";
} else {
    exit ($status >> 8);
}


sub fatal($) {
    my ($pack,$file,$line);
    ($pack,$file,$line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    die $msg;
}
