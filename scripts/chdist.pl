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
# along with this program. If not, see <https://www.gnu.org/licenses/>.

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

Choose data directory (default: F<$HOME/.chdist/>).

=item B<-a>, B<--arch> I<ARCH>

Choose architecture (default: `B<dpkg --print-architecture>`).

=item B<--version>

Display version information.

=back

=head1 COMMANDS

=over 4

=item B<create> I<DIST> [I<URL> I<RELEASE> I<SECTIONS>]

Prepare a new tree named I<DIST>

=item B<apt> I<DIST> <B<update>|B<source>|B<show>|B<showsrc>|...>

Run B<apt> inside I<DIST>

=item B<apt-get> I<DIST> <B<update>|B<source>|...>

Run B<apt-get> inside I<DIST>

=item B<apt-cache> I<DIST> <B<show>|B<showsrc>|...>

Run B<apt-cache> inside I<DIST>

=item B<apt-file> I<DIST> <B<update>|B<search>|...>

Run B<apt-file> inside I<DIST>

=item B<apt-rdepends> I<DIST> [...]

Run B<apt-rdepends> inside I<DIST>

=item B<src2bin> I<DIST SRCPKG>

List binary packages for I<SRCPKG> in I<DIST>

=item B<bin2src> I<DIST BINPKG>

List source package for I<BINPKG> in I<DIST>

=item B<compare-packages> I<DIST1 DIST2> [I<DIST3>, ...]

=item B<compare-bin-packages> I<DIST1 DIST2> [I<DIST3>, ...]

List versions of packages in several I<DIST>ributions

=item B<compare-versions> I<DIST1 DIST2>

=item B<compare-bin-versions> I<DIST1 DIST2>

Same as B<compare-packages>/B<compare-bin-packages>, but also runs
B<dpkg --compare-versions> and display where the package is newer.

=item B<compare-src-bin-packages> I<DIST>

Compare sources and binaries for I<DIST>

=item B<compare-src-bin-versions> I<DIST>

Same as B<compare-src-bin-packages>, but also run B<dpkg --compare-versions>
and display where the package is newer

=item B<grep-dctrl-packages> I<DIST> [...]

Run B<grep-dctrl> on F<*_Packages> inside I<DIST>

=item B<grep-dctrl-sources> I<DIST> [...]

Run B<grep-dctrl> on F<*_Sources> inside I<DIST>

=item B<list>

List available I<DIST>s

=back

=head1 COPYRIGHT

This program is copyright 2007 by Lucas Nussbaum and Luk Claes. This
program comes with ABSOLUTELY NO WARRANTY.

It is licensed under the terms of the GPL, either version 2 of the
License, or (at your option) any later version.

=cut

use strict;
use warnings;
no if $] >= 5.018, 'warnings', 'experimental::smartmatch';
use feature 'switch';
use File::Copy qw(cp);
use File::Path qw(make_path);
use File::Basename;
use Getopt::Long qw(:config gnu_compat bundling require_order);
use Cwd qw(abs_path cwd);
use Dpkg::Version;
use Pod::Usage;

# Redefine Pod::Text's cmd_i so pod2usage converts I<...> to <...> instead of
# *...*
{
    package Pod::Text;
    no warnings qw(redefine);

    sub cmd_i { '<'. $_[2] . '>' }
}

my $progname = basename($0);

sub usage {
    pod2usage(-verbose => 99,
	      -exitval => $_[0],
	      -sections => 'SYNOPSIS|OPTIONS|ARGUMENTS|COMMANDS');
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
  "h|help"       => \$help,
  "d|data-dir=s" => \$datadir,
  "a|arch=s"     => \$arch,
  "version"    => \$version,
) or usage(1);

# Fix-up relative paths
$datadir = cwd() . "/$datadir" if $datadir !~ m!^/!;
$datadir = abs_path($datadir);

if ($help) {
    usage(0);
}

if ($version) {
    print $versioninfo;
    exit 0;
}


########################################################
### Functions
########################################################

sub fatal
{
    my ($msg) = @_;
    $msg =~ s/\n?$/\n/;
    print STDERR "$progname: $msg";
    exit 1;
}

sub uniq (@) {
    my %hash;
    map { $hash{$_}++ == 0 ? $_ : () } @_;
}

sub dist_check {
    # Check that dist exists in $datadir
    my ($dist) = @_;
    if ($dist) {
	my $dir = "$datadir/$dist";
	return 0 if (-d $dir);
	fatal("Could not find $dist in $datadir. Run `$progname create $dist` first.");
    }
    else {
	fatal('No dist provided.');
    }
}

sub type_check {
    my ($type) = @_;
    if (($type ne 'Sources') && ($type ne 'Packages')) {
	fatal("Unknown type $type.");
    }
}

sub aptopts
{
    # Build apt options
    my ($dist) = @_;
    my @opts = ();
    if ($arch) {
	print "W: Forcing arch $arch for this command only.\n";
	push(@opts, '-o', "Apt::Architecture=$arch");
	push(@opts, '-o', "Apt::Architectures=$arch");
    }
    return @opts;
}

