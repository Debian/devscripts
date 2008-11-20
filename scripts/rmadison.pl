#!/usr/bin/perl -w
# vim:sw=4:sta:

# Copyright (C) 2006, 2007, 2008 Christoph Berg <myon@debian.org>
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
use File::Basename;
use Getopt::Long;

BEGIN {
    # Load the URI::Escape module safely
    eval { require URI::Escape; };
    if ($@) {
       my $progname = basename $0;
       if ($@ =~ /^Can\'t locate URI\/Escape\.pm/) {
           die "$progname: you must have the liburi-perl package installed\nto use this script\n";
       }
       die "$progname: problem loading the URI::Escape module:\n  $@\nHave you installed the liburi-perl package?\n";
    }
    import URI::Escape;
}

my $VERSION = '0.3';

sub version($) {
    my ($fd) = @_;
    print $fd "rmadison $VERSION (devscripts ###VERSION###) (C) 2006, 2007 Christoph Berg <myon\@debian.org>\n";
}

sub usage($$) {
    my ($fd, $exit) = @_;
    print <<EOT;
Usage: rmadison [OPTION] PACKAGE[...]
Display information about PACKAGE(s).

  -a, --architecture=ARCH    only show info for ARCH(s)
  -b, --binary-type=TYPE     only show info for binary TYPE
  -c, --component=COMPONENT  only show info for COMPONENT(s)
  -g, --greaterorequal       show buildd 'dep-wait pkg >= {highest version}' info
  -G, --greaterthan          show buildd 'dep-wait pkg >> {highest version}' info
  -h, --help                 show this help and exit
  -s, --suite=SUITE          only show info for this suite
  -S, --source-and-binary    show info for the binary children of source pkgs
  -t, --time                 show projectb snapshot date
  -u, --url=URL              use URL instead of http://qa.debian.org/madison.php

  --noconf, --no-conf        don\'t read devscripts configuration files

ARCH, COMPONENT and SUITE can be comma (or space) separated lists, e.g.
    --architecture=m68k,i386
EOT
    exit $exit;
}

my $params;
my %url_map = (
    'debian' => "http://qa.debian.org/madison.php",
    'qa' => "http://qa.debian.org/madison.php",
    'myon' => "http://qa.debian.org/~myon/madison.php",
    'bpo' => "http://www.backports.org/cgi-bin/madison.cgi",
    'debug' => "http://debug.debian.net/cgi-bin/madison.cgi",
    'ubuntu' => "http://people.ubuntu.com/~ubuntu-archive/madison.cgi",
);

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

   foreach my $envvar (@config_vars) {
	$envvar =~ /^RMADISON_URL_MAP_([^=]*)=(.*)$/ or next;
	$url_map{lc($1)}=$2;
    }
}

Getopt::Long::config('bundling');
unless (GetOptions(
    '-a=s'                =>  \$params->{'architecture'},
    '--architecture=s'    =>  \$params->{'architecture'},
    '-b=s'                =>  \$params->{'binary-type'},
    '--binary-type=s'     =>  \$params->{'binary-type'},
    '-c=s'                =>  \$params->{'component'},
    '--component=s'       =>  \$params->{'component'},
    '-g'                  =>  \$params->{'greaterorequal'},
    '--greaterorequal'    =>  \$params->{'greaterorequal'},
    '-G'                  =>  \$params->{'greaterthan'},
    '--greaterthan'       =>  \$params->{'greaterthan'},
    '-h'                  =>  \$params->{'help'},
    '--help'              =>  \$params->{'help'},
    '-r'                  =>  \$params->{'regex'},
    '--regex'             =>  \$params->{'regex'},
    '-s=s'                =>  \$params->{'suite'},
    '--suite=s'           =>  \$params->{'suite'},
    '-S'                  =>  \$params->{'source-and-binary'},
    '--source-and-binary' =>  \$params->{'source-and-binary'},
    '-t'                  =>  \$params->{'time'},
    '--time'              =>  \$params->{'time'},
    '-u=s'                =>  \$params->{'url'},
    '--url=s'             =>  \$params->{'url'},
    '--version'           =>  \$params->{'version'},
)) {
    usage(\*STDERR, 1);
};

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
if ($params->{regex}) {
    print STDERR "E: rmadison does not support the -r --regex option.\n";
    exit 1;
}
if ($params->{greaterorequal} and $params->{greaterthan}) {
    print STDERR "E: -g/--greaterorequal and -G/--greaterthan are mutually exclusive.\n";
    exit 1;
}

my @args;
push @args, "a=$params->{'architecture'}" if $params->{'architecture'};
push @args, "b=$params->{'binary-type'}" if $params->{'binary-type'};
push @args, "c=$params->{'component'}" if $params->{'component'};
push @args, "g" if $params->{'greaterorequal'};
push @args, "G" if $params->{'greaterthan'};
push @args, "s=$params->{'suite'}" if $params->{'suite'};
push @args, "S" if $params->{'source-and-binary'};
push @args, "t" if $params->{'time'};

my $url = $params->{'url'} ? $params->{'url'} : "debian";
my @url = split /,/, $url;

foreach my $url (@url) {
    print "$url:\n" if @url > 1;
    $url = $url_map{$url} if $url_map{$url};
    my @cmd = -x "/usr/bin/curl" ? qw/curl -s -S/ : qw/wget -q -O -/;
    system @cmd, $url . "?package=" . join("+", map { uri_escape($_) } @ARGV) . "&text=on&" . join ("&", @args);
}

=pod

=head1 NAME

rmadison -- Remotely query the Debian archive database about packages

=head1 SYNOPSIS

=over

=item B<rmadison> [I<OPTIONS>] I<PACKAGE> ...

=back

=head1 DESCRIPTION

B<dak ls> queries the Debian archive database ("projectb") and
displays which package version is registered per architecture/component/suite.
The CGI at B<http://qa.debian.org/madison.php> provides that service without
requiring ssh access to ftp-master.debian.org or the mirror on
merkel.debian.org. This script, B<rmadison>, is a command line frontend to
this CGI.

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

=item B<-S>, B<--source-and-binary>

show info for the binary children of source pkgs

=item B<-t>, B<--time>

show projectb snapshot and reload time (not supported by all archives)

=item B<-u>, B<--url=>I<URL>[B<,>I<URL...>]

use I<URL> for the query. Supported shorthands are
 B<debian> or B<qa> http://qa.debian.org/madison.php (the default)
 B<bpo> http://www.backports.org/cgi-bin/madison.cgi
 B<debug> http://debug.debian.net/cgi-bin/madison.cgi
 B<ubuntu> http://people.ubuntu.com/~ubuntu-archive/madison.cgi

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

=back

=head1 NOTES

B<dak ls> also supports B<-r>, B<--regex> to treat I<PACKAGE> as a regex. Since
that can easily DoS the database ("-r ."), this option is not supported by the
CGI and rmadison.

B<dak ls> was formerly called B<madison>.

The protocol used by rmadison is fairly simple, the CGI accepts query the
parameters a, b, c, g, G, s, S, t, and package. The parameter text is passed to
enable plain-text output.

=head1 SEE ALSO

madison-lite(1), dak(1).

=head1 AUTHOR

rmadison and http://qa.debian.org/madison.php were written by Christoph Berg
<myon@debian.org>. dak was written by
James Troup <james@nocrew.org>, Anthony Towns <ajt@debian.org>, and others.

=cut
