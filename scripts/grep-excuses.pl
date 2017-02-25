#!/usr/bin/perl
# Grep debian testing excuses file.
#
# Copyright 2002 Joey Hess <joeyh@debian.org>
# Small mods Copyright 2002 Julian Gilbey <jdg@debian.org>

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

use 5.006;
use strict;
use warnings;
use File::Basename;

# Needed for --wipnity option

open DEBUG, ">/dev/null" or die $!;
my $do_autoremovals = 1;

my $term_size_broken;

sub have_term_size {
    return ($term_size_broken ? 0 : 1) if defined $term_size_broken;
    pop @INC if $INC[-1] eq '.';
    # Load the Term::Size module safely
    eval { require Term::Size; };
    if ($@) {
	if ($@ =~ /^Can\'t locate Term\/Size\.pm/) {
	    $term_size_broken="the libterm-size-perl package is not installed";
	} else {
	    $term_size_broken="couldn't load Term::Size: $@";
	}
    } else {
	$term_size_broken = 0;
    }

    return ($term_size_broken ? 0 : 1);
}

my $progname = basename($0);
my $modified_conf_msg;

my $url='https://release.debian.org/britney/update_excuses.html.gz';

my $rmurl='https://udd.debian.org/cgi-bin/autoremovals.cgi';
my $rmurl_yaml='https://udd.debian.org/cgi-bin/autoremovals.yaml.cgi';

# No longer use these - see bug#309802
my $cachedir = $ENV{'HOME'}."/.devscripts_cache/";
my $cachefile = $cachedir . basename($url);
unlink $cachefile if -f $cachefile;

sub usage {
    print <<"EOF";
Usage: $progname [options] [<maintainer>|<package>]
  Grep the Debian update_excuses file to find out about the packages
  of <maintainer> or <package>.  If neither are given, use the configuration
  file setting or the environment variable DEBFULLNAME to determine the
  maintainer name.
Options:
  --no-conf, --noconf Don\'t read devscripts config files;
                      must be the first option given
  --wipnity, -w       Check <https://qa.debian.org/excuses.php>.  A package
                      name must be given when using this option.
  --no-autoremovals   Do not investigate and report autoremovals
  --help              Show this help
  --version           Give version information
  --debug             Print debugging output to stderr

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2002 by Joey Hess <joeyh\@debian.org>,
and modifications are copyright 2002 by Julian Gilbey <jdg\@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF

sub wipnity
{
    die "$progname: Couldn't run wipnity: $term_size_broken\n" unless have_term_size();

    my $columns = Term::Size::chars();

    if (system("command -v w3m >/dev/null 2>&1") != 0) {
	die "$progname: wipnity mode requires the w3m package to be installed\n";
    }

    while( my $package=shift ) {
	my $dump = `w3m -dump -cols $columns "https://qa.debian.org/excuses.php?package=$package"`;
	$dump =~ s/.*(Excuse for .*)\s+Maintainer page.*/$1/ms;
	$dump =~ s/.*(No excuse for .*)\s+Maintainer page.*/$1/ms;
	print($dump);
    }
}

# Now start by reading configuration files and then command line
# The next stuff is boilerplate

my $string;

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'GREP_EXCUSES_MAINTAINER' => '',
		       );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
	$shell_cmd .= "$var='$config_vars{$var}';\n";
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $string = $config_vars{'GREP_EXCUSES_MAINTAINER'};
}

while (@ARGV and $ARGV[0] =~ /^-/) {
    if ($ARGV[0] eq '--wipnity' or $ARGV[0] eq '-w') {
	if (@ARGV) {
	    shift;
	    $string=shift;
	}
	if (! $string or $string eq '') {
	    die "$progname: no package specified!\nTry $progname --help for help.\n";
	}
	if (@ARGV) {
	    die "$progname: too many arguments!  Try $progname --help for help.\n";
	} else { wipnity($string); exit 0; }
    }
    if ($ARGV[0] eq '--debug') {
	open DEBUG, ">&STDERR" or die $!;
	shift; next;
    }
    if ($ARGV[0] eq '--no-autoremovals') { $do_autoremovals=0; shift; next; }
    if ($ARGV[0] eq '--help') { usage(); exit 0; }
    if ($ARGV[0] eq '--version') { print $version; exit 0; }
    if ($ARGV[0] =~ /^--no-?conf$/) {
	die "$progname: $ARGV[0] is only acceptable as the first command-line option!\n";
    }
    die "$progname: unrecognised option $ARGV[0]; try $progname --help for help\n";
}

if (! $string and exists $ENV{'DEBFULLNAME'}) {
    $string = $ENV{'DEBFULLNAME'};
}

