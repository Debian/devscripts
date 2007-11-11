#!/usr/bin/perl

# Debian GNU/Linux chdist.  Copyright (C) 2007 Lucas Nussbaum and Luk Claes.
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

use Getopt::Long;

my $datadir = $ENV{'HOME'} . '/.chdist';

sub usage {
  return <<EOF;
Usage: chdist [options] [command] [command parameters]

Options:
    -h, --help                       Show this help
    -d, --data-dir DIR               Choose data directory (default: \$HOME/.chdist/

Commands:
  create DIST : prepare a new tree named DIST
  apt-get DIST (update|source|...) : run apt-get inside DIST
  apt-cache DIST (show|showsrc|...) : run apt-cache inside DIST
  apt-rdepends DIST [...] : run apt-rdepends inside DIST
  src2bin DIST PKG : get binary packages for a source package in DIST
  bin2src DIST PKG : get source package for a binary package in DIST
  compare-packages DIST1 DIST2 [DIST3, ...] : list versions of packages in
      several DISTributions
  compare-versions DIST1 DIST2 : same as compare-packages, but also run
      dpkg --compare-versions and display where the package is newer
  grep-dctrl-packages DIST [...] : run grep-dctrl on *_Packages inside DIST
  grep-dctrl-sources DIST [...] : run grep-dctrl on *_Sources inside DIST
EOF
}

# specify the options we accept and initialize
# the option parser
my $help     = '';
GetOptions(
  "help"       => \$help,
  "data-dir=s" => \$datadir,
);

if ($help) {
  print usage(0);
  exit;
}

########################################################
sub dist_check {
  my $dist = $_;
  my $dir  = $datadir . '/' . $dist;
  return 0 if (-d $dir);
  print "Could not find $dist in $datadir. Exiting.\n";
  exit(1);
}

sub aptopts {
  my $dist = @_[0];
  return "-o Dir=$datadir/$dist -o Dir::State::status=$datadir/$dist/var/lib/dpkg/status";
}

sub compare_versions {
  my $va = $_[0];
  my $vb = $_[1];
  return `dpkg --compare-versions $va lt $vb; echo $?`;
}

###

sub aptcache {
  my @args = @_;
  my $dist = shift @args;
  dist_check($dist);
  my $args = aptopts($dist) . " @args";
  system("/usr/bin/apt-cache $args");
}

sub aptget {
  my @args = @_;
  my $dist = shift @args;
  dist_check($dist);
  my $args = aptopts($dist) . " @args";
  system("/usr/bin/apt-get $args");
}

sub aptrdepends {
  my @args = @_;
  my $dist = shift @args;
  dist_check($dist);
  my $args = aptopts($dist) . " @args";
  system("/usr/bin/apt-rdepends $args");
}

sub bin2src {
  my @args = @_;
  my $dist = $args[0];
  dist_check($dist);
  my $args = aptopts($dist) . " show $args[1]";
  my $source = `/usr/bin/apt-cache $args|grep '^Source:'`;
  exit($?) if($? != 0);
  $source =~ s/Source: (.*)/$1/;
  print $args[1] if($source eq '');
  print $source if($source ne '');
}

sub src2bin {
  my @argv = @_;
  my $dist = $argv[0];
  dist_check($dist);
  my $args = aptopts($dist) . " showsrc $argv[1]";
  my $bins = `/usr/bin/apt-cache $args|sed 's/\(Package: .*\)\n/\(Binary: .*\)/\1\t\2/'|grep "Package: $argv[1]"|sed 's/.*Binary: \(.*\)\n/\1/'`;
  exit($?) if ($? != 0);
  my @bins = split /, /, $bins;
  print join "\n", @bins;
}

sub dist_create {
  my @argv = @_;
  my $dist = $argv[0];
  my $dir  = $datadir . '/' . $dist;
  if (-d $dir) {
    print "$dir already exists, exiting.\n";
    exit(1);
  }
  if (! -d $datadir) {
    mkdir($datadir);
  }
  mkdir($dir);
  foreach $d (('/etc/apt', '/var/lib/apt/lists/partial', '/var/lib/dpkg', '/var/cache/apt/archives/partial')) {
    my @temp = split /\//, $d;
    my $tres = $dir;
    foreach my $piece (@temp) {
      $tres .= "/$piece";
      mkdir($tres);
    }
  }
  open(FH, ">$dir/etc/apt/sources.list");
  print FH <<EOF;
#deb http://ftp.debian.org/debian/ unstable main contrib non-free
#deb-src http://ftp.debian.org/debian/ unstable main contrib non-free

#deb http://archive.ubuntu.com/ubuntu dapper main restricted
#deb http://archive.ubuntu.com/ubuntu dapper universe multiverse
#deb-src http://archive.ubuntu.com/ubuntu dapper main restricted
#deb-src http://archive.ubuntu.com/ubuntu dapper universe multiverse
EOF
  close FH;
  open(FH, ">$dir/var/lib/dpkg/status");
  close FH; #empty file
  print "Now edit $dir/etc/apt/sources.list\n";
  print "Then run chdist apt-get $dist update\n";
  print "And enjoy.\n";
}

sub dist_compare(\@;$) {
  my ($argv, $do_compare) = @_;
  $do_compare = 0 if $do_compare eq 'false';
  my @dists;
  my $n = 0;
  my @argv = @$argv;
  # read params
  foreach my $a (@argv) {
    $dists[$n] = $a;
    dist_check($dists[$n]);
    $n += 1;
  }
  if ($do_compare && $n != 2) {
    print "Can only compare if there are two distros.\n";
    exit(1);
  }
  # read Sources
  my @tot = ();
  my %packages;
  foreach my $dist (@dists) {
    foreach $f (glob($datadir . '/' . $dist . "/var/lib/apt/lists/*_Sources")) {
      my $pkg;
      open FILE, $f;
      foreach my $l (<FILE>) {
        chomp $l;
	if ($l =~ /^Package: /) {
          (my $ign, $pkg) = split /: /, $l;
	  push @tot, $pkg;
        }
        elsif ($l =~ /^Version: /) {
          (my $ign, $packages{$dist}{$pkg}) = split /: /, $l;
        }
      }
    }
  }
  # @out contains the uniq elements of @tot
  my %saw;
  @saw{@tot} = ();
  my @out = keys %saw;
  foreach my $pkg (@out) {  
    my $str = "$pkg";
    foreach $dist (@dists) {
      if ($packages{$dist}{$pkg}) {
        $str .= " $packages{$dist}{$pkg}";
      }
      else {
        $str .= " UNAVAIL";
      }
    }
    if ($do_compare) {
      # compare versions if run as compare-versions
      if (! $packages{$dists[0]}{$pkg}) {
        $dist = $dists[0];
        $str .= " not_in_$dist";
      }
      elsif (! $packages{$dists[1]}{$pkg}) {
        $dist = $dists[1];
	$str .= " not_in_$dist";
      }
      elsif ($packages{$dists[0]}{$pkg} eq $packages{$dists[1]}{$pkg}) {
        $str .= " same_version";
      }
      elsif (compare_versions($packages{$dists[0]}{$pkg}, $packages{$dists[1]}{$pkg})) {
        $dist = $dists[0];
	$str .= " newer_in_$dist";
      }
      else {
        $dist = $dists[1];
	$str .= " newer_in_$dist";
      }
    }
    print "$str\n";
  }
}

sub grep_file {
  my (@argv, $file) = @_;
  $dist = shift @argv;
  dist_check($dist);
  $f = glob($datadir . '/' . $dist . "/var/lib/apt/lists/*_$file");
  # FIXME avoid shell invoc, potential quoting problems here
  system("cat $f | grep-dctrl @argv");
}

########################################################
# Command parsing

my $command = shift @ARGV;
if ($command eq 'create') {
  dist_create(@ARGV);
}
elsif ($command eq 'apt-get') {
  aptget(@ARGV);
}
elsif ($command eq 'apt-cache') {
  aptcache(@ARGV);
}
elsif ($command eq 'apt-rdepends') {
  aptrdepends(@ARGV);
}
elsif ($command eq 'bin2src') {
  bin2src(@ARGV);
}
elsif ($command eq 'src2bin') {
  src2bin(@ARGV);
}
elsif ($command eq 'compare-packages') {
  dist_compare(@ARGV);
}
elsif ($command eq 'compare-versions') {
  dist_compare(@ARGV, 1);
}
elsif ($command eq 'grep-dctrl-packages') {
  grep_file(@ARGV, 'Packages');
}
elsif ($command eq 'grep-dctrl-sources') {
  grep_file(@ARGV, 'Sources');
}
else {
  print "Command unknown. Try $0 -h\n";
  exit(1);
}
