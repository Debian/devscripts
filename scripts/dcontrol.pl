#!/usr/bin/perl
# vim:sw=4:sta:

#   dcontrol - Query Debian control files across releases and architectures
#   Copyright (C) 2009 Christoph Berg <myon@debian.org>
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

use strict;
use warnings;
use File::Basename;
use Getopt::Long qw(:config gnu_getopt);

BEGIN {
    # Load the URI::Escape and LWP::UserAgent modules safely
    my $progname = basename($0,'.pl');
    eval { require URI::Escape; };
    if ($@) {
       if ($@ =~ /^Can\'t locate URI\/Escape\.pm/) {
           die "$progname: you must have the liburi-perl package installed\nto use this script\n";
       }
       die "$progname: problem loading the URI::Escape module:\n  $@\nHave you installed the liburi-perl package?\n";
    }
    import URI::Escape;

    eval { require LWP::UserAgent; };
    if ($@) {
       my $progname = basename $0;
       if ($@ =~ /^Can\'t locate LWP/) {
           die "$progname: you must have the libwww-perl package installed\nto use this script\n";
       }
       die "$progname: problem loading the LWP::UserAgent module:\n  $@\nHave you installed the libwww-perl package?\n";
    }
    import LWP::UserAgent;
}

# global variables

my $progname = basename($0,'.pl');  # the '.pl' is for when we're debugging
my $modified_conf_msg;
my $dcontrol_url;
my $opt;

my $ua = LWP::UserAgent->new(agent => "$progname ###VERSION###");
$ua->env_proxy();

# functions

sub usage {
    print <<"EOT";
Usage: $progname [-sd] package[modifiers] [...]

Query package and source control files for all Debian distributions.

Options:
    -s --show-suite  Add headers for distribution the control file is from
    -d --debug       Print URL queried

Modifiers:
    =version         Exact version match
    \@architecture    Query this architecture
    /[archive:][suite][/component]
                     Restrict to archive (debian, debian-backports,
		     debian-security, debian-volatile), suite (always
		     codenames, with the exception of experimental), and/or
		     component (main, updates/main, ...). Use // if the suite
		     name contains slashes.

By default, all versions, suites, and architectures are queried.
Use \@source for source packages. \@binary returns no source packages.
Refer to $dcontrol_url for currently supported values.

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOT
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2009 by Christoph Berg <myon\@debian.org>.
All rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

sub apt_get {
    my ($arg) = @_;
    unless ($arg =~ /^([\w.+-]+)/) {
	die "$arg does not start with a valid package name\n";
    }
    my $url = "$dcontrol_url?package=" . uri_escape($1);
    if ($arg =~ /=([\w~:.+-]+)/) {
	$url .= "&version=" . uri_escape($1);
    }
    if ($arg =~ /@([\w.-]+)/) {
	$url .= "&architecture=$1";
    }
    if ($arg =~ m!/([\w-]*):([\w/-]*)//([\w/-]*)!) {
	$url .= "&archive=$1&suite=$2&component=$3";
    } elsif ($arg =~ m!/([\w/-]*)//([\w/-]*)!) {
	$url .= "&suite=$1&component=$2";
    } elsif ($arg =~ m!/([\w-]*):([\w-]*)/([\w/-]*)!) {
	$url .= "&archive=$1&suite=$2&component=$3";
    } elsif ($arg =~ m!/([\w-]*):([\w-]*)!) {
	$url .= "&archive=$1&suite=$2";
    } elsif ($arg =~ m!/([\w-]*)/([\w/-]*)!) {
	$url .= "&suite=$1&component=$2";
    } elsif ($arg =~ m!/([\w\/-]+)!) {
	$url .= "&suite=$1";
    }
    if ($opt->{'show-suite'}) {
	$url .= "&annotate=yes";
    }
    print "$url\n" if $opt->{debug};
    my $response = $ua->get ($url);
    if ($response->is_success) {
	print $response->content . "\n";
    } else {
	die $response->status_line;
    }
}

# main program

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DCONTROL_URL' => 'https://qa.debian.org/cgi-bin/dcontrol',
		       );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
	$shell_cmd .= "$var='$config_vars{$var}';\n";
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $dcontrol_url = $config_vars{'DCONTROL_URL'};
}

# handle options
GetOptions(
    "d|debug"      =>  \$opt->{'debug'},
    "s|show-suite" =>  \$opt->{'show-suite'},
    "h|help"       =>  \$opt->{'help'},
    "V|version"    =>  \$opt->{'version'},
)
    or die "$progname: unrecognised option. Run $progname --help for more details.\n";

if ($opt->{'help'}) { usage(); exit 0; }
if ($opt->{'version'}) { version(); exit 0; }
if ($opt->{'no-conf'}) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}

if (! @ARGV) {
    usage();
    exit 1;
}

# handle arguments
while (my $arg = shift @ARGV) {
    apt_get ($arg);
}

=head1 NAME

dcontrol -- Query package and source control files for all Debian distributions

=head1 SYNOPSIS

=over

=item B<dcontrol> [I<options>] I<package>[I<modifiers>] ...

=back

=head1 DESCRIPTION

B<dcontrol> queries a remote database of Debian binary and source package
control files. It can be thought of as an B<apt-cache> webservice that also
operates for distributions and architectures different from the local machine.

=head1 MODIFIERS

Like B<apt-cache>, packages can be suffixed by modifiers:

=over 4

=item B<=>I<version>

Exact version match

=item B<@>I<architecture>

Query this only architecture. Use B<@source> for source packages,
B<@binary> excludes source packages.

=item B</>[I<archive>B<:>][I<suite>][B</>I<component>]

Restrict to I<archive> (debian, debian-backports, debian-security,
debian-volatile), I<suite> (always codenames, with the exception of
experimental), and/or I<component> (main, updates/main, ...). Use two slashes
(B<//>) to separate suite and component if the suite name contains slashes.
(Component can be left empty.)

=back

By default, all versions, suites, and architectures are queried. Refer to
B<https://qa.debian.org/cgi-bin/dcontrol> for currently supported values.

=head1 OPTIONS

=over 4

=item B<-s>, B<--show-suites>

Add headers showing which distribution the control file is from.

=item B<-d>, B<--debug>

Print URL queried.

=item B<-h>, B<--help>

Show a help message.

=item B<-V>, B<--version>

Show version information.

=back

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables.  Command line options can be used to override
configuration file settings.  Environment variable settings are
ignored for this purpose.  The currently recognised variable is:

=over 4

=item DCONTROL_URL

URL to query. Default is B<https://qa.debian.org/cgi-bin/dcontrol>.

=back

=head1 AUTHOR

This program is Copyright (C) 2009 by Christoph Berg <myon@debian.org>.

This program is licensed under the terms of the GPL, either version 2
of the License, or (at your option) any later version.

=head1 SEE ALSO

B<apt-cache>(1)