if (@ARGV) {
    $string=shift;
}
if ($string eq '') {
    die "$progname: no maintainer or package specified!\nTry $progname --help for help.\n";
}
if (@ARGV) {
    die "$progname: too many arguments!  Try $progname --help for help.\n";
}

if (system("command -v wget >/dev/null 2>&1") != 0) {
    die "$progname: this program requires the wget package to be installed\n";
}

sub grep_autoremovals () {
    print DEBUG "Fetching $rmurl\n";

    unless (open REMOVALS, "wget -q -O - $rmurl |") {
	warn "$progname: wget $rmurl failed: $!\n";
	return;
    }

    my $wantmaint = 0;
    my %reportpkgs;

    while (<REMOVALS>) {
	if (m%^https?:%) {
	    next;
	}
	if (m%^\S%) {
	    $wantmaint = m%^\Q$string\E\b%;
	    next;
	}
	if (m%^$%) {
	    $wantmaint = undef;
	    next;
	}
	if (defined $wantmaint && m%^\s+([0-9a-z][-.+0-9a-z]*):\s*(.*)%) {
	    next unless $wantmaint || $1 eq $string;
	    warn "$progname: package $1 repeated in $rmurl at line $.:\n$_"
		if defined $reportpkgs{$1};
	    $reportpkgs{$1} = $2;
	    next;
	}
	warn "$progname: unprocessed line $. in $rmurl:\n$_";
    }
    $?=0;
    unless (close REMOVALS) {
	my $rc = $? >> 8;
	warn "$progname: fetch $rmurl failed ($rc $!)\n";
    }

    return unless %reportpkgs;

    print DEBUG "Fetching $rmurl_yaml\n";

    unless (open REMOVALS, "wget -q -O - $rmurl_yaml |") {
	warn "$progname: wget $rmurl_yaml failed: $!\n";
	return;
    }

    my $reporting = 0;
    while (<REMOVALS>) {
	if (m%^([0-9a-z][-.+0-9a-z]*):$%) {
	    my $pkg = $1;
	    my $human = $reportpkgs{$pkg};
	    delete $reportpkgs{$pkg};
	    $reporting = !!defined $human;
	    if ($reporting) {
		print"$pkg (AUTOREMOVAL)\n  $human\n" or die $!;
	    }
	    next;
	}
	if (m%^[ \t]%) {
	    if ($reporting) {
		print "    ", $_ or die $!;
	    }
	    next;
	}
	if (m%^$% || m%^\#% || m{^---$}) {
	    next;
	}
	warn "$progname: unprocessed line $. in $rmurl_yaml:\n$_";
    }

    $?=0;
    unless (close REMOVALS)
    {
	my $rc = $? >> 8;
	warn "$progname: fetch $rmurl_yaml failed ($rc $!)\n";
    }

    foreach my $pkg (keys %reportpkgs) {
	print "$pkg (AUTOREMOVAL)\n  $reportpkgs{$pkg}\n" or die $!;
    }
}

grep_autoremovals() if $do_autoremovals;

print DEBUG "Fetching $url\n";

open EXCUSES, "wget -q -O - $url | zcat |" or
    die "$progname: wget | zcat failed: $!\n";

my $item='';
my $mainlist=0;
my $sublist=0;
while (<EXCUSES>) {
    if (! $mainlist) {
	# Have we found the start of the actual content?
	next unless /^\s*<ul>\s*$/;
	$mainlist=1;
	next;
    }
    # Have we reached the end?
    if (! $sublist and m%</ul>%) {
	$mainlist=0;
	next;
    }
    next unless $mainlist;
    # Strip hyperlinks
    my $saveline=$_;
    s%<a\s[^>]*>%%g;
    s%</a>%%g;
    s%&gt;%>%g;
    s%&lt;%<%g;
    # New item?
    if (! $sublist and /^\s*<li>/) {
	s%<li>%%;
	s%<li>%\n%g;
	$item = $_;
    }
    elsif (! $sublist and /^\s*<ul>/) {
	$sublist=1;
    }
    elsif ($sublist and m%</ul>%) {
	$sublist=0;
	# Did the last item match?
	if ($item=~/^-?\Q$string\E\s/ or
	    $item=~/^\s*Maintainer:\s[^\n]*\b\Q$string\E\b[^\n]*$/m) {
	    print $item;
	}
    }
    elsif ($sublist and /^\s*<li>/) {
	s%<li>%    %;
	s%<li>%\n    %g;
	$item .= $_;
    }
    else {
	warn "$progname: unrecognised line in update_excuses (line $.):\n$saveline";
    }
}
close EXCUSES or die "$progname: read/zcat failed: $!\n";

exit 0;
