#!/usr/bin/perl

# rc-alert - find RC bugs for programs on your system
# Copyright (C) 2003 Anthony DeRobertis
# Modifications Copyright 2003 Julian Gilbey <jdg@debian.org>
# Modifications Copyright 2008 Adam D. Barratt <adam@adam-barratt.org.uk>
# Modifications copyright 2009 by Jan Hauke Rahm <info@jhr-online.de>
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
use warnings;
use lib '/usr/share/devscripts';
use Devscripts::Packages;
use File::Basename;
use Getopt::Long qw(:config gnu_getopt);

sub remove_duplicate_values($);
sub store_if_relevant(%);
sub human_flags($);
sub unhtmlsanit($);
sub dt_parse_request($);

my $cachedir = $ENV{'HOME'}."/.devscripts_cache/";
my $url = "http://bugs.debian.org/release-critical/other/all.html";
my $cachefile = $cachedir . basename($url);
my $forcecache = 0;
my $usecache = 0;

my %flagmap = ( '(P)' => "pending",
		'.(\+)' => "patch",
		'..(H)' => "help [wanted]",
		'...(M)' => "moreinfo [needed]",
		'....(R)' => "unreproducible",
		'.....(S)' => "security",
		'......(U)' => "upstream",
		'.......(I)' => "wheezy-ignore or squeeze-ignore",
	      );
# A little hacky but allows us to sort the list by length
my %distmap = ( '(O)' => "oldstable",
		'.?(S)' => "stable",
		'.?.?(T)' => "testing",
		'.?.?.?(U)' => "unstable",
		'.?.?.?.?(E)' => "experimental");

my $includetags = "";
my $excludetags = "";

my $includedists = "";
my $excludedists = "";

my $tagincoperation = "or";
my $tagexcoperation = "or";
my $distincoperation = "or";
my $distexcoperation = "or";

my $popcon = 0;
my $popcon_by_vote = 0;
my $popcon_local = 0;

my $debtags = '';
my $debtags_db = '/var/lib/debtags/package-tags';

my $progname = basename($0);

my $usage = <<"EOF";
Usage: $progname [--help|--version|--cache] [package ...]
  List all installed packages (or listed packages) with
  release-critical bugs, as determined from the Debian
  release-critical bugs list.

  Options:
  --cache           Create ~/.devscripts_cache directory if it does not exist

  Matching options: (see the manpage for further information)
  --include-tags     Set of tags to include
  --include-tag-op   Must all tags match for inclusion?
  --exclude-tags     Set of tags to exclude
  --exclude-tag-op   Must all tags match for exclusion?
  --include-dists    Set of distributions to include
  --include-dist-op  Must all distributions be matched for inclusion?
  --exclude-dists    Set of distributions to exclude
  --exclude-dist-op  Must all distributions be matched for exclusion?

  Debtags options: (only list packages with matching debtags)
  --debtags          Comma separated list of tags
                       (e.g. implemented-in::perl,role::plugin)
  --debtags-database Database file (default: /var/lib/debtags/package-tags)

  Popcon options:
  --popcon           Sort bugs by package's popcon rank
  --pc-vote          Sort by_vote instead of by_inst
                       (see popularity-contest(8))
  --pc-local         Use local popcon data from last popcon run
                       (/var/log/popularity-contest)
EOF

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2003 by Anthony DeRobertis
Modifications copyright 2003 by Julian Gilbey <jdg\@debian.org>
Modifications copyright 2008 by Adam D. Barratt <adam\@adam-barratt.org.uk>
Modifications copyright 2009 by Jan Hauke Rahm <info\@jhr-online.de>
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
	   "include-tags|f=s" => \$includetags,
	   "exclude-tags=s" => \$excludetags,
	   "include-tag-op|t=s" => \$tagincoperation,
	   "exclude-tag-op=s" => \$tagexcoperation,
	   "include-dists|d=s" => \$includedists,
	   "exclude-dists=s" => \$excludedists,
	   "include-dist-op|o=s" => \$distincoperation,
	   "exclude-dist-op=s" => \$distexcoperation,
	   "debtags=s" => \$debtags,
	   "debtags-database=s" => \$debtags_db,
	   "popcon" => \$popcon,
	   "pc-vote" => \$popcon_by_vote,
	   "pc-local" => \$popcon_local,
	   ) or do { print $usage; exit 1; };

if ($opt_help) { print $usage; exit 0; }
if ($opt_version) { print $version; exit 0; }

$tagincoperation =~ /^(or|and)$/ or $tagincoperation = 'or';
$distincoperation =~ /^(or|and)$/ or $distincoperation = 'or';
$tagexcoperation =~ /^(or|and)$/ or $tagexcoperation = 'or';
$distexcoperation =~ /^(or|and)$/ or $distexcoperation = 'or';
$includetags =~ s/[^P+HMRSUI]//gi;
$excludetags =~ s/[^P+HMRSUI]//gi;
$includedists =~ s/[^OSTUE]//gi;
$excludedists =~ s/[^OSTUE]//gi;
$includetags = remove_duplicate_values(uc($includetags));
$excludetags = remove_duplicate_values(uc($excludetags));
$includedists = remove_duplicate_values(uc($includedists));
$excludedists = remove_duplicate_values(uc($excludedists));

