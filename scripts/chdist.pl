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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

chdist - script to easily play with several distributions

=head1 SYNOPSIS

B<chdist> [I<options>] [I<command>] [I<command parameters>]

=head1 DESCRIPTION

B<chdist> is a rewrite of what used to be known as 'MultiDistroTools'
(or mdt). Its use is to create 'APT trees' for several distributions,
making it easy to query the status of packages in other distribution
without using chroots, for instance.

=head1 OPTIONS

=over 4

=item B<-h>, B<--help>

Provide a usage message.

=item B<-d>, B<--data-dir> I<DIR>

Choose data directory (default: $HOME/.chdist/).

=item B<-a>, B<--arch> I<ARCH>

Choose architecture (default: `B<dpkg --print-architecture>`).

=item B<--version>

Display version information.

=back

=head1 COMMANDS

=over 4

=item B<create> I<DIST> : prepare a new tree named I<DIST>

=item B<apt-get> I<DIST> (B<update>|B<source>|...) : run B<apt-get> inside I<DIST>

=item B<apt-cache> I<DIST> (B<show>|B<showsrc>|...) : run B<apt-cache> inside I<DIST>

=item B<apt-rdepends> I<DIST> [...] : run B<apt-rdepends> inside I<DIST>

=item B<src2bin> I<DIST PKG> : get binary packages for a source package in I<DIST>

=item B<bin2src> I<DIST PKG> : get source package for a binary package in I<DIST>

=item B<compare-packages> I<DIST1 DIST2> [I<DIST3>, ...] : list versions of packages in several I<DIST>ributions

=item B<compare-bin-packages> I<DIST1 DIST2> [I<DIST3>, ...]

=item B<compare-versions> I<DIST1 DIST2> : same as B<compare-packages>, but also run B<dpkg --compare-versions> and display where the package is newer.

=item B<compare-bin-versions> I<DIST1 DIST2>

=item B<compare-src-bin-packages> I<DIST> : compare sources and binaries for I<DIST>

=item B<compare-src-bin-versions> I<DIST> : same as B<compare-src-bin-versions>, but also run I<dpkg --compare-versions> and display where the package is newer

=item B<grep-dctrl-packages> I<DIST> [...] : run B<grep-dctrl> on F<*_Packages> inside I<DIST>

=item B<grep-dctrl-sources> I<DIST> [...] : run B<grep-dctrl> on F<*_Sources> inside I<DIST>

=item B<list> : list available I<DIST>s

=back

=head1 COPYRIGHT

This program is copyright 2007 by Lucas Nussbaum and Luk Claes. This
program comes with ABSOLUTELY NO WARRANTY.

It is licensed under the terms of the GPL, either version 2 of the
License, or (at your option) any later version.

=cut

use strict;
use warnings;
use File::Basename;
use Getopt::Long qw(:config require_order);
use Cwd qw(abs_path cwd);
use Dpkg::Version;

my $progname = basename($0);

sub usage {
  return <<EOF;
Usage: chdist [options] [command] [command parameters]

Options:
    -h, --help                       Show this help
    -d, --data-dir DIR               Choose data directory (default: \$HOME/.chdist/)
    -a, --arch ARCH                  Choose architecture (default: `dpkg --print-architecture`)
    -v, --version                    Display version and copyright information

Commands:
  create DIST : prepare a new tree named DIST
  apt-get DIST (update|source|...) : run apt-get inside DIST
  apt-cache DIST (show|showsrc|...) : run apt-cache inside DIST
  apt-rdepends DIST [...] : run apt-rdepends inside DIST
  src2bin DIST PKG : get binary packages for a source package in DIST
  bin2src DIST PKG : get source package for a binary package in DIST
  compare-packages DIST1 DIST2 [DIST3, ...] : list versions of packages in
      several DISTributions
  compare-bin-packages DIST1 DIST2 [DIST3, ...]
  compare-versions DIST1 DIST2 : same as compare-packages, but also run
      dpkg --compare-versions and display where the package is newer
  compare-bin-versions DIST1 DIST2
  compare-src-bin-packages DIST : compare sources and binaries for DIST
  compare-src-bin-versions DIST : same as compare-src-bin-versions, but also
      run dpkg --compare-versions and display where the package is newer
  grep-dctrl-packages DIST [...] : run grep-dctrl on *_Packages inside DIST
  grep-dctrl-sources DIST [...] : run grep-dctrl on *_Sources inside DIST
  list : list available DISTs
EOF
}

