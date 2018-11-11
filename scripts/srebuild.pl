#!/usr/bin/perl
#
# Copyright 2014 Johannes Schauer
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

=pod

=head1 NAME

srebuild - sbuild wrapper to make a reproducible build using a .buildinfo file

=head1 SYNOPSIS

.B srebuild package.buildinfo

=head1 DESCRIPTION

B<srebuild> is a thin wrapper around sbuild. Given a C<.buildinfo> file,
it first finds a timestamp of Debian Sid from snapshot.debian.org which
contains the requested packages in their exact versions. It then runs sbuild
with the right architecture as given by the C<.buildinfo> file and the right
base system to upgrade from, as given by the version of the base-files package
version in the C<.buildinfo> file. Using two hooks it will install the right
package versions and verify that the installed packages are in the right
version before the build starts.

=head1 OPTIONS

=over

=item B<--archive>

Default: "debian"

C<.devscripts> variable: C<SREBUILD_ARCHIVE>

=item B<--area>

Default: "main"

C<.devscripts> variable: C<SREBUILD_AREA>

=item B<--dist>, B<--distribution>

Default: "stretch"

C<.devscripts> variable: C<SREBUILD_DIST>

=item B<--suite>

Default: "sid"

C<.devscripts> variable: C<SREBUILD_SUITE>

=item B<--ua>, B<--user-agent>

Default: "LWP::UserAgent/srebuild"

C<.devscripts> variable: C<SREBUILD_USER_AGENT>

=back

=head1 BUGS

B<srebuild> will give up if not all packages can be found in a single
snapshot. It should be possible to retrieve the right packages from multiple
timestamps.

Querying the snapshot.debian.org API for the right timestamp with the correct
versions takes some time. It should be possible to manually supply the right
timestamp on the command line, allowing to skip the step of figuring out the
right timestamp. Conversely, every run should output the timestamp it found so
that it can be used to skip the step for repeated runs.

The right snapshot is expected to be found in Debian sid, main. It should be
possible to find it in stable and testing as well or even mix different suites.
It should be possible to find the right packages in contrib and non free, too.
Additionally, it might be worthwhiel to search debian-archive,
debian-backports, debian-ports, debian-security or debian-volatile for the
right version.

Currently, wheezy will always be used as the base. Instead, the version of the
base-files package should be used to select the optimal release to upgrade
from.

=head1 AUTHORS

Johannes Schauer E<lt>j.schauer@email.deE<gt>

Rewritten by Xavier E<lt>yadd@debian.orgE<gt> for devscripts

=head1 COPYRIGHT

Copyright 2015 Johannes Schauer <j.schauer@email.de>

=head1 SEE ALSO

.BR sbuild (1)

=cut

package Devscripts::Srebuild::Config;

use strict;
use Moo;

extends 'Devscripts::Config';

use constant keys => [
    ['archive',             'SREBUILD_ARCHIVE', undef, 'debian'],
    ['area',                'SREBUILD_AREA',    undef, 'main'],
    ['dist|distribution=s', 'SREBUILD_DIST',    undef, 'stretch'],
    ['suite',               'SREBUILD_SUITE',   undef, 'sid'],
    [
        'ua|user-agent=s', 'SREBUILD_USER_AGENT',
        undef,             'LWP::UserAgent/srebuild'
    ]];

package main;

use strict;
use warnings;

use DateTime::Format::Strptime;
use Dpkg::Control;
use Dpkg::Compression::FileHandle;
use Dpkg::Deps;
use Digest::SHA qw(sha256_hex);
use Compress::Zlib;
use File::Basename;
use File::Temp 'tempfile';

my $config = Devscripts::Srebuild::Config->new->parse;

eval {
    require LWP::Simple;
    require LWP::UserAgent;
    no warnings;
    $LWP::Simple::ua = LWP::UserAgent->new(agent => $config->{ua});
};
if ($@) {
    if ($@ =~ m/Can\'t locate LWP/) {
        die "Unable to run: the libwww-perl package is not installed";
    } else {
        die "Unable to run: Couldn't load LWP::Simple: $@";
    }
}