sub aptconfig
{
    # Build APT_CONFIG override
    my ($dist) = @_;
    my $aptconf = "$datadir/$dist/etc/apt/apt.conf";
    if (! -r $aptconf) {
	fatal("Unable to read $aptconf");
    }
    $ENV{'APT_CONFIG'} = $aptconf;
}

###

sub aptcmd
{
    my ($cmd, $dist, @args) = @_;
    dist_check($dist);
    unshift(@args, aptopts($dist));
    aptconfig($dist);
    exec($cmd, @args);
}

sub apt_file
{
    my ($dist, @args) = @_;
    dist_check($dist);
    aptconfig($dist);
    my @query = ('dpkg-query', '-W', '-f');
    open(my $fd, '-|', @query, '${Version}', 'apt-file')
	or fatal('Unable to run dpkg-query.');
    my $aptfile_version = <$fd>;
    close($fd);
    if (version_compare('3.0~', $aptfile_version) < 0) {
	open($fd, '-|', @query, '${Conffiles}\n', 'apt-file')
	    or fatal('Unable to run dpkg-query.');
	my @aptfile_confs = map { (split)[0] }
			    grep { /apt\.conf\.d/ } <$fd>;
	close($fd);
	# New-style apt-file
	for my $conffile (@aptfile_confs) {
	    if (! -f "$datadir/$dist/$conffile") {
		cp($conffile, "$datadir/$dist/$conffile");
	    }
	}
    }
    else {
	my $cache_directory = $datadir . '/' . $dist . "/var/cache/apt/apt-file";
	unshift(@args,
	    '--cache', $cache_directory
	);
    }
    exec('apt-file', @args);
}

sub bin2src
{
    my ($dist, $pkg) = @_;
    dist_check($dist);
    if (!defined($pkg)) {
	fatal("No package name provided. Exiting.");
    }
    my @args = (aptopts($dist), 'show', $pkg);
    aptconfig($dist);
    my $src = $pkg;
    my $pid = open(CACHE, '-|', 'apt-cache', @args);
    if (!defined($pid)) {
	fatal("Couldn't run apt-cache: $!");
    }
    if ($pid) {
	while (<CACHE>) {
	    if (m/^Source: (.*)/) {
		$src = $1;
		# Slurp remaining output to avoid SIGPIPE
		local $/ = undef;
		my $junk = <CACHE>;
		last;
	    }
	}
	close CACHE || fatal("bad apt-cache $!: $?");
	print "$src\n";
    }
}

sub src2bin {
    my ($dist, $pkg) = @_;
    dist_check($dist);
    if (!defined($pkg)) {
	fatal("no package name provided. Exiting.");
    }
    my @args = (aptopts($dist), 'showsrc', $pkg);
    my $pid = open(CACHE, '-|', 'apt-cache', @args);
    if (!defined($pid)) {
	fatal("Couldn't run apt-cache: $!");
    }
    if ($pid) {
	while (<CACHE>) {
	    if (m/^Binary: (.*)/) {
		print join("\n", split(/, /, $1)) . "\n";
		# Slurp remaining output to avoid SIGPIPE
		local $/ = undef;
		my $junk = <CACHE>;
		last;
	    }
	}
	close CACHE || fatal("bad apt-cache $!: $?");
    }
}

