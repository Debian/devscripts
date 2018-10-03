#!/usr/bin/perl
# vim: set ai shiftwidth=4 tabstop=4 expandtab:

# Copyright © 2010, David Paleino <d.paleino@gmail.com>,
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use Getopt::Long qw(:config bundling permute no_getopt_compat);
use File::Basename;
use Cwd qw/cwd abs_path/;
use File::Path qw/make_path/;
use Dpkg::Version;
use JSON::PP;

my $progname = basename($0);

eval {
    require LWP::Simple;
    require LWP::UserAgent;
    no warnings;
    $LWP::Simple::ua = LWP::UserAgent->new(
        agent => 'LWP::UserAgent/Devscripts/###VERSION###');
    $LWP::Simple::ua->env_proxy();
};
if ($@) {
    if ($@ =~ m/Can\'t locate LWP/) {
        die
          "$progname: Unable to run: the libwww-perl package is not installed";
    } else {
        die "$progname: Unable to run: Couldn't load LWP::Simple: $@";
    }
}

my $modified_conf_msg = '';
my %config_vars       = ();

my %opt = (architecture => []);
my $package = '';
my $pkgversion;
my $firstversion;
my $lastversion;
my $warnings = 0;

sub fatal($);
sub verbose($);

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2010 by David Paleino <dapal\@debian.org>.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License v3 or, at your option, any later version.
EOF
    exit 0;
}

sub usage {
    my $rc = shift;
    print <<"EOF";
$progname [options] <package name> [package version]

Automatically downloads packages from snapshot.debian.org

The following options are supported:
    -h, --help                          Shows this help message
    --version                           Shows information about version
    -v, --verbose                       Be verbose
    -d <destination directory>,
    --destdir=<destination directory>   Directory for retrieved packages
                                        Default is ./source-<package name>
    -f, --force                         Force overwriting an existing
                                        destdir
    --list                              Don't download but just list versions
    --binary                            Download binary packages instead of
                                        source packages
    -a <architecture>,
    --architecture <architecture>       Specify architecture of binary packages,
                                        implies --binary. May be given multiple
                                        times

Default settings modified by devscripts configuration files or command-line
options:
$modified_conf_msg
EOF
    exit $rc;
}

sub fetch_json_page {
    my ($json_url) = @_;

    # download the json page:
    verbose "Getting json $json_url\n";
    my $content = LWP::Simple::get($json_url);
    return unless defined $content;
    my $json = JSON::PP->new();

    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->decode($content);

    return $json_text;
}