eval { require JSON; };
if ($@) {
    if ($@ =~ m/Can\'t locate JSON/) {
        die "Unable to run: the libjson-perl package is not installed";
    } else {
        die "Unable to run: Couldn't load JSON: $@";
    }
}

# this subroutine is from debsnap(1)
sub fetch_json_page {
    my ($json_url) = @_;
    my $content = LWP::Simple::get($json_url);
    return unless defined $content;
    my $json      = JSON->new();
    my $json_text = $json->allow_nonref->utf8->relaxed->decode($content);
    return $json_text;
}

sub parse_buildinfo {
    my $buildinfo = shift;

    my $fh = Dpkg::Compression::FileHandle->new(filename => $buildinfo);

    my $cdata = Dpkg::Control->new(type => CTRL_INDEX_SRC);
    if (not $cdata->parse($fh, $buildinfo)) {
        die "cannot parse";
    }
    my $arch = $cdata->{"Build-Architecture"};
    if (not defined($arch)) {
        die "need Build-Architecture field";
    }
    my $checksums = $cdata->{"Checksums-Sha256"};
    if (not defined($checksums)) {
        die "need Checksums-Sha256 field";
    }
    my $environ
      = $cdata->{"Build-Environment"} || $cdata->{"Installed-Build-Depends"};
    if (not defined($environ)) {
        die "need Build-Environment field";
    }
    close $fh;

    # remove newline from start and end
    $checksums =~ s{^\Q$/\E}{};
    $checksums = [map { [split /\s+/] } (split /\s*\n\s*/, $checksums)];

    my @environ = ();
    foreach my $dep (split(/\s*,\s*/m, $environ)) {
        my $pkg = Dpkg::Deps::Simple->new($dep);
        if (not defined($pkg->{package})) {
            die "name undefined";
        }
        if (defined($pkg->{relation})) {
            if ($pkg->{relation} ne "=") {
                die "wrong relation";
            }
            if (not defined($pkg->{version})) {
                die "version undefined";
            }
        } else {
            die "no version";
        }
        push @environ,
          {
            name         => $pkg->{package},
            architecture => ($pkg->{archqual} || $arch),
            version      => $pkg->{version} };
    }

    return $arch, $checksums, @environ;
}

my %reqpkgs    = ();
my @timestamps = ();

my $dtparser = DateTime::Format::Strptime->new(
    pattern  => '%Y%m%dT%H%M%SZ',
    on_error => 'croak',
);

my $buildinfo = shift @ARGV;
if (not defined($buildinfo)) {
    die "need buildinfo filename";
}

my ($arch, $checksums, @environ) = parse_buildinfo $buildinfo;

print STDERR "check original checksums\n";

my $dsc_fname;

foreach my $sum (@{$checksums}) {
    my ($chksum, $size, $fname) = @{$sum};
    my $size2 = (stat($fname))[7];
    if ($size != $size2) {
        print "$size\n";
        print "$size2\n";
        die "size mismatch for $fname\n";
    }
    open my $fh, '<', $fname;
    my $chksum2 = sha256_hex <$fh>;
    if ($chksum ne $chksum2) {
        print "$chksum\n";
        print "$chksum2\n";
        die "checksum mismatch for $fname\n";
    }
    close $fh;
    if ($fname =~ /.dsc/) {
        if (defined($dsc_fname)) {
            die "more than one dsc\n";
        }
        $dsc_fname = $fname;
    }
}

if (not defined($dsc_fname)) {
    die "no dsc found\n";
}

print STDERR "retrieve last seen snapshot timestamps\n";

