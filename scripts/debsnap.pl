#!/usr/bin/perl

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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use Getopt::Long qw(:config gnu_getopt);
use File::Basename;
use Cwd qw/cwd abs_path/;
use File::Path qw/make_path/;
use Dpkg::Version;

my $progname = basename($0);

eval {
    require LWP::Simple;
    require LWP::UserAgent;
    no warnings;
    $LWP::Simple::ua = LWP::UserAgent->new(agent => 'LWP::UserAgent/Devscripts/###VERSION###');
};
if ($@) {
    if ($@ =~ m/Can\'t locate LWP/) {
	die "$progname: Unable to run: the libwww-perl package is not installed";
    } else {
	die "$progname: Unable to run: Couldn't load LWP::Simple: $@";
    }
}

eval {
    require JSON;
};
if ($@) {
    if ($@ =~ m/Can\'t locate JSON/) {
	die "$progname: Unable to run: the libjson-perl package is not installed";
    } else {
	die "$progname: Unable to run: Couldn't load JSON: $@";
    }
}

my $modified_conf_msg = '';
my %config_vars = ();

my %opt;
my $package = '';
my $pkgversion = '';
my $warnings = 0;

sub fatal($);
sub verbose($);

sub version
{
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2010 by David Paleino <dapal\@debian.org>.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License v3 or, at your option, any later version.
EOF
    exit 0;
}

sub usage
{
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

sub fetch_json_page
{
    my ($json_url) = @_;

    # download the json page:
    verbose "Getting json $json_url\n";
    my $content = LWP::Simple::get($json_url);
    return unless defined $content;
    my $json = JSON->new();

    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->decode($content);

    return $json_text;
}

sub read_conf
{
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    %config_vars = (
	'DEBSNAP_VERBOSE' => 'no',
	'DEBSNAP_DESTDIR' => '',
	'DEBSNAP_BASE_URL' => 'http://snapshot.debian.org',
    );

    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    $shell_cmd .= qq[unset `set | grep "^DEBSNAP_" | cut -d= -f1`;\n];
    foreach my $var (keys %config_vars) {
	$shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

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

sub have_file($$)
{
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

sub fatal($)
{
    my ($pack, $file, $line);
    ($pack, $file, $line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    $! = 1;
    die $msg;
}

sub verbose($)
{
    (my $msg = "@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    print "$msg" if $opt{verbose};
}

###
# Main program
###
read_conf(@ARGV);
Getopt::Long::Configure('gnu_compat');
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opt, 'verbose|v', 'destdir|d=s', 'force|f', 'help|h', 'version', 'binary', 'architecture|a=s@') || exit 1;

usage(0) if $opt{help};
usage(1) unless @ARGV;
$package = shift;
if (@ARGV) {
    my $version = shift;
    $pkgversion = Dpkg::Version->new($version, check => 1);
    fatal "Invalid version '$version'" unless $pkgversion;
}

$package eq '' && usage(1);

$opt{binary} ||= $opt{architecture};

my $baseurl;
if ($opt{binary}) {
    $opt{destdir} ||= "binary-$package";
    $baseurl = "$opt{baseurl}/mr/binary/$package/";
} else {
    $opt{destdir} ||= "source-$package";
    $baseurl = "$opt{baseurl}/mr/package/$package/";
}

if (-d $opt{destdir}) {
    unless ($opt{force} || cwd() eq abs_path($opt{destdir})) {
	fatal "Destination dir $opt{destdir} already exists.\nPlease (re)move it first, or use --force to overwrite.";
    }
}
make_path($opt{destdir});

my $json_text = fetch_json_page($baseurl);
unless ($json_text && @{$json_text->{result}}) {
    fatal "Unable to retrieve information for $package from $baseurl.";
}

if ($opt{binary}) {
    foreach my $version (@{$json_text->{result}}) {
	if ($pkgversion) {
	    next if ($version->{binary_version} <=> $pkgversion);
	}

	my $src_json = fetch_json_page("$opt{baseurl}/mr/package/$version->{source}/$version->{version}/binfiles/$version->{name}/$version->{binary_version}?fileinfo=1");

	unless ($src_json) {
	    warn "$progname: No binary packages found for $package version $version->{binary_version}\n";
	    $warnings++;
	}

	foreach my $result (@{$src_json->{result}}) {
	    if ($opt{architecture} && @{$opt{architecture}}) {
		next unless (grep { $_ eq $result->{architecture} } @{$opt{architecture}});
	    }
	    my $hash = $result->{hash};
	    my $fileinfo = @{$src_json->{fileinfo}{$hash}}[0];
	    my $file_url = "$opt{baseurl}/file/$hash";
	    my $file_name = basename($fileinfo->{name});
	    if (!have_file("$opt{destdir}/$file_name", $hash)) {
		verbose "Getting file $file_name: $file_url";
		LWP::Simple::getstore($file_url, "$opt{destdir}/$file_name");
	    }
	}
    }
}
else {
    foreach my $version (@{$json_text->{result}}) {
	if ($pkgversion) {
	    next if ($version->{version} <=> $pkgversion);
	}

	my $src_json = fetch_json_page("$baseurl/$version->{version}/srcfiles?fileinfo=1");
	unless ($src_json) {
	    warn "$progname: No source files found for $package version $version->{version}\n";
	    $warnings++;
	}

	foreach my $hash (keys %{$src_json->{fileinfo}}) {
	    my $fileinfo = $src_json->{fileinfo}{$hash};
	    my $file_name;
	    # fileinfo may match multiple files (e.g., orig tarball for iceweasel 3.0.12)
	    foreach my $info (@$fileinfo) {
		if ($info->{name} =~ m/^${package}/) {
		    $file_name = $info->{name};
		    last;
		}
	    }
	    unless ($file_name) {
		warn "$progname: No files with hash $hash matched '${package}'\n";
		$warnings++;
		next;
	    }
	    my $file_url = "$opt{baseurl}/file/$hash";
	    $file_name = basename($file_name);
	    if (!have_file("$opt{destdir}/$file_name", $hash)) {
		verbose "Getting file $file_name: $file_url";
		LWP::Simple::getstore($file_url, "$opt{destdir}/$file_name");
	    }
	}
    }
}

if ($warnings) {
    exit 2;
}
exit 0;
