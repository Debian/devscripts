#!/usr/bin/perl -w
# vim:sw=4:sta:

#   dget - Download Debian source and binary packages
#   Copyright (C) 2005 Christoph Berg <myon@debian.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

# 2005-10-04 cb: initial release
# 2005-12-11 cb: -x option, update documentation
# 2005-12-31 cb: -b, -q options, use getopt

use strict;
use IO::File;
use Digest::MD5;
use Getopt::Long;

# global variables

my $found_dsc;
# use curl if installed, wget otherwise
my $wget = -e "/usr/bin/curl" ? "curl" : "wget";
my $opt;
my $backup_dir = "backup";

# functions

sub usage {
    die "usage: $0 [-bqx] package-url.dsc/changes package package=version ...\n";
}

sub wget {
    my ($file, $url) = @_;
    my @cmd = ($wget);
    push @cmd, ($wget eq "wget" ? "-q" : "-s") if $opt->{quiet};
    push @cmd, ($wget eq "wget" ? "-O" : "-o");
    system @cmd, $file, $url;
    return $? >> 8;
}

sub backup_or_unlink {
    my $file = shift;
    return unless -e $file;
    if ($opt->{backup}) {
	unless (-d $backup_dir) {
	    mkdir $backup_dir or die "mkdir $backup_dir: $!";
	}
	rename $file, "$backup_dir/$file" or die "rename $file $backup_dir/$file: $!";
    } else {
	unlink $file or die "unlink $file: $!";
    }
}

# some files both are in .dsc and .changes, download only once
my %seen;
sub get_file {
    my ($dir, $file, $md5sum) = @_;
    return if $seen{$file};

    if ($md5sum eq "unlink") {
	backup_or_unlink($file);
    }

    if (-e $file) {
	my $md5 = Digest::MD5->new;
	my $fh5 = new IO::File($file) or die "$file: $!";
	my $md5sum_new = Digest::MD5->new->addfile($fh5)->hexdigest();
	close $fh5;
	if (not $md5sum or ($md5sum_new eq $md5sum)) {
	    print "$0: using existing $file\n";
	} else {
	    print "$0: md5sum for $file does not match\n";
	    backup_or_unlink($file);
	}
    }

    unless (-e $file) {
	print "$0: retrieving $dir/$file\n";
	if (wget($file, "$dir/$file")) {
	    warn "$0: $wget $file $dir/$file failed\n";
	    unlink $file;
	    return 0;
	}
    }

    if ($file =~ /\.(?:changes|dsc)$/) {
	parse_file($dir, $file);
    }
    if ($file =~ /\.dsc$/) {
	$found_dsc = $file;
    }

    $seen{$file} = 1;
    return 1;
}

sub parse_file {
    my ($dir, $file) = @_;

    my $fh = new IO::File($file);
    open $fh, $file or die "$file: $!";
    while (<$fh>) {
	if (/^ ([0-9a-f]{32}) (?:\S+ )*(\S+)$/) {
	    get_file($dir, $2, $1) or return;;
	}
    }
    close $fh;
}