## First download the RC bugs page

my $curl_or_wget;
my $getcommand;
if (system("command -v wget >/dev/null 2>&1") == 0) {
    $curl_or_wget = "wget";
    $getcommand = "wget -q -O -";
} elsif (system("command -v curl >/dev/null 2>&1") == 0) {
    $curl_or_wget = "curl";
    $getcommand = "curl -qfs";
} else {
    die "$progname: this program requires either the wget or curl package to be installed\n";
}


if (! -d $cachedir and $forcecache) {
    mkdir $cachedir
	or die "$progname: can't make cache directory $cachedir: $!\n";
}

if (-d $cachedir) {
    chdir $cachedir or die "$progname: can't cd $cachedir: $!\n";

    if ("$curl_or_wget" eq "wget") {
        # Either use the cached version because the remote hasn't been
        # updated (-N) or download a complete new copy (--no-continue)
	if (system('wget', '-qN', '--no-continue', $url) != 0) {
	    die "$progname: wget failed!\n";
	}
    } elsif ("$curl_or_wget" eq "curl") {
	if (system('curl', '-qfsR', $url) != 0) {
	    die "$progname: curl failed!\n";
	}
    } else {
	die "$progname: Unknown download program $curl_or_wget!\n";
    }
    open BUGS, $cachefile or die "$progname: could not read $cachefile: $!\n";
}
else {
    open BUGS, "$getcommand $url |" or
	die "$progname: could not run $curl_or_wget: $!\n";
}

## Get list of installed packages (not source packages)
my $package_list;
if (@ARGV) {
    my %tmp = map { $_ => 1 } @ARGV;
    $package_list = \%tmp;
}
else {
    $package_list = InstalledPackages(1);
}

## Get popcon information
my %popcon;
if ($popcon) {
    my $pc_by = $popcon_by_vote ? 'vote' : 'inst';

    my $pc_regex;
    if ($popcon_local) {
	open POPCON, "/var/log/popularity-contest"
	    or die "$progname: Unable to access popcon data: $!";
	$pc_regex = '(\d+)\s\d+\s(\S+)';
    } else {
	open POPCON, "$getcommand http://popcon.debian.org/by_$pc_by.gz | gunzip -c |"
	    or die "$progname: Not able to receive remote popcon data!";
	$pc_regex = '(\d+)\s+(\S+)\s+(\d+\s+){5}\(.*\)';
    }

    while (<POPCON>) {
	next unless /$pc_regex/;
	# rank $1 for package $2
	if ($popcon_local) {
	    # negative for inverse sorting of atimes
	    $popcon{$2} = "-$1";
	} else {
	    $popcon{$2} = $1;
	}
    }
    close POPCON;
}

## Get debtags info
my %dt_pkg;
my @dt_requests;
if ($debtags) {
    ## read debtags database to %dt_pkg
    open DEBTAGS, $debtags_db or die "$progname: could not read debtags database: $!\n";
    while (<DEBTAGS>) {
        next unless /^(.+?)(?::?\s*|:\s+(.+?)\s*)$/;
        $dt_pkg{$1} = $2;
    }
    close DEBTAGS;

    ## and parse the request string
    @dt_requests = dt_parse_request($debtags);
}

## Read the list of bugs

my $found_bugs_start;
my ($current_package, $comment);

my %pkg_store;
while (defined(my $line = <BUGS>)) {
    if( $line =~ /^<div class="package">/) {
	$found_bugs_start = 1;
    }
    if( ! defined($found_bugs_start)) {
	next;
    } elsif ($line =~ m%<a name="([^\"]+)"><strong>Package:</strong></a> <a href="[^\"]+">%i) {
	$current_package = $1;
	$comment = '';
    } elsif ($line =~ m%<a name="(\d+)"></a>\s*<a href="[^\"]+">\d+</a> (\[[^\]]+\])( \[[^\]]+\])? ([^<]+)%i) {
	my ($num, $tags, $dists, $name) = ($1, $2, $3, $4);
	chomp $name;
	store_if_relevant(pkg => $current_package, num => $num, tags => $tags, dists => $dists, name => $name, comment => $comment);
    }
}
for (sort {$a <=> $b } keys %pkg_store) { print $pkg_store{$_}; }

close BUGS or die "$progname: could not close $cachefile: $!\n";

exit 0;

