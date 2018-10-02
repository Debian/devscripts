#!/usr/bin/perl
# -*- tab-width: 8; indent-tabs-mode: t; cperl-indent-level: 4 -*-
# vim: set shiftwidth=4 tabstop=8 noexpandtab:
#   Copyright (C) Patrick Schoenfeld
#                 2015 Johannes Schauer <josch@debian.org>
#                 2017 James McCoy <jamessan@debian.org>
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

build-rdeps - find packages that depend on a specific package to build (reverse build depends)

=head1 SYNOPSIS

B<build-rdeps> I<package>

=head1 DESCRIPTION

B<build-rdeps> searches for all packages that build-depend on the specified package.

The default behaviour is to just `grep` for the given dependency in the
Build-Depends field of apt's Sources files.

If the package dose-extra >= 4.0 is installed, then a more complete reverse
build dependency computation is carried out. In particular, with that package
installed, build-rdeps will find transitive reverse dependencies, respect
architecture and build profile restrictions, take Provides relationships,
Conflicts, Pre-Depends, Build-Depends-Arch and versioned dependencies into
account and correctly resolve multiarch relationships for crossbuild reverse
dependency resolution.  (This tends to be a slow process due to the complexity
of the package interdependencies.)

=head1 OPTIONS

=over 4

=item B<-u>, B<--update>

Run apt-get update before searching for build-depends.

=item B<-s>, B<--sudo>

Use sudo when running apt-get update. Has no effect if -u is omitted.

=item B<--distribution>

Select another distribution, which is searched for build-depends.

=item B<--only-main>

Ignore contrib and non-free

=item B<--exclude-component>

Ignore the given component (e.g. main, contrib, non-free).

=item B<--origin>

Restrict the search to only the specified origin (such as "Debian").

=item B<-m>, B<--print-maintainer>

Print the value of the maintainer field for each package.

=item B<--host-arch>

Explicitly set the host architecture. The default is the value of
`dpkg-architecture -qDEB_HOST_ARCH`. This option only works if dose-extra >=
4.0 is installed.

=item B<--old>

Force the old simple behaviour without dose-ceve support even if dose-extra >=
4.0 is installed.  (This tends to be faster.)

Notice, that the old behaviour only finds direct dependencies, ignores virtual
dependencies, does not find transitive dependencies and does not take version
relationships, architecture restrictions, build profiles or multiarch
relationships into account.

=item B<--build-arch>

Explicitly set the build architecture. The default is the value of
`dpkg-architecture -qDEB_BUILD_ARCH`. This option only works if dose-extra >=
4.0 is installed.

=item B<--quiet>

Don't print meta information (header, counter). Making it easier to use in
scripts.

=item B<-d>, B<--debug>

Run the debug mode

=item B<--help>

Show the usage information.

=item B<--version>

Show the version information.

=back

=head1 REQUIREMENTS

The tool requires apt Sources files to be around for the checked components.
In the default case this means that in /var/lib/apt/lists files need to be
around for main, contrib and non-free.

In practice this means one needs to add one deb-src line for each component,
e.g.

deb-src http://<mirror>/debian <dist> main contrib non-free

and run apt-get update afterwards or use the update option of this tool.

=cut

use warnings;
use strict;
use File::Basename;
use Getopt::Long qw(:config bundling permute no_getopt_compat);

use Dpkg::Control;
use Dpkg::Vendor qw(get_current_vendor);

my $progname = basename($0);
my $version  = '1.0';
my $use_ceve = 0;
my $ceve_compatible;
my $opt_debug;
my $opt_update;
my $opt_sudo;
my $opt_maintainer;
my $opt_mainonly;
my $opt_distribution;
my $opt_origin = 'Debian';
my @opt_exclude_components;
my $opt_buildarch;
my $opt_hostarch;
my $opt_without_ceve;
my $opt_quiet;

sub version {
    print <<"EOT";
This is $progname $version, from the Debian devscripts package, v. ###VERSION###
This code is copyright by Patrick Schoenfeld, all rights reserved.
It comes with ABSOLUTELY NO WARRANTY. You are free to redistribute this code
under the terms of the GNU General Public License, version 2 or later.
EOT
    exit(0);
}