# specify the options we accept and initialize
# the option parser
my $help     = '';

my $version = '';
my $versioninfo = <<"EOF";
This is $progname, from the Debian devscripts package, version
###VERSION### This code is copyright 2007 by Lucas Nussbaum and Luk
Claes. This program comes with ABSOLUTELY NO WARRANTY. You are free
to redistribute this code under the terms of the GNU General Public
License, version 2 or (at your option) any later version.
EOF

my $arch;
my $datadir = $ENV{'HOME'} . '/.chdist';

GetOptions(
  "help"       => \$help,
  "data-dir=s" => \$datadir,
  "arch=s"     => \$arch,
  "version"    => \$version,
);

# Fix-up relative paths
$datadir = cwd() . "/$datadir" unless $datadir =~ m!^/!;
$datadir = abs_path($datadir);

if ($help) {
  print usage(0);
  exit;
}

if ($version) {
  print $versioninfo;
  exit;
}


########################################################
### Functions
########################################################

sub uniq (@) {
	my %hash;
	map { $hash{$_}++ == 0 ? $_ : () } @_;
}

sub dist_check {
  # Check that dist exists in $datadir
  my ($dist) = @_;
  if ($dist) {
     my $dir  = $datadir . '/' . $dist;
     return 0 if (-d $dir);
     die "E: Could not find $dist in $datadir. Run `$0 create $dist` first. Exiting.\n";
  } else {
     die "E: No dist provided. Exiting. \n";
  }
}

sub type_check {
   my ($type) = @_;
   if ( ($type ne 'Sources') && ($type ne 'Packages') ) {
      die "E: Unknown type $type. Exiting.\n";
   }
}

sub aptopts {
  # Build apt options
  my ($dist) = @_;
  my $opts = "";
  if ($arch) {
     print "W: Forcing arch $arch for this command only.\n";
     $opts .= " -o Apt::Architecture=$arch";
  }
  return $opts;
}

sub aptconfig {
  # Build APT_CONFIG override
  my ($dist) = @_;
  return "APT_CONFIG=$datadir/$dist/etc/apt/apt.conf";
}

###

sub aptcache {
  # Run apt-cache cmd
  my ($dist, @args) = @_;
  dist_check($dist);
  my $args = aptopts($dist) . " @args";
  my $aptconfig = aptconfig($dist);
  system("$aptconfig /usr/bin/apt-cache $args");
}

sub aptget {
  # Run apt-get cmd
  my ($dist, @args) = @_;
  dist_check($dist);
  my $args = aptopts($dist) . " @args";
  my $aptconfig = aptconfig($dist);
  system("$aptconfig /usr/bin/apt-get $args");
}

sub aptrdepends {
  # Run apt-rdepends cmd
  my ($dist, @args) = @_;
  dist_check($dist);
  my $args = aptopts($dist) . " @args";
  my $aptconfig = aptconfig($dist);
  system("$aptconfig /usr/bin/apt-rdepends $args");
}

sub bin2src {
  my ($dist, $pkg) = @_;
  dist_check($dist);
  if (!$pkg) {
     die "E: no package name provided. Exiting.\n";
  }
  my $args = aptopts($dist) . " show $pkg";
  my $aptconfig = aptconfig($dist);
  my $source = `$aptconfig /usr/bin/apt-cache $args|grep '^Source:'`;
  exit($?) if($? != 0);
  $source =~ s/Source: (.*)/$1/;
  print $pkg if($source eq '');
  print $source if($source ne '');
}