# we reinvent "apt-get -d install" here, without requiring root
# (and we do not download dependencies)
sub apt_get {
    my ($package, $version) = @_;

    my $qpackage = quotemeta($package);
    my $qversion = quotemeta($version) if $version;
    my @hosts;

    my $apt = new IO::File("LC_ALL=C apt-cache policy $package |") or die "$!";
    OUTER: while (<$apt>) {
	if (not $version and /^  Candidate: (.+)/) {
	    $version = $1;
	    $qversion = quotemeta($version);
	}
	if ($qversion and /^ [ *]{3} ($qversion) 0/) {
	    while (<$apt>) {
		last OUTER unless /^        (?:\d+) (\S+)/;
		push @hosts, $1;
	    }
	}
    }
    close $apt;
    unless ($version) {
	die "$0: $package has no installation candidate\n";
    }
    unless (@hosts) {
	die "$0: no hostnames in apt-cache policy $package for $version found\n";
    }

    $qversion =~ s/^([^:]+:)/($1)?/;
    $qversion =~ s/-([^.-]+)$/-$1(\.0\.\\d+)?\$/; # BinNMU: -x -> -x.0.1
    $qversion =~ s/-([^.-]+\.[^.-]+)$/-$1(\.\\d+)?\$/; # -x.y -> -x.y.1

    $apt = new IO::File("LC_ALL=C apt-cache show $package |") or die "$!";
    my ($v, $p, $filename, $md5sum);
    while (<$apt>) {
	if (/^Package: $qpackage$/) {
	    $p = $package;
	}
	if (/^Version: $qversion$/) {
	    $v = $version;
	}
	if (/^Filename: (.*)/) {
	    $filename = $1;
	}
	if (/^MD5sum: (.*)/) {
	    $md5sum = $1;
	}
	if (/^Description:/) { # we assume this is the last field
	    if ($p and $v and $filename) {
		last;
	    }
	    undef $p;
	    undef $v;
	    undef $filename;
	    undef $md5sum;
	}
    }
    close $apt;

    unless ($filename) {
	die "$0: no filename for $package ($version) found\n";
    }

    # find deb lines matching the hosts in the policy output
    $apt = new IO::File("/etc/apt/sources.list") or die "/etc/apt/sources.list: $!";
    my @repositories;
    my $host_re = '(?:' . (join '|', map { quotemeta; } @hosts) . ')';
    while (<$apt>) {
	if (/^\s*deb\s*($host_re\S+)/) {
	    push @repositories, $1;
	}
    }
    close $apt;
    unless (@repositories) {
	die "no repository found in /etc/apt/sources.list";
    }

    # try each repository in turn
    foreach my $repository (@repositories) {
	my ($dir, $file) = ($repository, $filename);
	if ($filename =~ /(.*)\/([^\/]*)$/) {
	    ($dir, $file) = ("$repository/$1", $2);
	}

	get_file($dir, $file, $md5sum) and exit 0;
    }
    exit 1;
}

# main program

Getopt::Long::config('bundling');
unless (GetOptions(
    '-h'	=>  \$opt->{'help'},
    '--help'	=>  \$opt->{'help'},
    '-b'	=>  \$opt->{'backup'},
    '--backup'	=>  \$opt->{'backup'},
    '-q'	=>  \$opt->{'quiet'},
    '--quiet'	=>  \$opt->{'quiet'},
    '-x'	=>  \$opt->{'unpack_source'},
    '--extract'	=>  \$opt->{'unpack_source'},
)) {
    usage();
}

usage() if !@ARGV or $opt->{help};

for my $arg (@ARGV) {
    $found_dsc = "";

    if ($arg =~ /^((?:copy|file|ftp|http|rsh|rsync|ssh|www).*)\/([^\/]+\.\w+)$/) {
	get_file($1, $2, "unlink");
	if ($found_dsc and $opt->{unpack_source}) {
	    system 'dpkg-source', '-x', $found_dsc;
	}

    } elsif ($arg =~ /^[a-z0-9.+-]{2,}$/) {
	apt_get($arg);

    } elsif ($arg =~ /^([a-z0-9.+-]{2,})=([a-zA-Z0-9.:+-]+)$/) {
	apt_get($1, $2);

    } else {
	usage();
    }
}

=pod

=head1 NAME

dget -- Download Debian source and binary packages

=head1 SYNOPSIS

=over

=item B<dget> [B<-bqx>] I<URL>

=item B<dget> [B<-bq>] I<package>

=item B<dget> [B<-bq>] I<package>=I<version>

=back

=head1 DESCRIPTION

B<dget> downloads Debian packages. In the first form, B<dget> acts as a source
package-aware form of wget; it fetches the given URL and recursively any files
referenced, if the URL points to a .dsc or .changes file. When the B<-x> option
is given, the downloaded source is unpacked by B<dpkg-source>.

In the second and third form, B<dget> downloads a binary package from the
Debian mirror configured in /etc/apt/sources.list. Unlike B<apt-get install
-d>, it does not require root privileges, writes to the current directory, and
does not download dependencies.

Before downloading referenced files in .dsc and .changes files, and before
downloading binary packages, if any of the files already exist, md5sums are
compared to avoid wasting bandwidth. Download backends used are B<curl> and
B<wget>, looked for in that order.

B<dget> was written to make it easier to retrieve source packages from the web
for sponsor uploads. For checking the package with B<debdiff>, the last binary
version is available via B<dget> I<package>, the last source version via
B<apt-get source> I<package>.

=head1 OPTIONS

B<-b> move files that would be overwritten to B<./backup>.

B<-q> suppress wget/curl output.

B<-x> run B<dpkg-source -x> on the downloaded source package.

=head1 BUGS

B<dget> I<package> should be implemented in B<apt-get install -d>.

=head1 AUTHOR

=over

=item Christoph Berg <myon@debian.org>

=back

=head1 SEE ALSO

apt-get(1), debdiff(1), dpkg-source(1), curl(1), wget(1).