sub usage {
    print <<"EOT";
usage: $progname packagename
       $progname --help
       $progname --version

Searches for all packages that build-depend on the specified package.

Options:
   -u, --update                   Run apt-get update before searching for build-depends.
                                  (needs root privileges)
   -s, --sudo                     Use sudo when running apt-get update
                                  (has no effect when -u is omitted)
   -q, --quiet                    Don't print meta information
   -d, --debug                    Enable the debug mode
   -m, --print-maintainer         Print the maintainer information (experimental)
   --distribution distribution    Select a distribution to search for build-depends
                                  (Default: unstable)
   --origin origin                Select an origin to search for build-depends
                                  (Default: Debian)
   --only-main                    Ignore contrib and non-free
   --exclude-component COMPONENT  Ignore the specified component (can be given multiple times)
   --host-arch                    Set the host architecture (requires dose-extra >= 4.0)
   --build-arch                   Set the build architecture (requires dose-extra >= 4.0)
   --old                          Use the old simple reverse dependency resolution

EOT
    version;
}

sub test_ceve {
    return $ceve_compatible if defined $ceve_compatible;

    # test if the debsrc input and output format is supported by the installed
    # ceve version
    system('dose-ceve -T debsrc debsrc:///dev/null > /dev/null 2>&1');
    if ($? == -1) {
        print STDERR "DEBUG: dose-ceve cannot be executed: $!\n"
          if ($opt_debug);
        $ceve_compatible = 0;
    } elsif ($? == 0) {
        $ceve_compatible = 1;
    } else {
        print STDERR "DEBUG: dose-ceve is too old\n" if ($opt_debug);
        $ceve_compatible = 0;
    }
    return $ceve_compatible;
}

sub is_devel_release {
    my $ctrl = shift;
    if (get_current_vendor() eq 'Debian') {
        return $ctrl->{Suite} eq 'unstable' || $ctrl->{Codename} eq 'sid';
    } else {
        return $ctrl->{Suite} eq 'devel';
    }
}

sub indextargets {
    my @cmd = ('apt-get', 'indextargets', 'DefaultEnabled: yes');

    if (!$use_ceve) {
        # ceve needs both Packages and Sources
        push(@cmd, 'Created-By: Sources');
    }

    if ($opt_origin) {
        push(@cmd, "Origin: $opt_origin");
    }

    if ($opt_mainonly) {
        push(@cmd, 'Component: main');
    }

    print STDERR 'DEBUG: Running ' . join(' ', map { "'$_'" } @cmd) . "\n"
      if $opt_debug;
    return @cmd;
}

# Gather information about the available package/source lists.
#
# Returns a hash reference following this structure:
#
# <site> => {
#     <suite> => {
#         <component> => {
#             sources => $src_fname,
#             <arch1> => $arch1_fname,
#             ...,
#         },
#     },
# ...,
sub collect_files {
    my %info = ();

    open(my $targets, '-|', indextargets());

    until (eof $targets) {
        my $ctrl = Dpkg::Control->new(type => CTRL_UNKNOWN);
        if (!$ctrl->parse($targets, 'apt-get indextargets')) {
            next;
        }
        # Only need Sources/Packages stanzas
        if (   $ctrl->{'Created-By'} ne 'Packages'
            && $ctrl->{'Created-By'} ne 'Sources') {
            next;
        }

        # In expected components
        if (   !$opt_mainonly
            && exists $ctrl->{Component}
            && @opt_exclude_components) {
            my $invalid_component = '(?:'
              . join('|', map { "\Q$_\E" } @opt_exclude_components) . ')';
            if ($ctrl->{Component} =~ m/$invalid_component/) {
                next;
            }
        }

        # And the provided distribution
        if ($opt_distribution) {
            if (   $ctrl->{Suite} !~ m/\Q$opt_distribution\E/
                && $ctrl->{Codename} !~ m/\Q$opt_distribution\E/) {
                next;
            }
        } elsif (!is_devel_release($ctrl)) {
            next;
        }

        $info{ $ctrl->{Site} }{ $ctrl->{Suite} }{ $ctrl->{Component} } ||= {};
        my $ref
          = $info{ $ctrl->{Site} }{ $ctrl->{Suite} }{ $ctrl->{Component} };

        if ($ctrl->{'Created-By'} eq 'Sources') {
            $ref->{sources} = $ctrl->{Filename};
            print STDERR "DEBUG: Added source file: $ctrl->{Filename}\n"
              if $opt_debug;
        } else {
            $ref->{ $ctrl->{Architecture} } = $ctrl->{Filename};
        }
    }
    close($targets);

    return \%info;
}