sub src2bin {
  my ($dist, $pkg) = @_;
  dist_check($dist);
  if (!$pkg) {
     die "E: no package name provided. Exiting.\n";
  }
  my $args = aptopts($dist) . " showsrc $pkg";
  my $bins = `/usr/bin/apt-cache $args|sed -n '/^Package: $pkg/{N;p}' | sed -n 's/^Binary: \\(.*\\)/\\1/p'`;
  exit($?) if ($? != 0);
  my @bins = split /, /, $bins;
  print join "\n", @bins;
}


sub recurs_mkdir {
  my ($dir) = @_;
  my @temp = split /\//, $dir;
  my $createdir = "";
  foreach my $piece (@temp) {
     $createdir .= "/$piece";
     if (! -d $createdir) {
        mkdir($createdir);
     }
  }
}

sub dist_create {
  my ($dist, $method, $version, @sections) = @_;
  my $dir  = $datadir . '/' . $dist;
  if ( ! $dist ) {
     die "E: you must provide a dist name.\n";
  }
  if (-d $dir) {
    die "E: $dir already exists, exiting.\n";
  }
  if (! -d $datadir) {
    mkdir($datadir);
  }
  mkdir($dir);
  foreach my $d (('/etc/apt', '/var/lib/apt/lists/partial', '/var/lib/dpkg', '/var/cache/apt/archives/partial')) {
     recurs_mkdir("$dir/$d");
  }

  # Create sources.list
  open(FH, ">$dir/etc/apt/sources.list");
  if ($version) {
     # Use provided method, version and sections
     my $sections_str = join(' ', @sections);
     print FH <<EOF;
deb $method $version $sections_str
deb-src $method $version $sections_str
EOF
  } else {
     if ($method) {
        warn "W: method provided without a section. Using default content for sources.list\n";
     }
     # Fill in sources.list with example contents
     print FH <<EOF;
#deb http://ftp.debian.org/debian/ unstable main contrib non-free
#deb-src http://ftp.debian.org/debian/ unstable main contrib non-free

#deb http://archive.ubuntu.com/ubuntu dapper main restricted
#deb http://archive.ubuntu.com/ubuntu dapper universe multiverse
#deb-src http://archive.ubuntu.com/ubuntu dapper main restricted
#deb-src http://archive.ubuntu.com/ubuntu dapper universe multiverse
EOF
  }
  close FH;
  # Create dpkg status
  open(FH, ">$dir/var/lib/dpkg/status");
  close FH; #empty file
  # Create apt.conf
  $arch ||= `dpkg --print-architecture`;
  chomp $arch;
  open(FH, ">$dir/etc/apt/apt.conf");
  print FH <<EOF;
Apt {
   Architecture "$arch";
}

Dir "$dir";
Dir::State::status "$dir/var/lib/dpkg/status";
EOF
  close FH;
  print "Now edit $dir/etc/apt/sources.list\n";
  print "Then run chdist apt-get $dist update\n";
  print "And enjoy.\n";
}



sub get_distfiles {
  # Retrieve files to be read
  # Takes a dist and a type
  my ($dist, $type) = @_;

  # Let the above function check the type
  #type_check($type);

  my @files;

  foreach my $file ( glob($datadir . '/' . $dist . "/var/lib/apt/lists/*_$type") ) {
     if ( -f $file ) {
        push @files, $file;
     }
  }

  return \@files;
}


