#!/usr/bin/perl -w

# RCBugger - find RC bugs for programs on your system
# Copyright (C) 2003 Anthony DeRobertis
# Modifications Copyright 2003 Julian Gilbey <jdg@debian.org>
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

use strict;
use lib '/usr/share/devscripts';
use Devscripts::Packages;
use File::Basename;
use Getopt::Long;

sub print_if_relevant(%);
sub human_flags($);
sub unhtmlsanit($);

my $cachedir = $ENV{'HOME'}."/.testing-devscripts_cache/";
my $url = "http://bugs.debian.org/release-critical/other/all.html";
my $cachefile = $cachedir . basename($url);
my $forcecache = 0;
my $usecache = 0;

my $progname = basename($0);

my $usage = <<"EOF";
Usage: $progname [--help|--version|--cache]
  List all installed packages with release-critical bugs,
  as determined from the Debian release-critical bugs list.

  Options:
  --cache     Create ~/.devscripts_cache directory if it does not exist
EOF

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2003 by Anthony DeRobertis
Modifications copyright 2003 by Julian Gilbey <jdg\@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2, or (at your option) any later version.
EOF

##
## handle command-line options
##

my ($opt_help, $opt_version);
GetOptions("help|h" => \$opt_help,
	   "version|v" => \$opt_version,
	   "cache" => \$forcecache,
	   );

if ($opt_help) { print $usage; exit 0; }
if ($opt_version) { print $version; exit 0; }

## First download the RC bugs page

unless (system("command -v wget >/dev/null 2>&1") == 0) {
    die "$progname: this program requires the wget package to be installed\n";
}


if (! -d $cachedir and $forcecache) {
    mkdir $cachedir
	or die "$progname: can't make cache directory $cachedir: $!\n";
}

if (-d $cachedir) {
    chdir $cachedir or die "$progname: can't cd $cachedir: $!\n";

    if (system("wget -qN $url") != 0) {
	die "$progname: wget failed!\n";
    }
    open BUGS, $cachefile or die "$progname: could not read $cachefile: $!\n";
}
else {
    open BUGS, "wget -q -O - $url |" or
	die "$progname: could not run wget: $!\n";
}

## Get list of installed packages (not source packages)
my $package_list = InstalledPackages(0);

## Read the list of bugs

my $found_bugs_start;
my ($current_package, $comment);

while (defined(my $line = <BUGS>)) {
    if ($line =~ /^<pre>$/) {
	$found_bugs_start = 1;
	next;
    } elsif (! defined($found_bugs_start)) {
	next;
    } elsif ($line =~ m%^<a name="([^\"]+)"><strong>Package:</strong> <a href="[^\"]+">%i) {
	$current_package = $1;
	$comment = '';
    } elsif ($line =~ m%^\[%) {
	$comment .= $line;
    } elsif ($line =~ m%^<a name="(\d+)">\s*<a href="[^\"]+">\d+</a> (\[[^\]]+\])( \[[^\]]+\])? (.+)$%i) {
	print_if_relevant(pkg => $current_package, num => $1, tags => $2, dists => $3, name => $4, comment => $comment);
    }
}

close BUGS or die "$progname: could not close $cachefile: $!\n";

exit 0;


sub print_if_relevant(%) {
    my %args = @_;
    if (exists($$package_list{$args{pkg}})) {
	# yep, relevant
	print "Package: $args{pkg}\n",
	    $comment,  # non-empty comments always contain the trailing \n
	    "Bug:     $args{num}\n",
	    "Title:   " . unhtmlsanit($args{name}) , "\n",
	    "Flags:   " . human_flags($args{tags}) , "\n",
	    (defined $args{dists} ? "Dists:  " . human_dists($args{dists}) . "\n" : ""),
	    "\n";
    }
}

sub human_flags($) {
    my $mrf = shift;    # machine readable flags, for those of you wondering
    my @hrf = ();       # considering above, should be obvious
    $mrf =~ /^\[P/ and push(@hrf, "pending");
    $mrf =~ /^\[.\+/ and push(@hrf, "patch");
    $mrf =~ /^\[..H/ and push(@hrf, "help [wanted]");
    $mrf =~ /^\[...M/ and push(@hrf, "moreinfo [needed]");
    $mrf =~ /^\[....R/ and push(@hrf, "unreproducible");
    $mrf =~ /^\[.....S/ and push(@hrf, "security");
    $mrf =~ /^\[......U/ and push(@hrf, "upstream");

    if (@hrf) {
	return "$mrf (" . join(", ", @hrf) . ')';
    } else {
	return "$mrf (none)";
    }
}

sub human_dists($) {
    my $mrf = shift;     # machine readable flags, for those of you wondering
    my @hrf = ();        # considering above, should be obvious

    $mrf =~ /O/ and push(@hrf, "oldstable");
    $mrf =~ /S/ and push(@hrf, "stable");
    $mrf =~ /T/ and push(@hrf, "testing");
    $mrf =~ /U/ and push(@hrf, "unstable");
    $mrf =~ /X/ and push(@hrf, "not in testing");
    
    if (@hrf) {
	return "$mrf (" . join(", ", @hrf) . ')';
    } else {
	return '';
    }
}

# Reverse of master.debian.org:/org/bugs.debian.org/cgi-bin/common.pl
sub unhtmlsanit ($) {
    my %saniarray = ('lt','<', 'gt','>', 'amp','&', 'quot', '"');
    my $in = $_[0];
    $in =~ s/&(lt|gt|amp|quot);/$saniarray{$1}/g;
    return $in;
}