foreach my $pkg (@environ) {
    $reqpkgs{"$pkg->{name}:$pkg->{architecture}=$pkg->{version}"} = 1;
    my $url
      = "http://snapshot.debian.org/mr/binary/$pkg->{name}/$pkg->{version}/binfiles?fileinfo=1";
    my $json_text = fetch_json_page($url);
    unless ($json_text && @{ $json_text->{result} }) {
        die "Unable to retrieve information for $pkg->{name} from $url.\n";
    }
    my $hash = undef;
    if (scalar @{ $json_text->{result} } == 1) {
        if (@{ $json_text->{result} }[0]->{architecture} ne "all") {
            print STDERR
"expected arch:all, not $json_text->{result}->[0]->{architecture} for $pkg->{name}\n";
        }
        $hash = ${ $json_text->{result} }[0]->{hash};
    } else {
        foreach my $result (@{ $json_text->{result} }) {
            if ($result->{architecture} eq $arch) {
                $hash = $result->{hash};
                last;
            }
        }
    }
    if (not defined($hash)) {
        die "cannot find architecture for $pkg->{name}\n";
    }
    my @first_seen = grep { $_->{archive_name} eq $config->{archive} }
      @{ $json_text->{fileinfo}->{$hash} };
    if (scalar @first_seen != 1) {
        die "more than one package with the same hash\n";
    }
    @first_seen = map { $_->{first_seen} } @first_seen;
    push @timestamps, $dtparser->parse_datetime($first_seen[0]);
}

# @timestamps = sort { DateTime->compare($a, $b) } @timestamps;
@timestamps = sort @timestamps;