sub findreversebuilddeps {
    my ($package, $info) = @_;
    my $count = 0;

    my $source_file = $info->{sources};
    if ($use_ceve) {
        die "build arch undefined" if !defined $opt_buildarch;
        die "host arch undefined"  if !defined $opt_hostarch;

        my $buildarch_file = $info->{$opt_buildarch};
        my $hostarch_file  = $info->{$opt_hostarch};

        my @ceve_cmd = (
            'dose-ceve',             '-T',
            'debsrc',                '-r',
            $package,                '-G',
            'pkg',                   "--deb-native-arch=$opt_buildarch",
            "deb://$buildarch_file", "debsrc://$source_file"
        );
        if ($opt_buildarch ne $opt_hostarch) {
            push(@ceve_cmd,
                "--deb-host-arch=$opt_hostarch",
                "deb://$hostarch_file");
        }
        my %sources;
        print STDERR 'DEBUG: executing: ' . join(' ', @ceve_cmd)
          if ($opt_debug);
        open(SOURCES, '-|', @ceve_cmd);
        while (<SOURCES>) {
            next unless s/^Package:\s+//;
            chomp;
            $sources{$_} = 1;
        }
        for my $source (sort keys %sources) {
            print $source;
            if ($opt_maintainer) {
                my $maintainer
                  = `apt-cache showsrc $source | grep-dctrl -n -s Maintainer '' | sort -u`;
                print " ($maintainer)";
            }
            print "\n";
            $count += 1;
        }
    } else {
        open(my $out, '-|', '/usr/lib/apt/apt-helper', 'cat-file',
            $source_file)
          or die
"$progname: Unable to run \"apt-helper cat-file '$source_file'\": $!";

        my %packages;
        until (eof $out) {
            my $ctrl = Dpkg::Control->new(type => CTRL_INDEX_SRC);
            if (!$ctrl->parse($out, 'apt-helper cat-file')) {
                next;
            }
            print STDERR "$ctrl\n" if ($opt_debug);
            for my $relation (
                qw(Build-Depends Build-Depends-Indep Build-Depends-Arch)) {
                if (exists $ctrl->{$relation}) {
                    if ($ctrl->{$relation}
                        =~ m/^(.*\s)?\Q$package\E(?::[a-zA-Z0-9][a-zA-Z0-9-]*)?([\s,]|$)/
                    ) {
                        $packages{ $ctrl->{Package} }{Maintainer}
                          = $ctrl->{Maintainer};
                    }
                }
            }
        }

        close($out);

        while (my $depending_package = each(%packages)) {
            print $depending_package;
            if ($opt_maintainer) {
                print " ($packages{$depending_package}->{'Maintainer'})";
            }
            print "\n";
            $count += 1;
        }
    }

    if (!$opt_quiet) {
        if ($count == 0) {
            print "No reverse build-depends found for $package.\n\n";
        } else {
            print
"\nFound a total of $count reverse build-depend(s) for $package.\n\n";
        }
    }
}