sub dist_compare(\@;$;$) {
  # Takes a list of dists, a type of comparison and a do_compare flag
  my ($dists, $do_compare, $type) = @_;
  # Type is 'Sources' by default
  $type ||= 'Sources';
  type_check($type);

  $do_compare = 0 if $do_compare eq 'false';

  # Get the list of dists from the referrence
  my @dists = @$dists;
  map { dist_check($_) } @dists;

  # Get all packages
  my %packages;

  foreach my $dist (@dists) {
     my $files = get_distfiles($dist,$type);
     my @files = @$files;
     foreach my $file ( @files ) {
        my $parsed_file = parseFile($file);
        foreach my $package ( keys(%{$parsed_file}) ) {
           if ( $packages{$dist}{$package} ) {
              warn "W: Package $package is already listed for $dist. Not overriding.\n";
           } else {
              $packages{$dist}{$package} = $parsed_file->{$package};
           }
        }
     }
  }

  # Get entire list of packages
  my @all_packages = uniq sort ( map { keys(%{$packages{$_}}) } @dists );

  foreach my $package (@all_packages) {
     my $line = "$package ";
     my $status = "";
     my $details;

     foreach my $dist (@dists) {
        if ( $packages{$dist}{$package} ) {
           $line .= "$packages{$dist}{$package}{'Version'} ";
        } else {
           $line .= "UNAVAIL ";
           $status = "not_in_$dist";
        }
     }

     my @versions = map { $packages{$_}{$package}{'Version'} } @dists;
     # Escaped versions
     my @esc_vers = @versions;
     foreach my $vers (@esc_vers) {
        $vers =~ s|\+|\\\+|;
     }
 
     # Do compare
     if ($do_compare) {
        if ($#dists != 1) {
           die "E: Can only compare versions if there are two distros.\n";
        }
        if (!$status) {
          my $cmp = version_compare($versions[0], $versions[1]);
          if (!$cmp) {
            $status = "same_version";
          } elsif ($cmp < 0) {
            $status = "newer_in_$dists[1]";
            if ( $versions[1] =~ m|^$esc_vers[0]| ) {
               $details = " local_changes_in_$dists[1]";
            }
          } else {
             $status = "newer_in_$dists[0]";
             if ( $versions[0] =~ m|^$esc_vers[1]| ) {
                $details = " local_changes_in_$dists[0]";
             }
          }
        }
        $line .= " $status $details";
     }
     
     print "$line\n";
  }
}


sub compare_src_bin {
   my ($dist, $do_compare) = @_;

   $do_compare = 0 if $do_compare eq 'false';

   dist_check($dist);


   # Get all packages
   my %packages;
   my @parse_types = ('Sources', 'Packages');
   my @comp_types  = ('Sources_Bin', 'Packages');

   foreach my $type (@parse_types) {
      my $files = get_distfiles($dist, $type);
      my @files = @$files;
      foreach my $file ( @files ) {
         my $parsed_file = parseFile($file);
         foreach my $package ( keys(%{$parsed_file}) ) {
            if ( $packages{$dist}{$package} ) {
               warn "W: Package $package is already listed for $dist. Not overriding.\n";
            } else {
               $packages{$type}{$package} = $parsed_file->{$package};
            }
         }
      }
   }

   # Build 'Sources_Bin' hash
   foreach my $package ( keys( %{$packages{Sources}} ) ) {
      my $package_h = \%{$packages{Sources}{$package}};
      if ( $package_h->{'Binary'} ) {
         my @binaries = split(", ", $package_h->{'Binary'});
         my $version  = $package_h->{'Version'};
         foreach my $binary (@binaries) {
            if ( $packages{Sources_Bin}{$binary} ) {
               # TODO: replace if new version is newer (use dpkg --compare-version?)
               warn "There is already a version for binary $binary. Not replacing.\n";
            } else {
               $packages{Sources_Bin}{$binary}{Version} = $version;
            }
         }
      } else {
         warn "Source $package has no binaries!\n";
      }
   }

   # Get entire list of packages
   my @all_packages = uniq sort ( map { keys(%{$packages{$_}}) } @comp_types );

  foreach my $package (@all_packages) {
     my $line = "$package ";
     my $status = "";
     my $details;

     foreach my $type (@comp_types) {
        if ( $packages{$type}{$package} ) {
           $line .= "$packages{$type}{$package}{'Version'} ";
        } else {
           $line .= "UNAVAIL ";
           $status = "not_in_$type";
        }
     }

     my @versions = map { $packages{$_}{$package}{'Version'} } @comp_types;
     # Escaped versions
     my @esc_vers = @versions;
     foreach my $vers (@esc_vers) {
        $vers =~ s|\+|\\\+|;
     }

     # Do compare
     if ($do_compare) {
        if ($#comp_types != 1) {
           die "E: Can only compare versions if there are two types.\n";
        }
        if (!$status) {
          my $cmp = version_compare($versions[0], $versions[1]);
          if (!$cmp) {
            $status = "same_version";
          } elsif ($cmp < 0) {
            $status = "newer_in_$comp_types[1]";
            if ( $versions[1] =~ m|^$esc_vers[0]| ) {
               $details = " local_changes_in_$comp_types[1]";
            }
          } else {
             $status = "newer_in_$comp_types[0]";
             if ( $versions[0] =~ m|^$esc_vers[1]| ) {
                $details = " local_changes_in_$comp_types[0]";
             }
          }
        }
        $line .= " $status $details";
     }

     print "$line\n";
  }
}