sub remove_duplicate_values($) {
    my $in = shift || "";

    $in = join( "", sort { $a cmp $b } split //, $in );

    $in =~ s/(.)\1/$1/g while $in =~ /(.)\1/;

    return $in;
}

sub store_if_relevant(%) {
    my %args = @_;

    my $pkgname = $args{pkg};
    $args{pkg} =~ s/^src://;

    if (exists($package_list->{$args{pkg}})
        || exists($package_list->{$pkgname})) {
	# potentially relevant
	my ($flags, $flagsapply) = human_flags($args{tags});
	my $distsapply = 1;
	my $dists;
	($dists, $distsapply) = human_dists($args{dists}) if defined $args{dists};

	return unless $flagsapply and $distsapply;

	foreach (@dt_requests) {
	    ## the array should be empty if nothing requested
	    return unless ($dt_pkg{$args{pkg}} and
		$dt_pkg{$args{pkg}} =~ /(\A|,\s*)$_(,|\z)/);
	}

	# yep, relevant
	my $bug_string = "Package: $pkgname\n" .
	    $comment .  # non-empty comments always contain the trailing \n
	    "Bug:     $args{num}\n" .
	    "Title:   " . unhtmlsanit($args{name}) . "\n" .
	    "Flags:   " . $flags . "\n" .
	    (defined $args{dists} ? "Dists:  " . $dists . "\n" : "") .
	    (defined $dt_pkg{$args{pkg}} ?
		"Debtags: " . $dt_pkg{$args{pkg}} . "\n" : "");

	unless ($popcon_local) {
	    $bug_string .= (defined $popcon{$args{pkg}} ?
		"Popcon rank: " . $popcon{$args{pkg}} . "\n" : "");
	}
	$bug_string .= "\n";

	if ($popcon) {
	    return unless $bug_string;
	    my $index = $popcon{$args{pkg}} ? $popcon{$args{pkg}} : 9999999;
	    $pkg_store{$index} .= $bug_string;
	} else {
	    $pkg_store{1} .= $bug_string;
	}
    }
}

sub human_flags($) {
    my $mrf = shift;    # machine readable flags, for those of you wondering
    my @hrf = ();       # considering above, should be obvious
    my $matchedflags = 0;
    my $matchedexcludes = 0;
    my $applies = 1;

    foreach my $flag ( sort { length $a <=> length $b } keys %flagmap ) {
	if ($mrf =~ /^\[(?:$flag)/) {
	    if ($excludetags =~ /\Q$1\E/) {
		$matchedexcludes++;
	    } elsif ($includetags =~ /\Q$1\E/ or ! $includetags) {
		$matchedflags++;
	    }
	    push @hrf, $flagmap{$flag};
	}
    }
    if ($excludetags and $tagexcoperation eq 'and' and
	(length $excludetags == $matchedexcludes)) {
	$applies = 0;
    }
    elsif ($matchedexcludes and $tagexcoperation eq 'or') {
	$applies = 0;
    }
    elsif ($includetags and ! $matchedflags) {
	$applies = 0;
    } elsif ($includetags and $tagincoperation eq 'and' and
	(length $includetags != $matchedflags)) {
	$applies = 0;
    }

    if (@hrf) {
	return ("$mrf (" . join(", ", @hrf) . ')', $applies);
    } else {
	return ("$mrf (none)", $applies);
    }
}

sub human_dists($) {
    my $mrf = shift;     # machine readable flags, for those of you wondering
    my @hrf = ();        # considering above, should be obvious
    my $matcheddists = 0;
    my $matchedexcludes = 0;
    my $applies = 1;

    foreach my $dist ( sort { length $a <=> length $b } keys %distmap ) {
	if ($mrf =~ /(?:$dist)/) {
	    if ($excludedists =~ /$dist/) {
		$matchedexcludes++;
	    } elsif ($includedists =~ /$dist/ or ! $includedists) {
		$matcheddists++;
	    }
	    push @hrf, $distmap{$dist};
	}
    }
    if ($excludedists and $distexcoperation eq 'and' and
	(length $excludedists == $matchedexcludes)) {
	$applies = 0;
    } elsif ($matchedexcludes and $distexcoperation eq 'or') {
	$applies = 0;
    } elsif ($includedists and ! $matcheddists) {
	$applies = 0;
    } elsif ($includedists and $distincoperation eq 'and' and
	(length $includedists != $matcheddists)) {
	$applies = 0;
    }

    if (@hrf) {
	return ("$mrf (" . join(", ", @hrf) . ')', $applies);
    } else {
	return ('', $applies);
    }
}

# Reverse of master.debian.org:/org/bugs.debian.org/cgi-bin/common.pl
sub unhtmlsanit ($) {
    my %saniarray = ('lt','<', 'gt','>', 'amp','&', 'quot', '"');
    my $in = $_[0];
    $in =~ s/&(lt|gt|amp|quot);/$saniarray{$1}/g;
    return $in;
}

sub dt_parse_request($) {
    my %dt_lookup;
    foreach (split /,/, $_[0]) {
	my ($d_key, $d_val) = split '::', $_;
	die "$progname: A debtag must be of the form 'key::value'. See debtags(1) for details!"
	    unless ($d_key and $d_val);
	if ($dt_lookup{$d_key}) {
	    $dt_lookup{$d_key} = "$dt_lookup{$d_key}|$d_val";
	} else {
	    $dt_lookup{$d_key} = quotemeta($d_val);
	}
    }

    my @out;
    while (my ($dk, $dv) = each %dt_lookup) {
	$dv = "($dv)" if ($dv =~ /\|/);
	push @out, $dk . "::" . $dv;
    }
    return @out;
}