sub dist_create
{
    my ($dist, $method, $version, @sections) = @_;
    if (!defined($dist)) {
	fatal("you must provide a dist name.");
    }
    my $dir = "$datadir/$dist";
    if (-d $dir) {
	fatal("$dir already exists, exiting.");
    }
    make_path($datadir);
    foreach my $d (('/etc/apt', '/etc/apt/apt.conf.d', '/etc/apt/preferences.d',
		    '/etc/apt/trusted.gpg.d', '/etc/apt/sources.list.d',
		    '/var/lib/apt/lists/partial',
		    '/var/cache/apt/archives/partial', '/var/lib/dpkg')) {
	make_path("$dir/$d");
    }

    # Create sources.list
    open(FH, '>', "$dir/etc/apt/sources.list");
    if ($version) {
	# Use provided method, version and sections
	my $sections_str = join(' ', @sections);
	print FH <<EOF;
deb $method $version $sections_str
deb-src $method $version $sections_str
EOF
    }
    else {
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
    open(FH, '>', "$dir/var/lib/dpkg/status");
    close FH; #empty file
    # Create apt.conf
    $arch ||= `dpkg --print-architecture`;
    chomp $arch;
    open(FH, ">$dir/etc/apt/apt.conf");
    print FH <<EOF;
Apt {
   Architecture "$arch";
   Architectures "$arch";
};

Dir "$dir";
Dir::State::status "$dir/var/lib/dpkg/status";
EOF
    close FH;
    foreach my $keyring (qw(debian-archive-keyring.gpg
			    debian-archive-removed-keys.gpg
			    ubuntu-archive-keyring.gpg
			    ubuntu-archive-removed-keys.gpg)) {
	my $src = "/usr/share/keyrings/$keyring";
	if (-f $src) {
	    symlink $src, "$dir/etc/apt/trusted.gpg.d/$keyring";
	}
    }
    print "Now edit $dir/etc/apt/sources.list\n" unless $version;
    print "Run chdist apt $dist update\n";
    print "And enjoy.\n";
}



sub get_distfiles {
  # Retrieve files to be read
  # Takes a dist and a type
  my ($dist, $type) = @_;

  my @files;

  foreach my $file ( glob($datadir . '/' . $dist . "/var/lib/apt/lists/*_$type") ) {
     if ( -f $file ) {
        push @files, $file;
     }
  }

  return \@files;
}


sub dist_compare(\@$$) {
  # Takes a list of dists, a type of comparison and a do_compare flag
  my ($dists, $do_compare, $type) = @_;
  type_check($type);

  # Get the list of dists from the reference
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
        $vers =~ s|\+|\\\+| if defined $vers;
     }

     # Do compare
     if ($do_compare) {
        if (!@dists) {
           fatal('Can only compare versions if there are two distros.');
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
		if (defined $packages{Sources_Bin}{$binary}) {
		    my $alt_ver = $packages{Sources_Bin}{$binary}{Version};
		    # Skip this entry if it's an older version than we already
		    # have
		    if (version_compare($version, $alt_ver) < 0) {
			next;
		    }
		}
		$packages{Sources_Bin}{$binary}{Version} = $version;
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
	my $details = '';

	foreach my $type (@comp_types) {
	    if ( $packages{$type}{$package} ) {
		$line .= "$packages{$type}{$package}{'Version'} ";
	    } else {
		$line .= "UNAVAIL ";
		$status = "not_in_$type";
	    }
	}

	my @versions = map { $packages{$_}{$package}{'Version'} } @comp_types;

	# Do compare
	if ($do_compare) {
	    if (!@comp_types) {
		fatal('Can only compare versions if there are two types.');
	    }
	    if (!$status) {
		my $cmp = version_compare($versions[0], $versions[1]);
		if (!$cmp) {
		    $status = "same_version";
		} elsif ($cmp < 0) {
		    $status = "newer_in_$comp_types[1]";
		    if ( $versions[1] =~ m|^\Q$versions[0]\E| ) {
			$details = " local_changes_in_$comp_types[1]";
		    }
		} else {
		    $status = "newer_in_$comp_types[0]";
		    if ( $versions[0] =~ m|^\Q$versions[1]\E| ) {
			$details = " local_changes_in_$comp_types[0]";
		    }
		}
	    }
	    $line .= " $status $details";
	}

	print "$line\n";
    }
}

sub grep_file(\@$)
{
    my ($argv, $file) = @_;
    my $dist = shift @{$argv};
    dist_check($dist);
    my @f = glob($datadir . '/' . $dist . "/var/lib/apt/lists/*_$file");
    if (@f) {
	exec('grep-dctrl', @{$argv}, @f);
    }
    else {
	fatal("Couldn't find a $file for $dist.");
    }
}

sub list {
  opendir(DIR, $datadir) or fatal("can't open dir $datadir: $!");
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

   open(FILE, '<', $file) || fatal("Could not open $file : $!");

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
         my ($field, $data) = $line =~ m|([a-zA-Z-]+): (.*)$|;
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
given ($command) {
    when ('create') {
	dist_create(@ARGV);
    }
    when ('apt') {
	aptcmd('apt', @ARGV);
    }
    when ('apt-get') {
	aptcmd('apt-get', @ARGV);
    }
    when ('apt-cache') {
	aptcmd('apt-cache', @ARGV);
    }
    when ('apt-file') {
	apt_file(@ARGV);
    }
    when ('apt-rdepends') {
	aptcmd('apt-rdepends', @ARGV);
    }
    when ('bin2src') {
	bin2src(@ARGV);
    }
    when ('src2bin') {
	src2bin(@ARGV);
    }
    when ('compare-packages') {
	dist_compare(@ARGV, 0, 'Sources');
    }
    when ('compare-bin-packages') {
	dist_compare(@ARGV, 0, 'Packages');
    }
    when ('compare-versions') {
	dist_compare(@ARGV, 1, 'Sources');
    }
    when ('compare-bin-versions') {
	dist_compare(@ARGV, 1, 'Packages');
    }
    when ('grep-dctrl-packages') {
	grep_file(@ARGV, 'Packages');
    }
    when ('grep-dctrl-sources') {
	grep_file(@ARGV, 'Sources');
    }
    when ('compare-src-bin-packages') {
	compare_src_bin(@ARGV, 0);
    }
    when ('compare-src-bin-versions') {
	compare_src_bin(@ARGV, 1);
    }
    when ('list') {
	list;
    }
    default {
	usage(1);
    }
}
