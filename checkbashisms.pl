#! /usr/bin/perl -w

# This script is essentially copied from /usr/share/lintian/checks/scripts,
# which is:
#   Copyright (C) 1998 Richard Braakman
#   Copyright (C) 2002 Josip Rodin
# This version is
#   Copyright (C) 2003 Julian Gilbey
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
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
# MA 02111-1307, USA.

use strict;

(my $progname = $0) =~ s|.*/||;

my $usage = <<"EOF";
Usage: $progname script ...
   or: $progname --help
   or: $progname --version
This script performs basic checks for the presence of bashisms
in /bin/sh scripts.
EOF

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2003 by Julian Gilbey <jdg\@debian.org>,
based on original code which is copyright 1998 by Richard Braakman
and copyright 2002 by Josip Rodin.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2, or (at your option) any later version.
EOF

##
## handle command-line options
##
if (@ARGV and $ARGV[0] =~ /^(--help|-h)$/) { print $usage; exit 0; }
if (@ARGV and $ARGV[0] =~ /^(--version|-v)$/) { print $version; exit 0; }


my $status = 0;

foreach my $filename (@ARGV) {
    unless (open C, "$filename") {
	warn "cannot open script $filename for reading: $!\n";
	$status |= 2;
	next;
    }

    my $cat_string = "";

    while (<C>) {
	if ($. == 1) { # This should be an interpreter line
	    if (m,^\#!\s*(\S+),) {
		my $interpreter = $1;
		if ($interpreter =~ m,/bash$,) {
		    warn "script $filename is already a bash script; skipping\n";
		    $status |= 2;
		    last;  # end this file
		}
		elsif ($interpreter !~ m,/(sh|ash|dash)$,) {
		    warn "script $filename does not appear to be a /bin/sh script; skipping\n";
		    $status |= 2;
		    last;
		}
	    } else {
		warn "script $filename does not appear to have a \#! interpreter line;\nyou may get strange results\n";
	    }
	}

	next if m,^\s*\#,;  # skip comment lines
	s/(?<!\\)\#.*$//;   # eat comments
	chomp;

	if (m/(?:^|\s+)cat\s*\<\<\s*(\w+)/) {
	    $cat_string = $1;
	}
	elsif ($cat_string ne "" and m/^$cat_string/) {
	    $cat_string = "";
	}
	my $within_another_shell = 0;
	if (m,(^|\s+)((/usr)?/bin/)?((b|d)?a|k|z|t?c)sh\s+-c\s*.+,) {
	    $within_another_shell = 1;
	}
	# if cat_string is set, we are in a HERE document and need not
	# check for things
	if ($cat_string eq "" and !$within_another_shell) {
	    my $found = 0;
	    my $match = '';
	    my @bashism_regexs = (
		'function \w+\(\s*\)',       # function is useless
		                             # should be '.', not 'source'
		'(?:^|\s+)source\s+(?:\.\/|\/|\$)[^\s]+',
		'(\[|test|-o|-a)\s*[^\s]+\s+==\s', # should be 'b = a'
		'\s\|\&',                    # pipelining is not POSIX
		'\$\[\w+\]',                 # arith not allowed
		'\$\{\w+\:\d+(?::\d+)?\}',   # ${foo:3[:1]}
		'\$\{\w+(/.+?){1,2}\}',      # ${parm/?/pat[/str]}
		'[^\\\]\{([^\s]+?,)+[^\\\}\s]+\}',     # brace expansion
		'(?:^|\s+)\w+\[\d+\]=',      # bash arrays, H[0]
		'\$\{\#?\w+\[[0-9\*\@]+\]\}',   # bash arrays, ${name[0|*|@]}
		'(?:^|\s+)(read\s*(?:;|$))'  # read without variable
	    );

	    for my $re (@bashism_regexs) {
		if (m/($re)/) {
		    $found = 1;
		    $match = $1;
		    last;
		}
	    }
	    # since this test is ugly, I have to do it by itself
	    # detect source (.) trying to pass args to the command it runs
	    if (not $found and m/^\s*(\.\s+[^\s]+\s+([^\s]+))/) {
		if ($2 eq '&&' || $2 eq '||') {
		    # everything is ok
		    ;
		} else {
		    $found = 1;
		    $match = $1;
		}
	    }
	    unless ($found == 0) {
		warn "possible bashism in $filename line $.: \'$match\'\n";
		$status |= 1;
	    }
	}
    }

    close C;
}

exit $status;
