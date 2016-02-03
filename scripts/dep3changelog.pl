#!/usr/bin/perl

# dep3changelog: extract a DEP3 patch header from the named file and
# automatically update debian/changelog with a suitable entry
#
# Copyright 2010 Steve Langasek <vorlon@debian.org>
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
# USA

use 5.008;  # We're using PerlIO layers
use strict;
use warnings;
use open ':utf8';  # patch headers are required to be UTF-8

# for checking whether user names are valid and making format() behave
use Encode qw/decode_utf8 encode_utf8/;
use Getopt::Long;
use File::Basename;

# And global variables
my $progname = basename($0);
my %env;

sub usage () {
    print <<"EOF";
Usage: $progname patch [patch...] [options] [-- [dch options]]
Options:
   --help, -h
         Display this help message and exit
  --version
         Display version information
  Additional options specified after -- are passed to dch.
EOF
}

sub version () {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2010 by Steve Langasek, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

my ($opt_help, $opt_version);
GetOptions("help|h" => \$opt_help,
	   "version" => \$opt_version,
)
or die "Usage: $progname patch [... patch] [-- [dch options]]\nRun $progname --help for more details\n";

if ($opt_help) { usage; exit 0; }
if ($opt_version) { version; exit 0; }

my @patches;

while (@ARGV && $ARGV[0] !~ /^-/) {
    push(@patches,shift(@ARGV));
}

# Check, sanitise and decode these environment variables
check_env_utf8('DEBFULLNAME');
check_env_utf8('NAME');
check_env_utf8('DEBEMAIL');
check_env_utf8('EMAIL');

if (exists $env{'DEBEMAIL'} and $env{'DEBEMAIL'} =~ /^(.*)\s+<(.*)>$/) {
    $env{'DEBFULLNAME'} = $1 unless exists $env{'DEBFULLNAME'};
    $env{'DEBEMAIL'} = $2;
}
if (! exists $env{'DEBEMAIL'} or ! exists $env{'DEBFULLNAME'}) {
    if (exists $env{'EMAIL'} and $env{'EMAIL'} =~ /^(.*)\s+<(.*)>$/) {
	$env{'DEBFULLNAME'} = $1 unless exists $env{'DEBFULLNAME'};
	$env{'EMAIL'} = $2;
    }
}

my $fullname = '';
my $email = '';

if (exists $env{'DEBFULLNAME'}) {
    $fullname = $env{'DEBFULLNAME'};
} elsif (exists $env{'NAME'}) {
    $fullname = $env{'NAME'};
} else {
    my @pw = getpwuid $<;
    if ($pw[6]) {
	if (my $pw = decode_utf8($pw[6])) {
	    $pw =~ s/,.*//;
	    $fullname = $pw;
	} else {
	    warn "$progname warning: passwd full name field for uid $<\nis not UTF-8 encoded; ignoring\n";
	}
    }
}

if (exists $env{'DEBEMAIL'}) {
    $email = $env{'DEBEMAIL'};
} elsif (exists $env{'EMAIL'}) {
    $email = $env{'EMAIL'};
}

for my $patch (@patches) {
    my $shebang = 0;
    my $dpatch = 0;
    # TODO: more than one debian or launchpad bug in a patch?
    my ($description,$author,$debbug,$lpbug,$origin);

    next unless (open PATCH, $patch);
    while (<PATCH>) {
	# first line only
	if (!$shebang) {
	    $shebang = 1;
	    if (/^#!/) {
		$dpatch = $shebang = 1;
		next;
	    }
	}
	last if (/^---/ || /^\s*$/);
	chomp;
	# only if there was a shebang do we strip comment chars
	s/^# // if ($dpatch);
	# fixme: this should only apply to the description field.
	next if (/^ /);

	if (/^(Description|Subject):\s+(.*)\s*/) {
	    $description = $2;
	} elsif (/^(Author|From):\s+(.*)\s*/) {
	    $author = $2;
	} elsif (/^Origin:\s+(.*)\s*/) {
	    $origin = $1;
	} elsif (/^bug-debian:\s+https?:\/\/bugs\.debian\.org\/([0-9]+)\s*/i) {
	    $debbug = $1;
	} elsif (/^bug-ubuntu:\s+https:\/\/.*launchpad\.net\/.*\/([0-9]+)\s*/i) {
	    $lpbug = $1;
	}
    }
    close PATCH;
    if (!$description || (!$origin && !$author)) {
	warn "$patch: Invalid DEP3 header\n";
	next;
    }
    my $changelog = "$patch: $description";
    $changelog .= '.' unless ($changelog =~ /\.$/);
    if ($author && $author ne $fullname && $author ne "$fullname <$email>")
    {
	$changelog .= "  Thanks to $author.";
    }
    if ($debbug || $lpbug) {
	$changelog .= '  Closes';
	$changelog .= ": #$debbug" if ($debbug);
	$changelog .= "," if ($debbug && $lpbug);
	$changelog .= " LP: #$lpbug" if ($lpbug);
	$changelog .= '.';
    }
    system('dch',$changelog,@ARGV);
}

# Is the environment variable valid or not?
sub check_env_utf8 {
    my $envvar = $_[0];

    if (exists $ENV{$envvar} and $ENV{$envvar} ne '') {
	if (! decode_utf8($ENV{$envvar})) {
	    warn "$progname warning: environment variable $envvar not UTF-8 encoded; ignoring\n";
	} else {
	    $env{$envvar} = decode_utf8($ENV{$envvar});
	}
    }
}
