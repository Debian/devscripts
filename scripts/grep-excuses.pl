#! /usr/bin/perl -w
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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use 5.006;
use strict;
use File::Basename;

# Needed for --wipnity option
use Term::Size;

my $progname = basename($0);
my $modified_conf_msg;

my $url='http://ftp-master.debian.org/testing/update_excuses.html.gz';

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
  --wipnity, -w       Get informations from <http://bjorn.haxx.se/debian/>
  --help              Show this help
  --version           Give version information

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

sub wipnity {
my $columns = Term::Size::chars();

while( my $package=shift ) {
    my $dump = `w3m -dump -cols $columns "http://bjorn.haxx.se/debian/testing.pl?package=$package"`;
    $dump =~ s/^.*?(?=Checking)//s;
    $dump =~ s/^\[.*//ms;
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

if (! $string and exists $ENV{'DEBFULLNAME'}) {
    $string = $ENV{'DEBFULLNAME'};
}

while (@ARGV and $ARGV[0] =~ /^-/) {
    if ($ARGV[0] eq '--wipnity' or $ARGV[0] eq '-w') {
	if (@ARGV) {
            shift;
            $string=shift;
        }
	if (! $string or $string eq '') {
            die "$progname: no maintainer or package specified!\nTry $progname --help for help.\n";
        }
        if (@ARGV) {
            die "$progname: too many arguments!  Try $progname --help for help.\n";
        } else { wipnity($string); exit 0; }
    }
    if ($ARGV[0] eq '--help') { usage(); exit 0; }
    if ($ARGV[0] eq '--version') { print $version; exit 0; }
    if ($ARGV[0] =~ /^--no-?conf$/) {
	die "$progname: $ARGV[0] is only acceptable as the first command-line option!\n";
    }
    die "$progname: unrecognised option $ARGV[0]; try $progname --help for help\n";
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

my $hostname = `hostname --fqdn`;
chomp $hostname;

if (system("command -v wget >/dev/null 2>&1") != 0) {
    die "$progname: this program requires the wget package to be installed\n";
}
    
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
	    # In case there are embedded <li> tags
	    $item =~ s%<li>%\n    %g;
	    print $item;
	}
    }
    elsif ($sublist and /^\s*<li>/) {
	s%<li>%    %;
	$item .= $_;
    }
    else {
	warn "$progname: unrecognised line in update_excuses (line $.):\n$saveline";
    }
}
close EXCUSES or die "$progname: read/zcat failed: $!\n";

exit 0;