my $newest = $timestamps[$#timestamps];
$newest = $newest->strftime("%Y%m%dT%H%M%SZ");

my $snapshot_url
  = "http://snapshot.debian.org/archive/$config->{archive}/$newest/dists/"
  . "$config->{suite}/$config->{area}/binary-$arch/Packages.gz";

print STDERR "download Packages.gz\n";

my $response = LWP::Simple::get($snapshot_url);

my $dest = Compress::Zlib::memGunzip($response)
  or die "Cannot uncompress\n";

print STDERR "process Packages.gz\n";

open my $fh, '<', \$dest;

while (1) {
    my $cdata = Dpkg::Control->new(type => CTRL_INDEX_SRC);
    last if not $cdata->parse($fh, "Packages.gz");
    my $pkgname = $cdata->{"Package"};
    next if not defined($pkgname);
    my $pkgver = $cdata->{"Version"};
    my $pkgarch;
    if ($cdata->{"Architecture"} eq "all") {
        $pkgarch = $arch;
    } else {
        $pkgarch = $cdata->{"Architecture"};
    }
    my $key = "$pkgname:$pkgarch=$pkgver";
    if (exists $reqpkgs{$key}) {
        delete $reqpkgs{$key};
    }
}

if (scalar(keys %reqpkgs) != 0) {
    die "some of the requested packages are not part of this snapshot";
}

print "architecture = $arch\n";
print
  "mirror =  http://snapshot.debian.org/archive/$config->{archive}/$newest/\n";

my $bn_buildinfo = basename $buildinfo;

my $prehook = tempdir(CLEANUP => 1) . "srebuild-hook";
open my $ph, '>', $prehook or die $!;
print $ph, join('', <DATA>);
close $ph;
chmod 0755, $prehook;

my $retval = system "sbuild", "--arch=$arch", "--dist=$config->{dist}",
  "--pre-build-command=cp $prehook $buildinfo %SBUILD_CHROOT_DIR/tmp",
"--chroot-setup-command=/tmp/srebuild-hook chroot-setup /tmp/$bn_buildinfo $newest",
"--starting-build-commands=/tmp/srebuild-hook starting-build /tmp/$bn_buildinfo",
  $dsc_fname;
$retval >>= 8;
if ($retval != 0) {
    die "failed";
}

foreach my $sum (@{$checksums}) {
    my ($chksum, $size, $fname) = @{$sum};
    my $size2 = (stat($fname))[7];
    if ($size != $size2) {
        print "$size\n";
        print "$size2\n";
        die "size mismatch for $fname\n";
    }
    open my $fh, '<', $fname;
    my $chksum2 = sha256_hex <$fh>;
    if ($chksum ne $chksum2) {
        print "$chksum\n";
        print "$chksum2\n";
        die "checksum mismatch for $fname\n";
    }
    close $fh;
}
__DATA__
#!/usr/bin/perl
#
# Copyright 2014 Johannes Schauer
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

use strict;
use warnings;

use Dpkg::Control;
use Dpkg::Compression::FileHandle;
use Dpkg::Deps;

sub none(&@) {
    my $code = shift;
    foreach (@_) {
        return 0 if $code->();
    }
    return 1;
}

sub system_fatal {
    my @args = @_;
    print "srebuild: executing: @args\n";
    my $retval = system @args;
    $retval >>= 8;
    if ($retval != 0) {
        die "failed: @args";
    }
}

sub parse_buildinfo {
    my $buildinfo = shift;

    my $fh = Dpkg::Compression::FileHandle->new(filename => $buildinfo);

    my $cdata = Dpkg::Control->new(type => CTRL_INDEX_SRC);
    if (not $cdata->parse($fh, $buildinfo)) {
        die "cannot parse";
    }
    my $arch = $cdata->{"Build-Architecture"};
    if (not defined($arch)) {
        die "need Build-Architecture field";
    }
    my $environ = $cdata->{"Build-Environment"};
    if (not defined($environ)) {
        die "need Build-Environment field";
    }
    close $fh;

    my @environ = ();
    foreach my $dep (split(/\s*,\s*/m, $environ)) {
        my $pkg = Dpkg::Deps::Simple->new($dep);
        if (not defined($pkg->{package})) {
            die "name undefined";
        }
        if (defined($pkg->{relation})) {
            if ($pkg->{relation} ne "=") {
                die "wrong relation";
            }
            if (not defined($pkg->{version})) {
                die "version undefined";
            }
        } else {
            die "no version";
        }
        push @environ,
          {
            name         => $pkg->{package},
            architecture => ($pkg->{archqual} || $arch),
            version      => $pkg->{version} };
    }

    return $arch, @environ;
}

sub chroot_setup {
    my $buildinfo  = shift;
    my @timestamps = @_;

    my ($arch, @environ) = parse_buildinfo $buildinfo;

    @environ = map { "$_->{name}:$_->{architecture}=$_->{version}" } @environ;

    my $fh;
    open $fh, '>', '/etc/apt/apt.conf.d/80no-check-valid-until';
    print $fh 'Acquire::Check-Valid-Until "false";';
    close $fh;

    open $fh, '>', '/etc/apt/apt.conf.d/99no-install-recommends';
    print $fh 'APT::Install-Recommends "0";';
    close $fh;

    open $fh, '>', '/etc/apt/sources.list';
    foreach my $timestamp (@timestamps) {
        print $fh
"deb http://snapshot.debian.org/archive/debian/$timestamp/ sid main\n";
    }
    close $fh;

    system_fatal "apt-get", "update";

    system_fatal "apt-get", "--yes", "--force-yes", "install", @environ;
}

sub starting_build {
    my $buildinfo = shift;

    my ($arch, @environ) = parse_buildinfo $buildinfo;

    @environ = map { "$_->{name}:$_->{architecture}=$_->{version}" } @environ;

    open my $fh, '-|',
'dpkg-query --show --showformat \'${Package}:${Architecture}=${Version}\n\'';
    my @installed = ();
    while (my $line = <$fh>) {
        chomp $line;
        # make arch:all packages build-arch packages
        $line =~ s/:all=/:$arch=/;
        push @installed, $line;
    }

    foreach my $dep (@environ) {
        if (none { $_ eq $dep } @installed) {
            die "require $dep to be installed but it is not";
        }
    }
    print "srebuild: all packages are in the correct version\n";
}

my $mode      = shift @ARGV;
my $buildinfo = shift @ARGV;
if (not defined($buildinfo)) {
    die "need buildinfo filename";
}

if ($mode eq "chroot-setup") {
    my @timestamps = @ARGV;
    if (scalar @timestamps == 0) {
        die "need timestamp";
    }

    chroot_setup $buildinfo, @timestamps;
} elsif ($mode eq "starting-build") {
    starting_build $buildinfo;
} else {
    die "invalid mode: $mode";
}
