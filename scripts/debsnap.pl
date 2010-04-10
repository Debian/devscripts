#!/usr/bin/perl -w

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

use LWP::Simple;
use JSON -support_by_pp;
use File::Basename;
use File::Path qw/remove_tree/;

my $progname = basename($0);
my $modified_conf_msg = '';
my %config_vars = ();
my $force_actions = 0;

my $numshifts = 0;

my $package = '';
my $pkgversion = '';
my $destdir = '';

sub fatal($;$);
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
    print <<"EOF";
$progname [options] <package name> [package version]

Automatically downloads packages from snapshot.debian.net

The following options are supported:
    -h, --help                          Shows this help message
    --version                           Shows information about version
    -v, --verbose                       Be verbose
    -d <destination directory>,
    --destdir=<destination directory>   Directory for retrieved packages
                                        Default is ./source-<package name>
    -f, --force                         Force overwriting an existing
                                        destdir

Default settings modified by devscripts configuration files or command-line
options:
$modified_conf_msg
EOF
    exit 0;
}

sub fetch_json_page
{
    my ($json_url) = @_;

    # download the json page:
    verbose "Getting json $json_url\n";
    my $content = get $json_url;
    my $json = new JSON;

    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($content);

    return $json_text;
}

sub read_conf
{
    # Most of the code in this sub has been stol^Wadapted from debuild.pl

    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    %config_vars = (
        'DEBSNAP_VERBOSE' => 'no',
        'DEBSNAP_DESTDIR' => '',
        'DEBSNAP_BASE_URL' => 'http://snapshot-dev.debian.org',
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

    # print STDERR "Running shell command:\n$shell_cmd";
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    # print STDERR "Shell output:\n${shell_out}End shell output\n";
    my @othervars;
    (@config_vars{keys %config_vars}, @othervars) = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'DEBSNAP_VERBOSE'} =~ /^(yes|no)$/
    or $config_vars{'DEBSNAP_VERBOSE'} = 'no';

    # Lastly, command-line options have priority
    while (my $arg=shift) {
        my $opt = '';
        $numshifts++;

        $arg =~/^(-v|--verbose)$/ and $config_vars{DEBSNAP_VERBOSE} = 'yes';

        if ($arg =~/^(-d|--destdir)$/) {
            $opt = shift;
            unless (defined ($opt) and ($opt !~ /^-.*$/)) {
                fatal "$arg requires an argument,\nrun $progname --help for usage information.";
            }
            $config_vars{DEBSNAP_DESTDIR} = $opt;
        }
        elsif ($arg =~/^--destdir=(.*)$/) {
            $arg = '--destdir';
            $opt = $1;
            $config_vars{DEBSNAP_DESTDIR} = $opt;
        }

        $arg =~ /^(-f|--force)$/ and $force_actions = 1;

        $arg =~ /^(-h|--help)$/ and usage();
        $arg eq '--version' and version();

        $arg eq '--' and last;
        $arg !~ /^-.*$/ and unshift(@ARGV, $arg), last;
    }

    foreach my $var (sort keys %config_vars) {
        if ($config_vars{$var} ne $config_default{$var}) {
            $modified_conf_msg .= "  $var=$config_vars{$var}\n";
        }
    }

    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;
}

sub fatal($;$)
{
    my ($pack, $file, $line);
    ($pack, $file, $line) = caller();
    my $msg = shift;
    ($msg = "$progname: fatal error at line $line:\n$msg\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;

    my $code = shift;
    if (defined $code) {
        $! = $code;
    }
    else {
        $! = 1;
    }

    die $msg;
}

sub verbose($)
{
    (my $msg = "@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    print "$msg" if $config_vars{DEBSNAP_VERBOSE} eq 'yes';
}

###
# Main program
###
read_conf(@ARGV);
# TODO: check if something less hacky can be done.
if (@ARGV) {
    splice(@ARGV, 0, $numshifts);

    $package = shift;
    $pkgversion = shift;
} else {
    usage();
}
$package eq '' and usage();
$pkgversion ||= '';

# TODO: more compact version?
if ($config_vars{DEBSNAP_DESTDIR}) {
    $destdir = $config_vars{DEBSNAP_DESTDIR};
}
else {
    $destdir = "source-$package";
}

my $baseurl = "$config_vars{DEBSNAP_BASE_URL}/mr/package/$package/";
if (-d $destdir) {
    if ($force_actions) {
        my $verbose = 1 if $config_vars{DEBSNAP_VERBOSE} eq 'yes';
        remove_tree($destdir, { verbose => $verbose });
        mkdir($destdir);
    }
    else {
        fatal "Destination dir $destdir already exists.\nPlease (re)move it first, or use --force to overwrite.";
    }
}
else {
    mkdir($destdir);
}

eval {
    my $json_text = fetch_json_page($baseurl);
    # iterate over each available version in the JSON structure:
    foreach my $version(@{$json_text->{result}}){
        if ($pkgversion) {
            next if $version->{version} ne $pkgversion;
        }

        my $src_json = fetch_json_page("http://snapshot-dev.debian.org/mr/package/$package/$version->{version}/srcfiles");

        foreach my $file(@{$src_json->{result}}){
            my $hash = $file->{hash};
            my $file = fetch_json_page("http://snapshot-dev.debian.org/mr/file/$hash/info")->{result}[0];

            #my %file_hash = ();
            #$file_hash{path} = $file->{path};
            #$file_hash{run} = $file->{run};
            #$file_hash{name} = $file->{name};
            #$file_hash{size} = $file->{size};
            #while (my($k, $v) = each (%file_hash)){
            #    print "$k => $v\n";
            #}

            my $file_url = "http://snapshot-dev.debian.org/file/$hash";
            verbose "Getting file $file->{name}: $file_url";
            eval {
                getstore($file_url, "$destdir/$file->{name}");
            };
            if ($@) {
                fatal("$@", 2);
            }

            # http://snapshot-dev.debian.org/file/7b4d5b2f24af4b5a299979134bc7f6d7b1eaf875
            # http://snapshot-dev.debian.org/mr/file/7b4d5b2f24af4b5a299979134bc7f6d7b1eaf875/info
            # "result": [{"path": "/pool/main/p/p0f", "run": "20070806T000000Z", "archive_name": "debian", "name": "p0f_2.0.8.orig.tar.gz", "size": 136877}]
        }
    }
};

# catch crashes:
if($@){
    fatal "$@";
}
