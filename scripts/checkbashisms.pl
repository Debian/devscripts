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
use Getopt::Long;

(my $progname = $0) =~ s|.*/||;

my $usage = <<"EOF";
Usage: $progname [-n] [-f] script ...
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

my ($opt_echo, $opt_force);
my ($opt_help, $opt_version);

##
## handle command-line options
##
GetOptions("help|h" => \$opt_help,
	   "version|v" => \$opt_version,
	   "newline|n" => \$opt_echo,
	   "force|f" => \$opt_force,
           )
    or die "Usage: $progname [options] filelist\nRun $progname --help for more details\n";

if (int(@ARGV) == 0 or $opt_help) { print $usage; exit 0; }
if ($opt_version) { print $version; exit 0; }

my $status = 0;

foreach my $filename (@ARGV) {
    if (!$opt_force and script_is_evil_and_wrong($filename)) {
	warn "script $filename does not appear to be a /bin/sh script; skipping\n";
	next;
    }
    unless (open C, "$filename") {
	warn "cannot open script $filename for reading: $!\n";
	$status |= 2;
	next;
    }

    my $cat_string = "";
    my $quote_string = "";

    while (<C>) {
	if ($. == 1) { # This should be an interpreter line
	    if (m,^\#!\s*(\S+),) {
		next if $opt_force;
		my $interpreter = $1;
		if ($interpreter =~ m,/bash$,) {
		    warn "script $filename is already a bash script; skipping\n";
		    $status |= 2;
		    last;  # end this file
		}
		elsif ($interpreter !~ m,/(sh|ash|dash|posh)$,) {
### ksh/zsh?
		    warn "script $filename does not appear to be a /bin/sh script; skipping\n";
		    $status |= 2;
		    last;
		}
	    } else {
		warn "script $filename does not appear to have a \#! interpreter line;\nyou may get strange results\n";
	    }
	}

	next if m,^\s*\#,;  # skip comment lines
	chomp;
	my $orig_line = $_;

	s/(?<!\\)\#.*$//;   # eat comments

	if ($cat_string ne "" and m/^$cat_string/) {
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
	    my $explanation = '';
	    my %bashisms = (
		'(?:^|\s+)function\s+\w+' =>   q<'function' is useless>,
		'(?:^|\s+)select\s+\w+' =>     q<'select' is not POSIX>,
		'(?:^|\s+)source\s+(?:\.\/|\/|\$)[^\s]+' =>
		                               q<should be '.', not 'source'>,
		'(\[|test|-o|-a)\s*[^\s]+\s+==\s' =>
		                               q<should be 'b = a'>,
		'\s\|\&' =>                    q<pipelining is not POSIX>,
		'[^\\\]\{([^\s]+?,)+[^\\\}\s]+\}' =>
		                               q<brace expansion>,
		'(?:^|\s+)\w+\[\d+\]=' =>      q<bash arrays, H[0]>,
		'(?:^|\s+)(read\s*(?:;|$))' => q<read without variable>,
		'\$\(\([A-Za-z]' => q<cnt=$((cnt + 1)) does not work in dash>,
		'(?:^|\s+)echo\s+-[e]' =>      q<echo -e>,
		'(?:^|\s+)exec\s+-[acl]' =>    q<exec -c/-l/-a name>,
		'(?:^|\s+)let\s' =>            q<let ...>,
		'(?<![\$\(])\(\(.*\)\)' =>     q<'((' should be '$(('>,
		'(\[|test)\s+-a' =>            q<test with unary -a (should be -e)>,
		'\&>' =>	               q<should be \>word 2\>&1>,
		'(<\&|>\&)\s*((-|\d+)[^\s;|)`&]|[^-\d\s])' =>
					       q<should be \>word 2\>&1>,
		'(?:^|\s+)kill\s+-[^sl]\w*' => q<kill -[0-9] or -[A-Z]>,
		'(?:^|\s+)trap\s+["\']?.*["\']?\s+.*[1-9]' => q<trap with signal numbers>,
		'\[\[(?!:)' => q<alternative test command ([[ foo ]] should be [ foo ])>,
		'<<<'                       => q<\<\<\< here string>,
		'/dev/(tcp|udp)'	    => q</dev/(tcp|udp)>,
		'(?:^|\s+)suspend\s' =>        q<suspend>,
		'(?:^|\s+)caller\s' =>         q<caller>,
		'(?:^|\s+)complete\s' =>       q<complete>,
		'(?:^|\s+)compgen\s' =>        q<compgen>,
		'(?:^|\s+)declare\s' =>        q<declare>,
		'(?:^|\s+)typeset\s' =>        q<typeset>,
		'(?:^|\s+)disown\s' =>         q<disown>,
		'(?:^|\s+)builtin\s' =>        q<builtin>,
		'(?:^|\s+)set\s+-[BHT]+' =>    q<set -[BHT]>,
		'(?:^|\s+)alias\s+-p' =>       q<alias -p>,
		'(?:^|\s+)unalias\s+-a' =>     q<unalias -a>,
		'(?:^|\s+)local\s+-[a-zA-Z]+' => q<local -opt>,
		'(?:^|\s+)local\s+\w+=' =>     q<local foo=bar>,
	    );

	    my %string_bashisms = (
		'\$\[\w+\]' =>                 q<arithmetic not allowed>,
		'\$\{\w+\:\d+(?::\d+)?\}' =>   q<${foo:3[:1]}>,
		'\$\{!\w+[\@*]\}' =>           q<${!prefix[*|@]>,
		'\$\{!\w+\}' =>                q<${!name}>,
		'\$\{\w+(/.+?){1,2}\}' =>      q<${parm/?/pat[/str]}>,
		'\$\{\#?\w+\[[0-9\*\@]+\]\}' => q<bash arrays, ${name[0|*|@]}>,
		'(\$\(|\`)\s*\<\s*\S+\s*(\)|\`)' => q<'$(\< foo)' should be '$(cat foo)'>,
		'\$\{?RANDOM\}?\b' =>          q<$RANDOM>,
		'\$\{?(OS|MACH)TYPE\}?\b'   => q<$(OS|MACH)TYPE>,
		'\$\{?HOST(TYPE|NAME)\}?\b' => q<$HOST(TYPE|NAME)>,
		'\$\{?DIRSTACK\}?\b'        => q<$DIRSTACK>,
		'\$\{?EUID\}?\b'	    => q<$EUID should be "id -u">,
		'\$\{?SECONDS\}?\b'	    => q<$SECONDS>,
		'\$\{?BASH(_[A-Z]+)?\}?\b'   => q<$BASH(_SOMETHING)>,
	    );

	    if ($opt_echo) {
		$bashisms{'echo\s+-[n]'} = 'q<echo -n>';
	    }

	    my $line = $_;

	    if ($quote_string ne "") {
		# Inside a quoted block
		if ($line =~ /^(?:.*?[^\\])?$quote_string(.*)$/) {
		    my $rest = $1;
		    my $count = () = $line =~ /(^|[^\\])?$quote_string/g;
		    if ($count % 2 == 1) {
			# Quoted block ends on this line
			# Ignore everything before the closing quote
			$line = $rest || '';
			$quote_string = "";
		    } else {
			next;
		    }
		} else {
		    # Still inside the quoted block, skip this line
		    next;
		}
	    } elsif ($line =~ /(?:^|[^\\])([\"\'])\s*\{?\s*$/) {
		# Possible start of a quoted block
		my $temp = $1;
		my $count = () = $line =~ /(^|[^\\])$temp/g;

		# If there's an odd number of non-escaped
		# quotes in the line and the line ends with
		# one, it's almost certainly the start of
		# a quoted block.
		$quote_string = $temp if ($count % 2 == 1);
	    }

	    # since this test is ugly, I have to do it by itself
	    # detect source (.) trying to pass args to the command it runs
	    if (not $found and m/^\s*(\.\s+[^\s;\`]+\s+([^\s;]+))/) {
		if ($2 =~ /^(\&|\||\d?>|<)/) {
		    # everything is ok
		    ;
		} else {
		    $found = 1;
		    $match = $1;
		    $explanation = "sourced script with arguments";
		}
	    }

	    unless ($found) {
		# Ignore anything inside single quotes; it could be an
		# argument to grep or the like.
		$line =~ s/(^|[^\\](?:\\\\)*)\'(?:\\.|[^\\\'])+\'/$1''/g;

		while (my ($re,$expl) = each %string_bashisms) {
		    if ($line =~ m/($re)/) {
			$found = 1;
			$match = $1;
		 	$explanation = $expl;
		 	last;
		    }
		}
	    }

	    # We've checked for all the things we still want to notice in
	    # double-quoted strings, so now remove those strings as well.
	    unless ($found) {
		$line =~ s/(^|[^\\](?:\\\\)*)\"(?:\\.|[^\\\"])+\"/$1""/g;
		while (my ($re,$expl) = each %bashisms) {
		    if ($line =~ m/($re)/) {
			$found = 1;
			$match = $1;
			$explanation = $expl;
			last;
		    }
		}
	    }

	    unless ($found == 0) {
		warn "possible bashism in $filename line $. ($explanation):\n$orig_line\n";
		$status |= 1;
	    }

	    # Only look for the beginning of a heredoc here, after we've
	    # stripped out quoted material, to avoid false positives.
	    if (m/(?:^|[^<])\<\<\s*[\'\"]?(\w+)[\'\"]?/) {
		$cat_string = $1;
	    }
	}
    }

    close C;
}

exit $status;

# Returns non-zero if the given file is not actually a shell script,
# just looks like one.
sub script_is_evil_and_wrong {
    my ($filename) = @_;
    my $ret = 0;
    # lintian's version of this function aborts if the file
    # can't be opened, but we simply return as the next
    # test in the calling code handles reporting the error
    # itself
    open (IN, '<', $filename) or return;
    my $i = 0;
    local $_;
    while (<IN>) {
        chomp;
        next if /^#/o;
        next if /^$/o;
        last if (++$i > 20);

        if (/(^\s*|\beval\s*\'|;\s*)exec\s*.+\s*.?\$0.?\s*(--\s*)?(\${1:?\+)?.?\$(\@|\*)/o) {
            $ret = 1;
            last;
        }
    }
    close IN;
    return $ret;
}

