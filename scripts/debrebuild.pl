#!/usr/bin/perl
#
# Copyright © 2014-2020 Johannes Schauer Marin Rodrigues <josch@debian.org>
# Copyright © 2020      Niels Thykier <niels@thykier.net>
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
use autodie;

use Getopt::Long qw(:config gnu_getopt no_bundling no_auto_abbrev);

use Dpkg::Control;
use Dpkg::Index;
use Dpkg::Deps;
use Dpkg::Source::Package;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::HomeDir;
use JSON::PP;
use Time::Piece;
use File::Basename;
use List::Util qw(any none);

my $progname;

BEGIN {
    $progname = basename($0);
    eval { require String::ShellQuote; };
    if ($@) {
        if ($@ =~ /^Can\'t locate String\/ShellQuote\.pm/) {
            die
"$progname: you must have the libstring-shellquote-perl package installed\n"
              . "to use this script";
        } else {
            die
"$progname: problem loading the String::ShellQuote module:\n  $@\n"
              . "Have you installed the libstring-shellquote-perl package?";
        }
    }

    eval {
        require LWP::Simple;
        require LWP::UserAgent;
        require URI::Escape;    # libwww-perl depends on liburi-perl
        no warnings;
        $LWP::Simple::ua
          = LWP::UserAgent->new(agent => 'LWP::UserAgent/debrebuild');
        $LWP::Simple::ua->env_proxy();
    };
    if ($@) {
        if ($@ =~ m/Can\'t locate LWP/) {
            die "$progname: you must have the libwww-perl package installed\n"
              . "to use this script";
        } else {
            die "$progname: problem loading the LWP and URI modules:\n  $@\n"
              . "Have you installed the libwww-perl package?";
        }
    }

}

my $respect_build_path = 1;
my $use_tor            = 0;
my $outdir             = './';
my $builder            = 'none';
my $timestamp          = '';

my %OPTIONS = (
    'help|h'              => sub { usage(0); },
    'use-tor-proxy!'      => \$use_tor,
    'respect-build-path!' => \$respect_build_path,
    'buildresult=s'       => \$outdir,
    'builder=s'           => \$builder,
    'timestamp|t=s'       => \$timestamp,
);

