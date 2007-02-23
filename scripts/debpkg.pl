#! /usr/bin/perl -w

# Perl version of Christoph Lameter's debpkg program.
# Written by Julian Gilbey, December 1998.

# Copyright 1999, Julian Gilbey
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


# All this program does is to check that it is either running as root
# or setuid root, and then exec dpkg with the command line options.

# As this may be running setuid, we make sure to clean out the
# environment before we go further.  Also wise for building the
# packages, anyway.  We don't put /usr/local/bin in the PATH as Debian
# programs will presumably be built without the use of any locally
# installed programs.  This could be changed, but in which case,
# you probably want to add /usr/local/bin at the END so that you don't
# get any unexpected behaviour.

use 5.003;
use File::Basename;

my $progname = basename($0);

# Predeclare functions
sub fatal($);

my $usage = "Usage: $progname --help|--version|dpkg-options\n";

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999 by Julian Gilbey, all rights reserved.
Based on code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF

##
## handle command-line options
##
if (! @ARGV) { print STDERR $usage; exit 1; }
if ($ARGV[0] eq '--help') { print $usage; exit 0; }
if ($ARGV[0] eq '--version') { print $version; exit 0; }

# We *do* preserve locale variables; dpkg should know how to handle
# them, and anyone running this with root privileges has total power
# over the system anyway, so doesn't really need to worry about forging
# locale data.  We don't try to preserve TEXTDOMAIN and the like.
foreach $var (keys %ENV) {
	delete $ENV{$var} unless
		$var =~ /^(PATH|TERM|HOME|LOGNAME|LANG)$/ or
			$var =~ /^LC_[A-Z]+$/;
}

$ENV{'PATH'} = "/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/X11";
# $ENV{'PATH'} = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/X11";
$ENV{'TERM'}='dumb' unless defined $ENV{'TERM'};

# Pick up superuser privileges if we are running setuid root
if ( $< != 0 && $> == 0 ) { $< = $>; }
fatal "debpkg is only useful if it is run by root or setuid root!"
	if $< != 0;

# Pick up group 'root'
$( = $) = 0;

# @ARGV is tainted, so we need to untaint it.  Don't bother doing any
# checking; anyone running this as root can do anything anyway.
my @clean_argv = map { /^(.*)$/ && $1; } @ARGV;
exec 'dpkg', @clean_argv or fatal "Couldn't exec dpkg: $!\n";

###### Subroutines

sub fatal($) {
    my ($pack,$file,$line);
    ($pack,$file,$line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
	 $msg =~ s/\n\n$/\n/;
    die $msg;
}