if ($#ARGV < 0) { usage; exit(0); }

GetOptions(
    "u|update"            => \$opt_update,
    "s|sudo"              => \$opt_sudo,
    "m|print-maintainer"  => \$opt_maintainer,
    "distribution=s"      => \$opt_distribution,
    "only-main"           => \$opt_mainonly,
    "exclude-component=s" => \@opt_exclude_components,
    "origin=s"            => \$opt_origin,
    "host-arch=s"         => \$opt_hostarch,
    "build-arch=s"        => \$opt_buildarch,
    #   "profiles=s" => \$opt_profiles, # FIXME: add build profile support
    #                                            once dose-ceve has a
    #                                            --deb-profiles option
    "old"       => \$opt_without_ceve,
    "q|quiet"   => \$opt_quiet,
    "d|debug"   => \$opt_debug,
    "h|help"    => sub { usage; },
    "v|version" => sub { version; }) or do { usage; exit 1; };

my $package = shift;

if (!$package) {
    die "$progname: missing argument. expecting packagename\n";
}

print STDERR "DEBUG: Package => $package\n" if ($opt_debug);

if ($opt_hostarch) {
    if ($opt_without_ceve) {
        die
"$progname: the --host-arch option cannot be used together with --old\n";
    }
    if (test_ceve()) {
        $use_ceve = 1;
    } else {
        die
"$progname: the --host-arch option requires dose-extra >= 4.0 to be installed\n";
    }
}

if ($opt_buildarch) {
    if ($opt_without_ceve) {
        die
"$progname: the --build-arch option cannot be used together with --old\n";
    }
    if (test_ceve()) {
        $use_ceve = 1;
    } else {
        die
"$progname: the --build-arch option requires dose-extra >= 4.0 to be installed\n";
    }
}

# if ceve usage has not been activated yet, check if it can be activated
if (!$use_ceve and !$opt_without_ceve) {
    if (test_ceve()) {
        $use_ceve = 1;
    } else {
        print STDERR
"WARNING: dose-extra >= 4.0 is not installed. Falling back to old unreliable behaviour.\n";
    }
}

if ($use_ceve) {
    if (system('command -v grep-dctrl >/dev/null 2>&1')) {
        die
"$progname: Fatal error. grep-dctrl is not available.\nPlease install the 'dctrl-tools' package.\n";
    }

    # set hostarch and buildarch if they have not been set yet
    if (!$opt_hostarch) {
        $opt_hostarch = `dpkg-architecture --query DEB_HOST_ARCH`;
        chomp $opt_hostarch;
    }
    if (!$opt_buildarch) {
        $opt_buildarch = `dpkg-architecture --query DEB_BUILD_ARCH`;
        chomp $opt_buildarch;
    }
    print STDERR "DEBUG: running with dose-ceve resolver\n" if ($opt_debug);
    print STDERR "DEBUG: buildarch=$opt_buildarch hostarch=$opt_hostarch\n"
      if ($opt_debug);
} else {
    print STDERR "DEBUG: running with old resolver\n" if ($opt_debug);
}

if ($opt_update) {
    print STDERR "DEBUG: Updating apt-cache before search\n" if ($opt_debug);
    my @cmd;
    if ($opt_sudo) {
        print STDERR "DEBUG: Using sudo to become root\n" if ($opt_debug);
        push(@cmd, 'sudo');
    }
    push(@cmd, 'apt-get', 'update');
    system @cmd;
}

my $file_info = collect_files();

if (!%{$file_info}) {
    die
"$progname: unable to find sources files.\nDid you forget to run apt-get update (or add --update to this command)?";
}

foreach my $site (sort keys %{$file_info}) {
    foreach my $suite (sort keys %{ $file_info->{$site} }) {
        foreach my $comp (qw(main contrib non-free)) {
            if (exists $file_info->{$site}{$suite}{$comp}) {
                if (!$opt_quiet) {
                    print "Reverse Build-depends in ${comp}:\n";
                    print "------------------------------\n\n";
                }
                findreversebuilddeps($package,
                    $file_info->{$site}{$suite}{$comp});
            }
        }
    }
}

=head1 LICENSE

This code is copyright by Patrick Schoenfeld
<schoenfeld@debian.org>, all rights reserved.
This program comes with ABSOLUTELEY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.

=head1 AUTHOR

Patrick Schoenfeld <schoenfeld@debian.org>

=cut
