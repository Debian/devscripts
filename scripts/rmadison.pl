#!/usr/bin/perl
# vim: set ai shiftwidth=4 tabstop=4 expandtab:

# Copyright (C) 2006-2013 Christoph Berg <myon@debian.org>
#           (C) 2010 Uli Martens <uli@youam.net>
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

use strict;
use warnings;
use File::Basename;
use Getopt::Long qw(:config bundling permute no_getopt_compat);

BEGIN {
    pop @INC if $INC[-1] eq '.';
    # Load the URI::Escape module safely
    eval { require URI::Escape; };
    if ($@) {
        my $progname = basename $0;
        if ($@ =~ /^Can\'t locate URI\/Escape\.pm/) {
            die
"$progname: you must have the liburi-perl package installed\nto use this script\n";
        }
        die
"$progname: problem loading the URI::Escape module:\n  $@\nHave you installed the liburi-perl package?\n";
    }
    import URI::Escape;
}

my $VERSION = '0.4';

sub version($) {
    my ($fd) = @_;
    print $fd <<EOT;
rmadison $VERSION (devscripts ###VERSION###)
(C) 2006-2010 Christoph Berg <myon\@debian.org>
(C) 2010 Uli Martens <uli\@youam.net>
EOT
}

my %url_map = (
    'debian' => "https://api.ftp-master.debian.org/madison",
    'new'    => "https://api.ftp-master.debian.org/madison?s=new",
    'qa'     => "https://qa.debian.org/madison.php",
    'ubuntu' => "https://people.canonical.com/~ubuntu-archive/madison.cgi",
    'udd'    => 'https://qa.debian.org/cgi-bin/madison.cgi',
);
my $default_url = 'debian';
if (system('dpkg-vendor', '--is', 'ubuntu') == 0) {
    $default_url = 'ubuntu';
}

sub usage($$) {
    my ($fd, $exit) = @_;
    my @urls = split /,/, $default_url;
    my $url
      = (@urls > 1)
      ? join(', and ', join(', ', @urls[0 .. $#urls - 1]), $urls[-1])
      : $urls[0];

    print $fd <<EOT;
Usage: rmadison [OPTION] PACKAGE[...]
Display information about PACKAGE(s).

  -a, --architecture=ARCH    only show info for ARCH(s)
  -b, --binary-type=TYPE     only show info for binary TYPE
  -c, --component=COMPONENT  only show info for COMPONENT(s)
  -g, --greaterorequal       show buildd 'dep-wait pkg >= {highest version}' info
  -G, --greaterthan          show buildd 'dep-wait pkg >> {highest version}' info
  -h, --help                 show this help and exit
  -r, --regex                treat PACKAGE as a regex [not supported everywhere]
  -s, --suite=SUITE          only show info for this suite
  -S, --source-and-binary    show info for the binary children of source pkgs
  -t, --time                 show projectb snapshot date
  -u, --url=URL              use URL instead of $url

  --noconf, --no-conf        don\'t read devscripts configuration files

ARCH, COMPONENT and SUITE can be comma (or space) separated lists, e.g.
    --architecture=m68k,i386

Aliases for URLs:
EOT
    foreach my $alias (sort keys %url_map) {
        print $fd "\t$alias\t$url_map{$alias}\n";
    }
    exit $exit;
}

my $params;
my $default_arch;
my $ssl_ca_file;
my $ssl_ca_path;

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    shift;
} else {
    # We don't have any predefined variables, but allow any of the form
    # RMADISON_URL_MAP_SHORTCODE=URL
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my @config_vars = ();

    my $shell_cmd;
    # Set defaults
    $shell_cmd .= qq[unset `set | grep "^RMADISON_" | cut -d= -f1`;\n];
    $shell_cmd .= 'for file in ' . join(" ", @config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    $shell_cmd .= 'for var in `set | grep "^RMADISON_" | cut -d= -f1`; do ';
    $shell_cmd .= 'eval echo $var=\$$var; done;' . "\n";
    # Read back values
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars = split /\n/, $shell_out, -1;

    foreach my $confvar (@config_vars) {
        if ($confvar =~ /^RMADISON_URL_MAP_([^=]*)=(.*)$/) {
            $url_map{ lc($1) } = $2;
        } elsif ($confvar =~ /^RMADISON_DEFAULT_URL=(.*)$/) {
            $default_url = $1;
        } elsif ($confvar =~ /^RMADISON_ARCHITECTURE=(.*)$/) {
            $default_arch = $1;
        } elsif ($confvar =~ /^RMADISON_SSL_CA_FILE=(.*)$/) {
            $ssl_ca_file = $1;
        } elsif ($confvar =~ /^RMADISON_SSL_CA_PATH=(.*)$/) {
            $ssl_ca_path = $1;
        }
    }
}

unless (
    GetOptions(
        '-a=s'                => \$params->{'architecture'},
        '--architecture=s'    => \$params->{'architecture'},
        '-b=s'                => \$params->{'binary-type'},
        '--binary-type=s'     => \$params->{'binary-type'},
        '-c=s'                => \$params->{'component'},
        '--component=s'       => \$params->{'component'},
        '-g'                  => \$params->{'greaterorequal'},
        '--greaterorequal'    => \$params->{'greaterorequal'},
        '-G'                  => \$params->{'greaterthan'},
        '--greaterthan'       => \$params->{'greaterthan'},
        '-h'                  => \$params->{'help'},
        '--help'              => \$params->{'help'},
        '-r'                  => \$params->{'regex'},
        '--regex'             => \$params->{'regex'},
        '-s=s'                => \$params->{'suite'},
        '--suite=s'           => \$params->{'suite'},
        '-S'                  => \$params->{'source-and-binary'},
        '--source-and-binary' => \$params->{'source-and-binary'},
        '-t'                  => \$params->{'time'},
        '--time'              => \$params->{'time'},
        '-u=s'                => \$params->{'url'},
        '--url=s'             => \$params->{'url'},
        '--version'           => \$params->{'version'},
    )
) {
    usage(\*STDERR, 1);
}

if ($params->{help}) {
    usage(\*STDOUT, 0);
}
if ($params->{version}) {
    version(\*STDOUT);
    exit 0;
}

unless (@ARGV) {
    print STDERR "E: need at least one package name as an argument.\n";
    exit 1;
}
if ($params->{greaterorequal} and $params->{greaterthan}) {
    print STDERR
      "E: -g/--greaterorequal and -G/--greaterthan are mutually exclusive.\n";
    exit 1;
}

my @args;

if ($params->{'architecture'}) {
    push @args, "a=$params->{'architecture'}";
} elsif ($default_arch) {
    push @args, "a=$default_arch";
}
push @args, "b=$params->{'binary-type'}" if $params->{'binary-type'};
push @args, "c=$params->{'component'}"   if $params->{'component'};
push @args, "g"                          if $params->{'greaterorequal'};
push @args, "G"                          if $params->{'greaterthan'};
push @args, "r"                          if $params->{'regex'};
push @args, "s=$params->{'suite'}"       if $params->{'suite'};
push @args, "S"                          if $params->{'source-and-binary'};
push @args, "t"                          if $params->{'time'};

my $url = $params->{'url'} ? $params->{'url'} : $default_url;
my @url = split /,/, $url;

my $status = 0;

# Strip arch qualifiers from the package name, to help those that are feeding
# in output from other commands
s/:.*// for (@ARGV);

foreach my $url (@url) {
    print "$url:\n" if @url > 1;
    $url = $url_map{$url} if $url_map{$url};
    my @cmd;
    my @ssl_errors;
    if (-x "/usr/bin/curl") {
        @cmd = qw/curl -f -s -S -L/;
        push @cmd, "--cacert", $ssl_ca_file if $ssl_ca_file;
        push @cmd, "--capath", $ssl_ca_path if $ssl_ca_path;
        push @ssl_errors, (60, 77);
    } else {
        @cmd = qw/wget -q -O -/;
        push @cmd, "--ca-certificate=$ssl_ca_file" if $ssl_ca_file;
        push @cmd, "--ca-directory=$ssl_ca_path"   if $ssl_ca_path;
        push @ssl_errors, 5;
    }
    system @cmd,
        $url
      . (($url =~ m/\?/) ? '&' : '?')
      . "package="
      . join("+", map { uri_escape($_) } @ARGV)
      . "&text=on&"
      . join("&", @args);
    my $rc = $? >> 8;
    if ($rc != 0) {
        if (grep { $_ == $rc } @ssl_errors) {
            die
"Problem with SSL CACERT check:\n Have you installed the ca-certificates package?\n";
        }
        $status = 1;
    }
}

exit $status;

__END__

=head1 NAME

rmadison -- Remotely query the Debian archive database about packages

=head1 SYNOPSIS

=over

=item B<rmadison> [I<OPTIONS>] I<PACKAGE> ...

=back

=head1 DESCRIPTION

B<dak ls> queries the Debian archive database ("projectb") and
displays which package version is registered per architecture/component/suite.
The CGI at B<https://qa.debian.org/madison.php> provides that service without
requiring SSH access to ftp-master.debian.org or the mirror on
mirror.ftp-master.debian.org. This script, B<rmadison>, is a command line
frontend to this CGI.

=head1 OPTIONS

=over

=item B<-a>, B<--architecture=>I<ARCH>

only show info for ARCH(s)

=item B<-b>, B<--binary-type=>I<TYPE>

only show info for binary TYPE

=item B<-c>, B<--component=>I<COMPONENT>

only show info for COMPONENT(s)

=item B<-g>, B<--greaterorequal>

show buildd 'dep-wait pkg >= {highest version}' info

=item B<-G>, B<--greaterthan>

show buildd 'dep-wait pkg >> {highest version}' info

=item B<-h>, B<--help>

show this help and exit

=item B<-s>, B<--suite=>I<SUITE>

only show info for this suite

=item B<-r>, B<--regex>

treat PACKAGE as a regex

B<Note:> Since B<-r> can easily DoS the database ("-r ."), this option is not
supported by the CGI on qa.debian.org and most other installations.

=item B<-S>, B<--source-and-binary>

show info for the binary children of source pkgs

=item B<-t>, B<--time>

show projectb snapshot and reload time (not supported by all archives)

=item B<-u>, B<--url=>I<URL>[B<,>I<URL> ...]

use I<URL> for the query. Supported shorthands are
 B<debian> https://api.ftp-master.debian.org/madison
 B<new> https://api.ftp-master.debian.org/madison?s=new
 B<qa> https://qa.debian.org/madison.php
 B<ubuntu> https://people.canonical.com/~ubuntu-archive/madison.cgi
 B<udd> https://qa.debian.org/cgi-bin/madison.cgi

See the B<RMADISON_URL_MAP_> variable below for a method to add
new shorthands.

=item B<--version>

show version and exit

=item B<--no-conf>, B<--noconf>

don't read the devscripts configuration files

=back

ARCH, COMPONENT and SUITE can be comma (or space) separated lists, e.g.
--architecture=m68k,i386

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables. Command line options can be used to override
configuration file settings. Environment variable settings are
ignored for this purpose. The currently recognised variables are:

=over 4

=item B<RMADISON_URL_MAP_>I<SHORTHAND>=I<URL>

Add an entry to the set of shorthand URLs listed above. I<SHORTHAND> should
be replaced with the shorthand form to be used to refer to I<URL>.

Multiple shorthand entries may be specified by using multiple
B<RMADISON_URL_MAP_*> variables.

=item B<RMADISON_DEFAULT_URL>=I<URL>

Set the default URL to use unless overridden by a command line option.
For Debian this defaults to debian. For Ubuntu this defaults to ubuntu.

=item B<RMADISON_ARCHITECTURE>=I<ARCH>

Set the default architecture to use unless overridden by a command line option.
To run an unrestricted query when B<RMADISON_ARCHITECTURE> is set, use
B<--architecture='*'>.

=item B<RMADISON_SSL_CA_FILE>=I<FILE>

Use the specified CA file instead of the default CA bundle for curl/wget,
passed as --cacert to curl, and as --ca-certificate to wget.

=item B<RMADISON_SSL_CA_PATH>=I<PATH>

Use the specified CA directory instead of the default CA bundle for curl/wget,
passed as --capath to curl, and as --ca-directory to wget.

=back

=head1 NOTES

B<dak ls> was formerly called B<madison>.

The protocol used by rmadison is fairly simple, the CGI accepts query the
parameters a, b, c, g, G, r, s, S, t, and package. The parameter text is passed to
enable plain-text output.

=head1 SEE ALSO

B<dak>(1), B<madison-lite>(1)

=head1 AUTHOR

rmadison and https://qa.debian.org/madison.php were written by Christoph Berg
<myon@debian.org>. dak was written by
James Troup <james@nocrew.org>, Anthony Towns <ajt@debian.org>, and others.

=cut