sub read_conf {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    %config_vars = (
        'DEBSNAP_VERBOSE'  => 'no',
        'DEBSNAP_DESTDIR'  => '',
        'DEBSNAP_BASE_URL' => 'https://snapshot.debian.org',
    );

    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    $shell_cmd .= qq[unset `set | grep "^DEBSNAP_" | cut -d= -f1`;\n];
    foreach my $var (keys %config_vars) {
        $shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    $shell_cmd .= 'for file in ' . join(" ", @config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{ keys %config_vars } = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'DEBSNAP_VERBOSE'} =~ /^(yes|no)$/
      or $config_vars{'DEBSNAP_VERBOSE'} = 'no';

    foreach my $var (sort keys %config_vars) {
        if ($config_vars{$var} ne $config_default{$var}) {
            $modified_conf_msg .= "  $var=$config_vars{$var}\n";
        }
    }

    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $opt{verbose} = $config_vars{DEBSNAP_VERBOSE} eq 'yes';
    $opt{destdir} = $config_vars{DEBSNAP_DESTDIR};
    $opt{baseurl} = $config_vars{DEBSNAP_BASE_URL};
}

sub have_file($$) {
    my ($path, $hash) = @_;

    if (-e $path) {
        open(HASH, '-|', 'sha1sum', $path) || fatal "Can't run sha1sum: $!";
        while (<HASH>) {
            if (m/^([a-fA-F\d]{40}) /) {
                close(HASH) || fatal "sha1sum problems: $! $?";
                return $1 eq $hash;
            }
        }
    }
    return 0;
}

sub fatal($) {
    my ($pack, $file, $line);
    ($pack, $file, $line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    $! = 1;
    die $msg;
}

sub verbose($) {
    (my $msg = "@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    print "$msg" if $opt{verbose};
}

sub keep_version($) {
    my $version = shift;
    if (defined $pkgversion) {
        return version_compare_relation($pkgversion, REL_EQ, $version);
    }
    if (defined $firstversion) {
        if ($firstversion > $version) {
            verbose "skip version $version: older than first";
            return 0;
        }
    }
    if (defined $lastversion) {
        if ($lastversion < $version) {
            verbose "skip version $version: newer than last";
            return 0;
        }
    }
    return 1;
}

###
# Main program
###
read_conf(@ARGV);
Getopt::Long::Configure('gnu_compat');
Getopt::Long::Configure('no_ignore_case');
GetOptions(
    \%opt,    'verbose|v', 'destdir|d=s', 'force|f',
    'help|h', 'version',   'first=s',     'last=s',
    'list',   'binary',    'architecture|a=s@'
) || usage(1);

usage(0)  if $opt{help};
version() if $opt{version};
usage(1) unless @ARGV;
$package = shift;
if (@ARGV) {
    my $version = shift;
    $pkgversion = Dpkg::Version->new($version);
    fatal "Invalid version '$version'" unless $pkgversion->is_valid();
}

if (defined $opt{first}) {
    $firstversion = Dpkg::Version->new($opt{first});
    fatal "Invalid version '$opt{first}'" unless $firstversion->is_valid();
}

if (defined $opt{last}) {
    $lastversion = Dpkg::Version->new($opt{last});
    fatal "Invalid version '$opt{last}'" unless $lastversion->is_valid();
}

$package eq '' && usage(1);

$opt{binary} ||= @{ $opt{architecture} };

my $baseurl;
if ($opt{binary}) {
    $opt{destdir} ||= "binary-$package";
    $baseurl = "$opt{baseurl}/mr/binary/$package/";
} else {
    $opt{destdir} ||= "source-$package";
    $baseurl = "$opt{baseurl}/mr/package/$package/";
}

my $mkdir_done = 0;
my $mkDestDir  = sub {
    unless ($mkdir_done) {
        if (-d $opt{destdir}) {
            unless ($opt{force} || cwd() eq abs_path($opt{destdir})) {
                fatal
"Destination dir $opt{destdir} already exists.\nPlease (re)move it first, or use --force to overwrite.";
            }
        }

        make_path($opt{destdir});
        $mkdir_done = 1;
    }
};

my $json_text = fetch_json_page($baseurl);
unless ($json_text && @{ $json_text->{result} }) {
    fatal "Unable to retrieve information for $package from $baseurl.";
}

my @versions = @{ $json_text->{result} };
@versions
  = $opt{binary}
  ? grep { keep_version($_->{binary_version}) } @versions
  : grep { keep_version($_->{version}) } @versions;
unless (@versions) {
    warn "$progname: No matching versions found for $package\n";
    $warnings++;
}
if ($opt{list}) {
    foreach my $version (@versions) {
        if ($opt{binary}) {
            print "$version->{binary_version}\n";
        } else {
            print "$version->{version}\n";
        }
    }
} elsif ($opt{binary}) {
    foreach my $version (@versions) {
        my $src_json
          = fetch_json_page(
"$opt{baseurl}/mr/package/$version->{source}/$version->{version}/binfiles/$version->{name}/$version->{binary_version}?fileinfo=1"
          );

        unless ($src_json) {
            warn
"$progname: No binary packages found for $package version $version->{binary_version}\n";
            $warnings++;
            next;
        }

        my @results = @{ $src_json->{result} };
        if (@{ $opt{architecture} }) {
            my %archs = map { ($_ => 0) } @{ $opt{architecture} };
            @results = grep {
                exists $archs{ $_->{architecture} }
                  && ++$archs{ $_->{architecture} }
            } @results;
            my @missing = grep { $archs{$_} == 0 } sort keys %archs;
            if (@missing) {
                warn
"$progname: No binary packages found for $package version $version->{binary_version} on "
                  . join(', ', @missing) . "\n";
                $warnings++;
            }
        }
        foreach my $result (@results) {
            my $hash      = $result->{hash};
            my $fileinfo  = @{ $src_json->{fileinfo}{$hash} }[0];
            my $file_url  = "$opt{baseurl}/file/$hash";
            my $file_name = basename($fileinfo->{name});
            if (!have_file("$opt{destdir}/$file_name", $hash)) {
                verbose "Getting file $file_name: $file_url";
                $mkDestDir->();
                LWP::Simple::mirror($file_url, "$opt{destdir}/$file_name");
            }
        }
    }
} else {
    foreach my $version (@versions) {
        my $src_json
          = fetch_json_page("$baseurl$version->{version}/srcfiles?fileinfo=1");
        unless ($src_json) {
            warn
"$progname: No source files found for $package version $version->{version}\n";
            $warnings++;
            next;
        }

        # Get the dsc file and parse it to get the list of files to be
        # restored (this should fix most issues with multi-tarball
        # source packages):
        my $dsc_name;
        my $dsc_hash;
        foreach my $hash (keys %{ $src_json->{fileinfo} }) {
            my $fileinfo = $src_json->{fileinfo}{$hash};
            foreach my $info (@$fileinfo) {
                if ($info->{name} =~ m/^\Q${package}\E_.*\.dsc/) {
                    $dsc_name = $info->{name};
                    $dsc_hash = $hash;
                    last;
                }
            }
            last if $dsc_name;
        }
        unless ($dsc_name) {
            warn
"$progname: No dsc file detected for $package version $version->{version}\n";
            $warnings++;
            next;
        }

        # Retrieve the dsc file:
        my $file_url = "$opt{baseurl}/file/$dsc_hash";
        if (!have_file("$opt{destdir}/$dsc_name", $dsc_hash)) {
            verbose "Getting dsc file $dsc_name: $file_url";
            $mkDestDir->();
            LWP::Simple::mirror($file_url, "$opt{destdir}/$dsc_name");
        }

        # Get the list of files from the dsc:
        my @files;
        open my $fh, '<', "$opt{destdir}/$dsc_name"
          or die "unable to open the dsc file $opt{destdir}/$dsc_name";
        while (<$fh> !~ /^Files:/) { }
        while (<$fh> =~ /^ (\S+) (\d+) (\S+)$/) {
            my ($checksum, $size, $file) = ($1, $2, $3);
            push @files, $file;
        }
        close $fh
          or die "unable to close the dsc file";

        # Iterate over files and find the right contents:
        foreach my $file_name (@files) {
            my $file_hash;
            foreach my $hash (keys %{ $src_json->{fileinfo} }) {
                my $fileinfo = $src_json->{fileinfo}{$hash};

                foreach my $info (@{$fileinfo}) {
                    if ($info->{name} eq $file_name) {
                        $file_hash = $hash;
                        last;
                    }
                }
                last if $file_hash;
            }
            unless ($file_hash) {
                # Warning: this next statement will only move to the
                # next files, not the next package
                print
"$progname: No hash found for file $file_name needed by $package version $version->{version}\n";
                $warnings++;
                next;
            }

            my $file_url = "$opt{baseurl}/file/$file_hash";
            $file_name = basename($file_name);
            if (!have_file("$opt{destdir}/$file_name", $file_hash)) {
                verbose "Getting file $file_name: $file_url";
                $mkDestDir->();
                LWP::Simple::mirror($file_url, "$opt{destdir}/$file_name");
            }
        }
    }
}

if ($warnings) {
    exit 2;
}
exit 0;