sub usage {
    my ($exit_code) = @_;
    $exit_code //= 0;
    print <<EOF;
Usage: $progname [options] <buildinfo>
       $progname <--help|-h>

Given a buildinfo file from a Debian package, generate instructions for
attempting to reproduce the binary packages built from the associated source
and build information.

Options:
 --help, -h                 Show this help and exit
 --[no-]use-tor-proxy       Whether to fetch resources via tor (socks://127.0.0.1:9050)
                            Assumes "apt-transport-tor" is installed both in host + chroot
 --[no-]respect-build-path  Whether to setup the build to use the Build-Path from the
                            provided .buildinfo file.
 --buildresults             Directory for the build artifacts (default: ./)
 --builder=BUILDER          Which building software should be used. Possible values are
                            none, sbuild, mmdebstrap, dpkg and sbuild+unshare. The default
                            is none. See section BUILDER for details.
 --timestamp, -t            The required unstable main timestamps from snapshot.d.o if you
                            already know them, separated by commas, or one of the values
                            "first_seen" or "metasnap". See section TIMESTAMPS.

Note: $progname can parse buildinfo files with and without a GPG signature.  However,
the signature (if present) is discarded as debrebuild does not support verifying
it.  If the authenticity or integrity of the buildinfo files are important to
you, checking these need to be done before invoking $progname, for example by using
dscverify.

EXAMPLES

    \$ $progname --buildresults=./artifacts --builder=mmdebstrap hello_2.10-2_amd64.buildinfo

BUILDERS

debrebuild can use different backends to perform the actual package rebuild.
The desired backend is chosen using the --builder option. The default is
"none".

    none            Dry-run mode. No build is performed.
    sbuild          Use sbuild to build the package. This requires sbuild to be
                    setup with schroot chroots of Debian stable distributions.
    mmdebstrap      Use mmdebstrap to build the package. This requires no
                    setup and no superuser privileges.
    dpkg            Directly run apt-get and dpkg-buildpackage on the current
                    system without chroot. This requires root privileges.
    sbuild+unshare  Use sbuild with the unshare backend. This will create the
                    chroot and perform the build without superuser privileges
                    and without any setup.

TIMESTAMPS

The --timestamp option allows one to skip the step of figuring out the correct
set of required timestamps by listing them separated by commas in the same
format used in the snapshot.d.o URL. The default is to use the "first_seen"
attribute from the snapshot.d.o API and download multiple Packages files until
all required timestamps are found. To explicitly select this mode, use
--timestamp=first_seen. Lastly, the metasnap.d.n service can be used to figure
out the right set of timestamps. This mode can be selected by using
--timestamp=metasnap. In contrast to the "first_seen" mode, the metasnap.d.n
service will always return a minimal set of timestamps if the package versions
were at some point part of Debian unstable main.

UNSHARE

Before kernel 5.10.1 or before Debian 11 (Bullseye), unprivileged user
namespaces were disabled in Debian for security reasons. Refer to Debian bug
#898446 for details. To enable user namespaces, run:

    \$ sudo sysctl -w kernel.unprivileged_userns_clone=1

The sbuild+unshare builder requires and the mmdebstrap builder benefits from
having unprivileged user namespaces activated. On Ubuntu they are enabled by
default.

LIMITATIONS

Currently, the code assumes that all packages were at some point part of Debian
unstable main. This fails for packages from Debian ports, packages from
experimental as well as for locally built packages or packages from third
party repositories. Enabling support for Debian ports and experimental is
conceptually possible and only needs somebody implementing it.

EOF

    exit($exit_code);
}

GetOptions(%OPTIONS);

my $buildinfo = shift @ARGV;
if (not defined($buildinfo)) {
    print STDERR "ERROR: Missing mandatory buildinfo filename\n";
    print STDERR "\n";
    usage(1);
}
if ($buildinfo eq '--help' or $buildinfo eq '-h') {
    usage(0);
}

if ($buildinfo =~ m/^-/) {
    print STDERR "ERROR: Unsupported option $buildinfo\n";
    print STDERR "\n";
    usage(1);
}

if (@ARGV) {
    print STDERR "ERROR: This program requires exactly argument!\n";
    print STDERR "\n";
    usage(1);
}

my $base_mirror = "http://snapshot.debian.org/archive/debian";
if ($use_tor) {
    $base_mirror = "tor+http://snapshot.debian.org/archive/debian";
    eval {
        $LWP::Simple::ua->proxy([qw(http https)] => 'socks://127.0.0.1:9050');
    };
    if ($@) {
        if ($@ =~ m/Can\'t locate LWP/) {
            die
"Unable to use tor: the liblwp-protocol-socks-perl package is not installed\n";
        } else {
            die "Unable to use tor: Couldn't load socks proxy support: $@\n";
        }
    }
}

# buildinfo support in libdpkg-perl (>= 1.18.11)
my $cdata = Dpkg::Control->new(type => CTRL_FILE_BUILDINFO, allow_pgp => 1);

if (not $cdata->load($buildinfo)) {
    die "cannot load $buildinfo\n";
}

if ($cdata->get_option('is_pgp_signed')) {
    print
"$buildinfo contained a GPG signature; it has NOT been validated (debrebuild does not support this)!\n";
} else {
    print "$buildinfo was unsigned\n";
}

my @architectures = split /\s+/, $cdata->{"Architecture"};
my $build_source  = (scalar(grep /^source$/, @architectures)) == 1;
my $build_archall = (scalar(grep /^all$/, @architectures)) == 1;
@architectures = grep { !/^source$/ && !/^all$/ } @architectures;
if (scalar @architectures > 1) {
    die "more than one architecture in Architecture field\n";
}
my $build_archany = (scalar @architectures) == 1;

my $build_arch = $cdata->{"Build-Architecture"};
if (not defined($build_arch)) {
    die "need Build-Architecture field\n";
}
my $host_arch = $cdata->{"Host-Architecture"};
if (not defined($host_arch)) {
    $host_arch = $build_arch;
}

my $srcpkgname = $cdata->{Source};
my $srcpkgver  = $cdata->{Version};
my $srcpkgbinver
  = $cdata->{Version};    # this version will include the binmu suffix
if ($srcpkgname =~ / /) {
    # In some cases such as binNMUs, the source field contains a version in
    # the form:
    #     mscgen (0.20)
    ($srcpkgname, $srcpkgver) = split / /, $srcpkgname, 2;
    # Add a simple control check to avoid the worst surprises and stop obvious
    # cases of garbage-in-garbage-out.
    die("Unexpected source package name: ${srcpkgname}\n")
      if $srcpkgname =~ m{[ \t_/\(\)<>!\n%&\$\#\@]};
    # remove the surrounding parenthesis from the version
    $srcpkgver =~ s/^\((.*)\)$/$1/;
}

my $new_buildinfo;
{
    my $arch;
    if ($build_archany) {
        $arch = $host_arch;
    } elsif ($build_archall) {
        $arch = 'all';
    } else {
        die "nothing to build\n";
    }
    $new_buildinfo = "$outdir/${srcpkgname}_${srcpkgbinver}_$arch.buildinfo";
}
if (-e $new_buildinfo) {
    my ($dev1, $ino1) = (lstat $buildinfo)[0, 1]
      or die "cannot lstat $buildinfo: $!\n";
    my ($dev2, $ino2) = (lstat $new_buildinfo)[0, 1]
      or die "cannot lstat $new_buildinfo: $!\n";
    if ($dev1 == $dev2 && $ino1 == $ino2) {
        die "refusing to overwrite the input buildinfo file\n";
    }
}

my $inst_build_deps = $cdata->{"Installed-Build-Depends"};
if (not defined($inst_build_deps)) {
    die "need Installed-Build-Depends field\n";
}
my $custom_build_path = $respect_build_path ? $cdata->{'Build-Path'} : undef;

if (defined($custom_build_path)) {
    if ($custom_build_path =~ m{['`\$\\"\(\)<>#]|(?:\a|/)[.][.](?:\z|/)}) {
        warn(
"Retry build with --no-respect-build-path to ignore the Build-Path field.\n"
        );
        die(
"Refusing to use $custom_build_path as Build-Path: Looks too special to be true"
        );
    }

    if ($custom_build_path eq '' or $custom_build_path !~ m{^/}) {
        warn(
"Retry build with --no-respect-build-path to ignore the Build-Path field.\n"
        );
        die(
qq{Build-Path must be a non-empty absolute path (i.e. start with "/").\n}
        );
    }
    print "Using defined Build-Path: ${custom_build_path}\n";
} else {
    if ($respect_build_path) {
        print
"No Build-Path defined; not setting a defined build path for this build.\n";
    }
}

my $srcpkg = Dpkg::Source::Package->new();
$srcpkg->{fields}{'Source'}  = $srcpkgname;
$srcpkg->{fields}{'Version'} = $srcpkgver;
my $dsc_fname
  = (dirname($buildinfo)) . '/' . $srcpkg->get_basename(1) . ".dsc";

my $environment = $cdata->{"Environment"};
if (not defined($environment)) {
    die "need Environment field\n";
}
$environment =~ s/\n/ /g;    # remove newlines
$environment =~ s/^ //;      # remove leading whitespace

my @environment;
foreach my $line (split /\n/, $cdata->{"Environment"}) {
    chomp $line;
    if ($line eq '') {
        next;
    }
    my ($name, $val) = split /=/, $line, 2;
    $val =~ s/^"(.*)"$/$1/;
    push @environment, "$name=$val";
}

# gather all installed build-depends and figure out the version of base-files
my $base_files_version;
my @inst_build_deps = ();
$inst_build_deps
  = deps_parse($inst_build_deps, reduce_arch => 0, build_dep => 0);
if (!defined $inst_build_deps) {
    die "deps_parse failed\n";
}

foreach my $pkg ($inst_build_deps->get_deps()) {
    if (!$pkg->isa('Dpkg::Deps::Simple')) {
        die "dependency disjunctions are not allowed\n";
    }
    if (not defined($pkg->{package})) {
        die "name undefined\n";
    }
    if (defined($pkg->{relation})) {
        if ($pkg->{relation} ne "=") {
            die "wrong relation";
        }
        if (not defined($pkg->{version})) {
            die "version undefined\n";
        }
    } else {
        die "no version";
    }
    if ($pkg->{package} eq "base-files") {
        if (defined($base_files_version)) {
            die "more than one base-files\n";
        }
        $base_files_version = $pkg->{version};
    }
    push @inst_build_deps,
      {
        name         => $pkg->{package},
        architecture => $pkg->{archqual},
        version      => $pkg->{version} };
}

if (!defined($base_files_version)) {
    die "no base-files\n";
}

# figure out the debian release from the version of base-files
my $base_dist;

my %base_files_map = ();
my $di_path        = '/usr/share/distro-info/debian.csv';
eval { require Debian::DistroInfo; };
if (!$@) {
    # libdistro-info-perl is installed
    my $di = DebianDistroInfo->new();
    foreach my $series ($di->all) {
        if (!$di->version($series)) {
            next;
        }
        $base_files_map{ $di->version($series) } = $series;
    }
} elsif (-f $di_path) {
    # distro-info-data is installed
    open my $fh, '<', $di_path or die "cannot open $di_path: $!\n";
    my $i = 0;
    while (my $line = <$fh>) {
        chomp($line);
        $i++;
        my @cells = split /,/, $line;
        if (scalar @cells < 4) {
            die "cannot parse line $i of $di_path\n";
        }
        if (
            $i == 1
            and (  scalar @cells < 6
                or $cells[0] ne 'version'
                or $cells[1] ne 'codename'
                or $cells[2] ne 'series'
                or $cells[3] ne 'created'
                or $cells[4] ne 'release'
                or $cells[5] ne 'eol')
        ) {
            die "cannot find correct header in $di_path\n";
        }
        if ($i == 1) {
            next;
        }
        $base_files_map{ $cells[0] } = $cells[2];
    }
    close $fh;
} else {
    # nothing is installed -- use hard-coded values
    %base_files_map = (
        "6"  => "squeeze",
        "7"  => "wheezy",
        "8"  => "jessie",
        "9"  => "stretch",
        "10" => "buster",
        "11" => "bullseye",
        "12" => "bookworm",
        "13" => "trixie",
    );
}

$base_files_version =~ s/^(\d+).*/$1/;

# we subtract one from $base_files_version because we want the Debian release
# before what is currently in unstable
$base_dist = $base_files_map{ $base_files_version - 1 };

if (!defined $base_dist) {
    die "base-files version didn't map to any Debian release\n";
}

my $src_date;
{
    print "retrieving snapshot.d.o data for $srcpkgname $srcpkgver\n";
    my $json_url
      = "http://snapshot.debian.org/mr/package/$srcpkgname/$srcpkgver/srcfiles?fileinfo=1";
    my $content = LWP::Simple::get($json_url);
    die "cannot retrieve $json_url" unless defined $content;
    my $json = JSON::PP->new();
    # json options taken from debsnap
    my $json_text = $json->allow_nonref->utf8->relaxed->decode($content);
    die "cannot decode json" unless defined $json_text;
    foreach my $result (@{ $json_text->{result} }) {
        # FIXME - assumption: package is from Debian official (and not ports)
        my @package_from_main = grep { $_->{archive_name} eq "debian" }
          @{ $json_text->{fileinfo}->{ $result->{hash} } };
        if (scalar @package_from_main > 1) {
            die
              "more than one package with the same hash in Debian official\n";
        }
        if (scalar @package_from_main == 0) {
            die "no package with the right hash in Debian official\n";
        }
        $src_date = $package_from_main[0]->{first_seen};
    }
}
if (!defined($src_date)) {
    die "cannot find .dsc\n";
}

# support timestamps being separated by a comma
my @required_timestamps = ();
if ($timestamp eq "first_seen") {
    # nothing to do, timestamps will be figured out later
} elsif ($timestamp eq "metasnap") {
    # acquire the required timestamps using metasnap.d.n
    print "retrieving required timestamps from metasnap.d.n\n";
    my $ua = LWP::UserAgent->new(timeout => 10);
    $ua->env_proxy;
    my @pkgs = ();
    foreach my $pkg (@inst_build_deps) {
        my $pkg_name = $pkg->{name};
        my $pkg_ver  = $pkg->{version};
        my $pkg_arch = $pkg->{architecture};
        if (defined $pkg_arch) {
            push @pkgs,
              URI::Escape::uri_escape("$pkg_name:$pkg_arch=$pkg_ver");
        } else {
            push @pkgs, URI::Escape::uri_escape("$pkg_name=$pkg_ver");
        }
    }
    my $response
      = $ua->get('https://metasnap.debian.net/cgi-bin/api'
          . '?archive=debian'
          . "&pkgs="
          . (join "%2C", @pkgs)
          . "&arch=$build_arch"
          . '&suite=unstable'
          . '&comp=main');
    if (!$response->is_success) {
        die "request to metasnap.d.n failed: $response->status_line";
    }
    foreach my $line (split /\n/, $response->decoded_content) {
        my ($arch, $t) = split / /, $line, 2;
        if ($arch ne $build_arch) {
            die
"debrebuild is currently unable to handle multiple architectures";
        }
        push @required_timestamps, $t;
    }
} else {
    @required_timestamps = split(/,/, $timestamp);
}

# setup a temporary apt directory

my $tempdir = tempdir(CLEANUP => 1);

foreach my $d ((
        '/etc/apt',                        '/etc/apt/apt.conf.d',
        '/etc/apt/preferences.d',          '/etc/apt/trusted.gpg.d',
        '/etc/apt/sources.list.d',         '/var/lib/apt/lists/partial',
        '/var/cache/apt/archives/partial', '/var/lib/dpkg',
    )
) {
    make_path("$tempdir/$d");
}

# We use the Build-Date field as a heuristic to find a good date for the
# stable release. If we would get the stable release from deb.debian.org
# instead, then packages might be newer than in unstable of the past because
# of point releases. The date from the source package will also work in most
# cases but will fail for binNMU buildinfo files where the source package
# might even come from years in the past
my $build_date;
{
    local $ENV{LC_ALL} = 'C';
    my $tp
      = Time::Piece->strptime($cdata->{'Build-Date'}, '%a, %d %b %Y %T %z');
    $build_date = $tp->strftime("%Y%m%dT%H%M%SZ");
}

sub get_sources_list() {
    my @result = ();
    push @result, "deb $base_mirror/$build_date/ $base_dist main";
    push @result, "deb-src $base_mirror/$src_date/ unstable main";
    foreach my $ts (@required_timestamps) {
        push @result, "deb $base_mirror/$ts/ unstable main";
    }
    return @result;
}

open(FH, '>', "$tempdir/etc/apt/sources.list");
print FH (join "\n", get_sources_list) . "\n";
close FH;
# FIXME - document what's dpkg's status for
# Create dpkg status
open(FH, '>', "$tempdir/var/lib/dpkg/status");
close FH;    #empty file
# Create apt.conf
my $aptconf = "$tempdir/etc/apt/apt.conf";
open(FH, '>', $aptconf);

# We create an apt.conf and pass it to apt via the APT_CONFIG environment
# variable instead of passing all options via the command line because
# otherwise apt will read the system's config first and might get unwanted
# configuration options from there. See apt.conf(5) for the order in which
# configuration options are read.
#
# While we are at it, we also set all other options through our custom
# apt.conf.
#
# Apt::Architecture has to be set because otherwise apt will default to the
# architecture apt was compiled for.
#
# Apt::Architectures has to be set or otherwise apt will use dpkg to find all
# foreign architectures of the system running apt.
#
# Dir::State::status has to be set even though Dir is set because Dir::State
# is set to var/lib/apt, so Dir::State::status would be below that but really
# isn't and without an absolute path, Dir::State::status would be constructed
# from Dir + Dir::State + Dir::State::status. This has been fixed in apt
# commit 475f75506db48a7fa90711fce4ed129f6a14cc9a.
#
# Acquire::Check-Valid-Until has to be set to false because the snapshot
# timestamps might be too far in the past to still be valid. This could be
# fixed by a solution to https://bugs.debian.org/763419
#
# Acquire::Languages has to be set to prevent downloading of translations from
# the mirrors.
#
# Binary::apt-get::Acquire::AllowInsecureRepositories has to be set to false
# so that apt-get update fails if repositories cannot be authenticated. The
# default value of this option will change to true with apt from Debian
# Buster.
#
# We need APT::Get::allow-downgrades set to true, because even if we choose a
# base distribution that was released before the state that "unstable"
# currently is in, the package versions in that stable release might be newer
# than what is in unstable due to security fixes. Choosing a stable release
# from an older snapshot timestamp would fix this problem but would defeat the
# purpose of a base distribution for builders like sbuild which can take
# advantage of existing chroot environments.

print FH <<EOF;
Apt {
   Architecture "$build_arch";
   Architectures "$build_arch";
};

Dir "$tempdir";
Dir::State::status "$tempdir/var/lib/dpkg/status";
Acquire::Languages "none";
Binary::apt-get::Acquire::AllowInsecureRepositories "false";
EOF
my @common_aptopts = (
    'Acquire::Check-Valid-Until "false";',
    'Acquire::http::Dl-Limit "1000";',
    'Acquire::https::Dl-Limit "1000";',
    'Acquire::Retries "5";',
    'APT::Get::allow-downgrades "true";',
);
foreach my $line (@common_aptopts) {
    print FH "$line\n";
}
close FH;

# add the removed keys because they are not returned by Dpkg::Vendor
# we don't need the Ubuntu vendor now but we already put the comments to
# possibly extend this script to other Debian derivatives
my @keyrings     = ();
my $debianvendor = Dpkg::Vendor::Debian->new();
push @keyrings, $debianvendor->run_hook('archive-keyrings');
push @keyrings, $debianvendor->run_hook('archive-keyrings-historic');
#my $ubuntuvendor = Dpkg::Vendor::Ubuntu->new();
#push @keyrings, $ubuntuvendor->run_hook('archive-keyrings');
#push @keyrings, $ubuntuvendor->run_hook('archive-keyrings-historic');

foreach my $keyring (@keyrings) {
    my $base = basename $keyring;
    print "$keyring\n";
    if (-f $keyring) {
        print "linking $tempdir/etc/apt/trusted.gpg.d/$base to $keyring\n";
        symlink $keyring, "$tempdir/etc/apt/trusted.gpg.d/$base";
    }
}

$ENV{'APT_CONFIG'} = $aptconf;

0 == system 'apt-get', 'update' or die "apt-get update failed\n";

sub dpkg_index_key_func {
    return
        $_[0]->{Package} . ' '
      . $_[0]->{Version} . ' '
      . $_[0]->{Architecture};
}

sub parse_all_packages_files {
    my $dpkg_index = Dpkg::Index->new(get_key_func => \&dpkg_index_key_func);

    open(my $fd, '-|', 'apt-get', 'indextargets', '--format', '$(FILENAME)',
        'Created-By: Packages');
    while (my $fname = <$fd>) {
        chomp $fname;
        print "parsing $fname...\n";
        open(my $fd2, '-|', '/usr/lib/apt/apt-helper', 'cat-file', $fname);
        $dpkg_index->parse($fd2, "pipe") or die "cannot parse Packages file\n";
        close($fd2);
    }
    close($fd);
    return $dpkg_index;
}

my $index = parse_all_packages_files();
if (scalar @required_timestamps == 0) {
    # go through all packages in the Installed-Build-Depends field and find out
    # the timestamps at which they were first seen each
    my %notfound_timestamps;

    my %missing;

    foreach my $pkg (@inst_build_deps) {
        my $pkg_name = $pkg->{name};
        my $pkg_ver  = $pkg->{version};
        my $pkg_arch = $pkg->{architecture};

      # check if we really need to acquire this package from snapshot.d.o or if
      # it already exists in the cache
        if (defined $pkg->{architecture}) {
            if ($index->get_by_key("$pkg_name $pkg_ver $pkg_arch")) {
                print "skipping $pkg_name $pkg_ver\n";
                next;
            }
        } else {
            if ($index->get_by_key("$pkg_name $pkg_ver $build_arch")) {
                $pkg->{architecture} = $build_arch;
                print "skipping $pkg_name $pkg_ver\n";
                next;
            }
            if ($index->get_by_key("$pkg_name $pkg_ver all")) {
                $pkg->{architecture} = "all";
                print "skipping $pkg_name $pkg_ver\n";
                next;
            }
        }

        print "retrieving snapshot.d.o data for $pkg_name $pkg_ver\n";
        my $json_url
          = "http://snapshot.debian.org/mr/binary/$pkg_name/$pkg_ver/binfiles?fileinfo=1";
        my $content = LWP::Simple::get($json_url);
        die "cannot retrieve $json_url" unless defined $content;
        my $json = JSON::PP->new();
        # json options taken from debsnap
        my $json_text = $json->allow_nonref->utf8->relaxed->decode($content);
        die "cannot decode json" unless defined $json_text;
        my $pkg_hash;
        if (scalar @{ $json_text->{result} } == 1) {
           # if there is only a single result, then the package must either be
           # Architecture:all, be the build architecture or match the requested
           # architecture
            $pkg_hash = ${ $json_text->{result} }[0]->{hash};
            $pkg->{architecture}
              = ${ $json_text->{result} }[0]->{architecture};
            # if a specific architecture was requested, it should match
            if (defined $pkg_arch && $pkg_arch ne $pkg->{architecture}) {
                die
"package $pkg_name was explicitly requested for $pkg_arch but only $pkg->{architecture} was found\n";
            }
            # if no specific architecture was requested, it should be the build
            # architecture
            if (   !defined $pkg_arch
                && $build_arch ne $pkg->{architecture}
                && "all" ne $pkg->{architecture}) {
                die
"package $pkg_name was implicitly requested for $pkg_arch but only $pkg->{architecture} was found\n";
            }
          # Ensure that $pkg_arch is defined from here as we want to look it up
          # later in a Packages file from snapshot.d.o if it is not in the
          # current Packages file
            $pkg_arch = $pkg->{architecture};
        } else {
            # Since the package occurs more than once, we expect it to be of
            # Architecture:any
            #
            # If no specific architecture was requested, look for the build
            # architecture
            if (!defined $pkg_arch) {
                $pkg_arch = $build_arch;
            }
            foreach my $result (@{ $json_text->{result} }) {
                if ($result->{architecture} eq $pkg_arch) {
                    $pkg_hash = $result->{hash};
                    last;
                }
            }
            if (!defined($pkg_hash)) {
                die "cannot find package in architecture $pkg_arch\n";
            }
            # we now know that this package is not architecture:all but has a
            # concrete architecture
            $pkg->{architecture} = $pkg_arch;
        }
        # FIXME - assumption: package is from Debian official (and not ports)
        my @package_from_main = grep { $_->{archive_name} eq "debian" }
          @{ $json_text->{fileinfo}->{$pkg_hash} };
        if (scalar @package_from_main > 1) {
            die
              "more than one package with the same hash in Debian official\n";
        }
        if (scalar @package_from_main == 0) {
            die "no package with the right hash in Debian official\n";
        }
        my $date = $package_from_main[0]->{first_seen};
        $pkg->{first_seen}                             = $date;
        $notfound_timestamps{$date}                    = 1;
        $missing{"${pkg_name}/${pkg_ver}/${pkg_arch}"} = 1;
    }

    # feed apt with timestamped snapshot.debian.org URLs until apt is able to
    # find all the required package versions. We start with the most recent
    # timestamp, check which packages cannot be found at that timestamp, add
    # the timestamp of the most recent not-found package and continue doing
    # this iteratively until all versions can be found.

    while (0 < scalar keys %notfound_timestamps) {
        print "left to check: " . (scalar keys %notfound_timestamps) . "\n";
        my @timestamps = map { Time::Piece->strptime($_, '%Y%m%dT%H%M%SZ') }
          (sort keys %notfound_timestamps);
        my $newest = $timestamps[$#timestamps];
        $newest = $newest->strftime("%Y%m%dT%H%M%SZ");
        push @required_timestamps, $newest;
        delete $notfound_timestamps{$newest};

        my $snapshot_url = "$base_mirror/$newest/";

        open(FH, '>>', "$tempdir/etc/apt/sources.list");
        print FH "deb ${snapshot_url} unstable main\n";
        close FH;

        0 == system 'apt-get', 'update' or die "apt-get update failed\n";

        my $index = parse_all_packages_files();
        foreach my $pkg (@inst_build_deps) {
            my $pkg_name   = $pkg->{name};
            my $pkg_ver    = $pkg->{version};
            my $pkg_arch   = $pkg->{architecture};
            my $first_seen = $pkg->{first_seen};
            my $cdata = $index->get_by_key("$pkg_name $pkg_ver $pkg_arch");
            if (not defined($cdata->{"Package"})) {
                # Not present yet; we hope a later snapshot URL will locate it.
                next;
            }
            delete($missing{"${pkg_name}/${pkg_ver}/${pkg_arch}"});
            if (defined $first_seen) {
              # this may delete timestamps that we actually need for some other
              # packages
                delete $notfound_timestamps{$first_seen};
            }
        }
    }

    if (%missing) {
        print STDERR 'Cannot locate the following packages via snapshots'
          . " or the current repo/mirror\n";
        for my $key (sort(keys(%missing))) {
            print STDERR "  ${key}\n";
        }
        exit(1);
    }
} else {
    # find out the actual package architecture for all installed build
    # dependencies without explicit architecture qualification
    foreach my $pkg (@inst_build_deps) {
        my $pkg_name = $pkg->{name};
        my $pkg_ver  = $pkg->{version};
        if (defined $pkg->{architecture}) {
            next;
        }
        if ($index->get_by_key("$pkg_name $pkg_ver $build_arch")) {
            $pkg->{architecture} = $build_arch;
            next;
        }
        if ($index->get_by_key("$pkg_name $pkg_ver all")) {
            $pkg->{architecture} = "all";
            next;
        }
        die "cannot find $pkg_name $pkg_ver in index\n";
    }
}

# remove $tempdir manually to avoid any surprises
0 == system 'apt-get', '--option',
  'Dir::Etc::SourceList=/dev/null',  '--option',
  'Dir::Etc::SourceParts=/dev/null', 'update'
  or die "apt-get update failed\n";

foreach my $f (
    '/var/cache/apt/pkgcache.bin',
    '/var/cache/apt/srcpkgcache.bin',
    '/var/lib/dpkg/status',
    '/var/lib/apt/lists/lock',
    '/etc/apt/apt.conf',
    '/etc/apt/sources.list',
    '/etc/apt/trusted.gpg.d/debian-archive-removed-keys.gpg',
    '/etc/apt/trusted.gpg.d/debian-archive-keyring.gpg'
) {
    unlink "$tempdir/$f" or die "cannot unlink $tempdir/$f: $!\n";
}

foreach my $d (
    '/var/cache/apt/archives/partial', '/var/cache/apt/archives',
    '/var/cache/apt',                  '/var/cache',
    '/var/lib/dpkg',                   '/var/lib/apt/lists/auxfiles',
    '/var/lib/apt/lists/partial',      '/var/lib/apt/lists',
    '/var/lib/apt',                    '/var/lib',
    '/var',                            '/etc/apt/sources.list.d',
    '/etc/apt/trusted.gpg.d',          '/etc/apt/preferences.d',
    '/etc/apt/apt.conf.d',             '/etc/apt',
    '/etc',                            ''
) {
    rmdir "$tempdir/$d" or die "cannot rmdir $d: $!\n";
}

!-e $tempdir or die "failed to remove $tempdir\n";

if ($builder ne "none") {
    if (!-e $outdir) {
        make_path($outdir);
    }
}

my $build       = '';
my $changesarch = '';
if ($build_archany and $build_archall) {
    $build       = "binary";
    $changesarch = $host_arch;
} elsif ($build_archany and !$build_archall) {
    $build       = "any";
    $changesarch = $host_arch;
} elsif (!$build_archany and $build_archall) {
    $build       = "all";
    $changesarch = 'all';
} else {
    die "nothing to build\n";
}

my @install = ();
foreach my $pkg (@inst_build_deps) {
    my $pkg_name = $pkg->{name};
    my $pkg_ver  = $pkg->{version};
    my $pkg_arch = $pkg->{architecture};
    if (any { $_ eq $builder } ('mmdebstrap', 'none', 'dpkg')) {
        if ($pkg_arch eq "all" || $pkg_arch eq $build_arch) {
            push @install, "$pkg_name=$pkg_ver";
        } else {
            push @install, "$pkg_name:$pkg_arch=$pkg_ver";
        }
    } elsif (any { $_ eq $builder } ('sbuild', 'sbuild+unshare')) {
        if ($pkg_arch eq "all" || $pkg_arch eq $build_arch) {
            push @install, "$pkg_name (= $pkg_ver)";
        } else {
            push @install, "$pkg_name:$pkg_arch (= $pkg_ver)";
        }
    } else {
        die "unsupported builder: $builder\n";
    }
}

if ($builder eq "none") {
    print "\n";
    print "Manual installation and build\n";
    print "-----------------------------\n";
    print "\n";
    print
      "The following sources.list contains all the required repositories:\n";
    print "\n";
    print(join "\n", get_sources_list);
    print "\n";
    print "You can manually install the right dependencies like this:\n";
    print "\n";
    print "apt-get install --no-install-recommends";

    # Release files from snapshots.d.o have often expired by the time
    # we fetch them.  Include the option to work around that to assist
    # the user.
    print " -oAcquire::Check-Valid-Until=false";
    foreach my $pkg (@install) {
        print " $pkg";
    }
    print "\n";
    print "\n";
    print "And then build your package:\n";
    print "\n";
    if ($custom_build_path) {
        require Cwd;
        my $custom_build_parent_dir = dirname($custom_build_path);
        my $dsc_path                = Cwd::realpath($dsc_fname)
          // die("Cannot resolve ${dsc_fname}: $!\n");
        print "mkdir -p \"${custom_build_parent_dir}\"\n";
        print qq{dpkg-source -x "${dsc_path}" "${custom_build_path}"\n};
        print "cd \"$custom_build_path\"\n";
    } else {
        print qq{dpkg-source -x "${dsc_fname}"\n};
        print "cd packagedirectory\n";
    }
    print "\n";
    if ($cdata->{"Binary-Only-Changes"}) {
        print(  "Since this is a binNMU, you must put the following "
              . "lines at the top of debian/changelog:\n\n");
        print($cdata->{"Binary-Only-Changes"});
    }
    print "\n";
    print(  "$environment dpkg-buildpackage -uc "
          . "--host-arch=$host_arch --build=$build\n");
} elsif ($builder eq "dpkg") {
    if ("$build_arch\n" ne `dpkg --print-architecture`) {
        die "must be run on $build_arch\n";
    }

    if ($> != 0) {
        die "you must be root for the dpkg builder\n";
    }

    if (-e $custom_build_path) {
        die "$custom_build_path exists -- refusing to overwrite\n";
    }

    my $sources = '/etc/apt/sources.list.d/debrebuild.list';
    if (-e $sources) {
        die "$sources already exists -- refusing to overwrite\n";
    }
    open(FH, '>', $sources) or die "cannot open $sources: $!\n";
    print FH (join "\n", get_sources_list) . "\n";
    close FH;

    my $config = '/etc/apt/apt.conf.d/23-debrebuild.conf';
    if (-e $config) {
        die "$config already exists -- refusing to overwrite\n";
    }
    open(FH, '>', $config) or die "cannot open $config: $!\n";
    foreach my $line (@common_aptopts) {
        print FH "$line\n";
    }
    close FH;

    0 == system 'apt-get', 'update' or die "apt-get update failed\n";

    my @cmd
      = ('apt-get', 'install', '--no-install-recommends', '--yes', @install);
    0 == system @cmd or die "apt-get install failed\n";

    0 == system 'apt-get', 'source', '--only-source', '--download-only',
      "$srcpkgname=$srcpkgver"
      or die "apt-get source failed\n";
    unlink $sources or die "failed to unlink $sources\n";
    unlink $config  or die "failed to unlink $config\n";
    make_path(dirname $custom_build_path);
    0 == system 'dpkg-source', '--no-check', '--extract',
      $srcpkg->get_basename(1) . '.dsc', $custom_build_path
      or die "dpkg-source failed\n";

    if ($cdata->{"Binary-Only-Changes"}) {
        open my $infh, '<', "$custom_build_path/debian/changelog"
          or die "cannot open debian/changelog for reading: $!\n";
        my $changelogcontent = do { local $/; <$infh> };
        close $infh;
        open my $outfh, '>', "$custom_build_path/debian/changelog"
          or die "cannot open debian/changelog for writing: $!\n";
        my $logentry = $cdata->{"Binary-Only-Changes"};
        # due to storing the binnmu changelog entry in deb822 buildinfo, the
        # first character is an unwanted newline
        $logentry =~ s/^\n//;
        print $outfh $logentry;
        # while the linebreak at the beginning is wrong, there are two missing
        # at the end
        print $outfh "\n\n";
        print $outfh $changelogcontent;
        close $outfh;
    }
    0 == system 'env', "--chdir=$custom_build_path", @environment,
      'dpkg-buildpackage', '-uc', "--host-arch=$host_arch", "--build=$build"
      or die "dpkg-buildpackage failed\n";
    # we are not interested in the unpacked source directory
    0 == system 'rm', '-r', $custom_build_path
      or die "failed to remove $custom_build_path: $?";
    # but instead we want the produced artifacts
    0 == system 'dcmd', 'mv',
      (dirname $custom_build_path)
      . "/${srcpkgname}_${srcpkgbinver}_$changesarch.changes", $outdir
      or die "dcmd failed\n";
} elsif ($builder eq "sbuild" or $builder eq "sbuild+unshare") {
    my $tarballpath = File::HomeDir->my_home
      . "/.cache/sbuild/$base_dist-$build_arch.tar.gz";
    if ($builder eq "sbuild+unshare") {
        if (!-e $tarballpath) {
            my $chrootdir = tempdir();
            0 == system 'sbuild-createchroot', '--chroot-mode=unshare',
              '--make-sbuild-tarball', $tarballpath,
              $base_dist, $chrootdir, "$base_mirror/$build_date/"
              or die "sbuild-createchroot failed\n";
            !-e $chrootdir or die "$chrootdir wasn't removed\n";
        }
    }

    my @cmd = ('env', "--chdir=$outdir", @environment, 'sbuild');
    foreach my $line (get_sources_list) {
        push @cmd, "--extra-repository=$line";
    }

    # Release files from snapshots.d.o have often expired by the time
    # we fetch them.  Include the option to work around that to assist
    # the user.
    push @cmd,
        '--chroot-setup-commands=echo '
      . (String::ShellQuote::shell_quote(join '\n', @common_aptopts))
      . ' | tee /etc/apt/apt.conf.d/23-debrebuild.conf';

    # sbuild chroots have build-essential already installed. This might
    # interfere with the packages that we need to install. Example:
    # libc6-dev : Breaks: libgcc-8-dev (< 8.4.0-2~) but 8.3.0-6 is to be inst..
    # Thus, we remove them beforehand -- the right versions will get installed
    # later anyways.
    # We have to list the packages manually instead of relying on autoremove
    # because debootstrap marks them all as manually installed.
    push @cmd,
      (     '--chroot-setup-commands=apt-get --yes remove build-essential'
          . ' libc6-dev gcc g++ make dpkg-dev');
    push @cmd, '--chroot-setup-commands=apt-get --yes autoremove';

    push @cmd, "--add-depends=" . (join ",", @install);
    push @cmd, "--build=$build_arch";
    push @cmd, "--host=$host_arch";

    if ($build_source) {
        push @cmd, '--source';
    } else {
        push @cmd, '--no-source';
    }
    if ($build_archany) {
        push @cmd, '--arch-any';
    } else {
        push @cmd, '--no-arch-any';
    }
    if ($build_archall) {
        push @cmd, '--arch-all';
    } else {
        push @cmd, '--no-arch-all';
    }
    if ($cdata->{"Binary-Only-Changes"}) {
        push @cmd, "--binNMU-changelog=$cdata->{'Binary-Only-Changes'}";
    }
    if ($builder eq "sbuild+unshare") {
        push @cmd, "--chroot=$tarballpath";
        push @cmd, "--chroot-mode=unshare";
    }
    push @cmd, "--dist=$base_dist";
    push @cmd, "--no-run-lintian";
    push @cmd, "--no-run-autopkgtest";
    push @cmd, "--no-apt-upgrade";
    push @cmd, "--no-apt-distupgrade";
    # disable the explainer
    push @cmd, "--bd-uninstallable-explainer=";
    # We need the aspcud resolver to install packages that are older than the
    # ones in the latest snapshot. Apt by default will only use the latest
    # package versions as candidates and sbuild uses a dummy package instead
    # of crafting an apt command line with the exact version requirements.
    push @cmd, "--build-dep-resolver=aspcud";

    if ($custom_build_path) {
        push @cmd, "--build-path=$custom_build_path";
    }
    push @cmd, "${srcpkgname}_$srcpkgver";
    print((join " ", @cmd) . "\n");
    0 == system @cmd or die "sbuild failed\n";
} elsif ($builder eq "mmdebstrap") {

    my @binnmucmds = ();
    if ($cdata->{"Binary-Only-Changes"}) {
        my $logentry = $cdata->{"Binary-Only-Changes"};
     # due to storing the binnmu changelog entry in deb822 buildinfo, the first
     # character is an unwanted newline
        $logentry =~ s/^\n//;
      # while the linebreak at the beginning is wrong, there are two missing at
      # the end
        $logentry .= "\n\n";
        push @binnmucmds,
            '{ printf "%s" '
          . (String::ShellQuote::shell_quote $logentry)
          . "; cat debian/changelog; } > debian/changelog.debrebuild",
          "mv debian/changelog.debrebuild debian/changelog";
    }

    my @cmd = (
        'env', '-i',
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin',
        'mmdebstrap',
        "--arch=$build_arch",
        "--variant=apt",
        (map { "--aptopt=$_" } @common_aptopts),
        '--include=' . (join ' ', @install),
        '--essential-hook=chroot "$1" sh -c "'
          . (
            join ' && ',
            'rm /etc/apt/sources.list',
            'echo '
              . (
                String::ShellQuote::shell_quote(
                    (join "\n", get_sources_list) . "\n"
                ))
              . ' >> /etc/apt/sources.list',
            'apt-get update'
          )
          . '"',
        '--customize-hook=chroot "$1" sh -c "'
          . (
            join ' && ',
            "apt-get source --only-source -d $srcpkgname=$srcpkgver",
            "mkdir -p "
              . (String::ShellQuote::shell_quote(dirname $custom_build_path)),
            "dpkg-source --no-check -x /"
              . $srcpkg->get_basename(1) . '.dsc '
              . (String::ShellQuote::shell_quote $custom_build_path),
            'cd ' . (String::ShellQuote::shell_quote $custom_build_path),
            @binnmucmds,
"env $environment dpkg-buildpackage -uc -a $host_arch --build=$build",
            'cd /',
            'rm -r ' . (String::ShellQuote::shell_quote $custom_build_path))
          . '"',
        '--customize-hook=sync-out '
          . (dirname $custom_build_path)
          . " $outdir",
        $base_dist,
        '/dev/null',
        "deb $base_mirror/$build_date/ $base_dist main"
    );
    print((join ' ', @cmd) . "\n");

    0 == system @cmd or die "mmdebstrap failed\n";
} else {
    die "unsupported builder: $builder\n";
}

# test if all checksums in the buildinfo file check out
if ($builder ne "none") {
    print "build artifacts stored in $outdir\n";

    my $checksums = Dpkg::Checksums->new();
    $checksums->add_from_control($cdata);
    # remove the .dsc as we only did the binaries
    #  - the .dsc cannot be reproduced anyways because we cannot reproduce its
    #    signature
    #  - binNMUs can only be done with --build=any
    foreach my $file ($checksums->get_files()) {
        if ($file !~ /\.dsc$/) {
            next;
        }
        $checksums->remove_file($file);
    }

    my $new_cdata
      = Dpkg::Control->new(type => CTRL_FILE_BUILDINFO, allow_pgp => 1);
    $new_cdata->load($new_buildinfo);
    my $new_checksums = Dpkg::Checksums->new();
    $new_checksums->add_from_control($new_cdata);

    my @files     = $checksums->get_files();
    my @new_files = $new_checksums->get_files();

    if (scalar @files != scalar @new_files) {
        print("old buildinfo:\n" . (join "\n", @files) . "\n");
        print("new buildinfo:\n" . (join "\n", @new_files) . "\n");
        die "new buildinfo contains a different number of files\n";
    }

    for (my $i = 0 ; $i <= $#files ; $i++) {
        if ($files[$i] ne $new_files[$i]) {
            die "different checksum files at position $i\n";
        }
        if ($files[$i] =~ /\.dsc$/) {
            print("skipping $files[$i]\n");
            next;
        }
        print("checking $files[$i]: ");
        if ($checksums->get_size($files[$i])
            != $new_checksums->get_size($files[$i])) {
            die "size differs for $files[$i]\n";
        } else {
            print("size... ");
        }
        my $chksum     = $checksums->get_checksum($files[$i], undef);
        my $new_chksum = $new_checksums->get_checksum($new_files[$i], undef);
        if (scalar keys %{$chksum} != scalar keys %{$new_chksum}) {
            die "different algos for $files[$i]\n";
        }
        foreach my $algo (keys %{$chksum}) {
            if (!exists $new_chksum->{$algo}) {
                die "$algo is not used in both buildinfo files\n";
            }
            if ($chksum->{$algo} ne $new_chksum->{$algo}) {
                die "value of $algo differs for $files[$i]\n";
            }
            print("$algo... ");
        }
        print("all OK\n");
    }
}