sub grep_file {
  my (@argv, $file) = @_;
  my $dist = shift @argv;
  dist_check($dist);
  my $f = glob($datadir . '/' . $dist . "/var/lib/apt/lists/*_$file");
  # FIXME avoid shell invoc, potential quoting problems here
  system("cat $f | grep-dctrl @argv");
}

sub list {
  opendir(DIR, $datadir) or die "can't open dir $datadir: $!";
  while (my $file = readdir(DIR)) {
     if ( (-d "$datadir/$file") && ($file =~ m|^\w+|) ) {
        print "$file\n";
     }
  }
  closedir(DIR);
}



sub parseFile {
   my ($file) = @_;

   # Parse a source file and returns results as a hash

   open(FILE, "$file") || die("Could not open $file : $!\n");

   # Use %tmp hash to store tmp data
   my %tmp;
   my %result;

   while (my $line = <FILE>) {
      if ( $line =~ m|^$| ) {
         # Commit data if empty line
	 if ( $tmp{'Package'} ) {
	    #print "Committing data for $tmp{'Package'}\n";
	    while ( my ($field, $data) = each(%tmp) ) {
	       if ( $field ne "Package" ) {
                  $result{$tmp{'Package'}}{$field} = $data;
	       }
	    }
	    # Reset %tmp
	    %tmp = ();
	 } else {
            warn "W: No Package field found. Not committing data.\n";
	 }
      } elsif ( $line =~ m|^[a-zA-Z]| ) {
         # Gather data
         my ($field, $data) = $line =~ m|([a-zA-z-]+): (.*)$|;
	 if ($data) {
	    $tmp{$field} = $data;
	 }
      }
   }
   close(FILE);

   return \%result;
}




########################################################
### Command parsing
########################################################

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
  dist_compare(@ARGV, 0, 'Sources');
}
elsif ($command eq 'compare-bin-packages') {
  dist_compare(@ARGV, 0, 'Packages');
}
elsif ($command eq 'compare-versions') {
  dist_compare(@ARGV, 1, 'Sources');
}
elsif ($command eq 'compare-bin-versions') {
  dist_compare(@ARGV, 1, 'Packages');
}
elsif ($command eq 'grep-dctrl-packages') {
  grep_file(@ARGV, 'Packages');
}
elsif ($command eq 'grep-dctrl-sources') {
  grep_file(@ARGV, 'Sources');
}
elsif ($command eq 'compare-src-bin-packages') {
  compare_src_bin(@ARGV, 0);
}
elsif ($command eq 'compare-src-bin-versions') {
  compare_src_bin(@ARGV, 1);
}
elsif ($command eq 'list') {
  list;
}
else {
  die "Command unknown. Try $0 -h\n";
}
