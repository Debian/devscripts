#!/usr/bin/perl

# who-permits-upload - Retrieve permissions granted to Debian Maintainers (DM)
# Copyright (C) 2012 Arno Töll <arno@debian.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


use strict;
use Dpkg::Control;
use LWP::UserAgent;
use Encode::Locale;
use Encode;
use Getopt::Long;
use constant {TYPE_PACKAGE => "package", TYPE_UID => "uid", TYPE_SPONSOR => "sponsor"};
use constant {SPONSOR_FINGERPRINT => 0, SPONSOR_NAME => 1};
use List::Util qw(first);

our $DM_URL = "https://ftp-master.debian.org/dm.txt";
our $KEYRING = "/usr/share/keyrings/debian-keyring.gpg:/usr/share/keyrings/debian-maintainers.gpg";
our $TYPE = "package";
our $GPG = first { !system('sh', '-c', "command -v $_ >/dev/null 2>&1") } qw(gpg2 gpg);
our ($HELP, @ARGUMENTS, @DM_DATA, %GPG_CACHE);

binmode STDIN, ':encoding(console_in)';
binmode STDOUT, ':encoding(console_out)';
binmode STDERR, ':encoding(console_out)';

=encoding utf8

=head1 NAME

who-permits-upload - look-up Debian Maintainer access control lists

=head1 SYNOPSIS

B<who-permits-upload> [B<-h>] [B<-s> I<keyring>] [B<-d> I<dm_url>] [B<-s> I<search_type>] I<query> [I<query> ...]

=head1 DESCRIPTION

B<who-permits-upload> looks up the given Debian Maintainer (DM) upload permissions
from ftp-master.debian.org and parses them in a human readable way. The tool can
search by DM name, sponsor (the person who granted the permission) and by package.

=head1 OPTIONS

=over 4

=item B<--dmfile=>I<dm_url>, B<-d> I<dm_url>

Retrieve the DM permission file from the supplied URL. When this option is not
present, the default value I<https://ftp-master.debian.org/dm.txt> is used.

=item B<--help>, B<-h>

Display a usage summary and exit.

=item B<--keyring=>I<keyring>, B<-s> I<keyring>

Use the supplied GnuPG keyrings to look-up GPG fingerprints from the DM permission
file. When not present, the default Debian Developer and Maintainer keyrings are used
(I</usr/share/keyrings/debian-keyring.gpg> and
I</usr/share/keyrings/debian-maintainers.gpg>, installed by the I<debian-keyring>
package).

Separate keyrings with a colon ":".

=item B<--search=>I<search_type>, B<-s> I<search_type>

Modify the look-up behavior. This influences the
interpretation of the I<query> argument. Supported search types are:

=over 4

=item B<package>

Search for a source package name. This is also the default when B<--search> is omitted.
Since package names are unique, this will return given ACLs - if any - for a
single package.

=item B<uid>

Search for a Debian Maintainer. This should be (a fraction of) a name. It will
return all ACLs assigned to matching maintainers.

=item B<sponsor>

Search for a sponsor (i.e. a Debian Developer) who granted DM permissions. This
will return all ACLs given by the supplied developer.

Note that this is an expensive operation which may take some time.

=back

=item I<query>

A case sensitive argument to be looked up in the ACL permission file. The exact
interpretation of this argument is dependent by the B<--search> argument.

This argument can be repeated.

=back

=head1 EXIT VALUE

=over 4

=item 0Z<>

Success

=item 1Z<>

An error occurred

=item 2Z<>

The command line was not understood

=back

=head1 EXAMPLES

=over 4

=item who-permits-upload --search=sponsor arno@debian.org

Search for all DM upload permissions given by the UID "arno@debian.org". Note,
that only primary UIDs will match.

=item who-permits-upload -s=sponsor "Arno Töll"

Same as above, but use a full name instead.

=item who-permits-upload apache2

Look up who gave upload permissions for the apache2 source package.

=item who-permits-upload --search=uid "Paul Tagliamonte"

Look up all DM upload permissions given to "Paul Tagliamonte".

=back

=head1 AUTHOR

B<who-permits-upload> was written by Arno Töll <arno@debian.org> and is licensed
under the terms of the General Public License (GPL) version 2 or later.

=head1 SEE ALSO

B<gpg>(1), B<gpg2>(1), B<who-uploads>(1)

S<I<https://lists.debian.org/debian-devel-announce/2012/09/msg00008.html>>

=cut


GetOptions ("help|h" => \$HELP,
    "keyring|k=s" => \$KEYRING,
    "dmfile|d=s" => \$DM_URL,
    "search|s=s" => \$TYPE,
    );
# pop positionals
@ARGUMENTS = @ARGV;

$TYPE = lc($TYPE);
if ($TYPE eq 'package')
{
    $TYPE = TYPE_PACKAGE;
}
elsif ($TYPE eq 'uid')
{
    $TYPE = TYPE_UID;
}
elsif ($TYPE eq 'sponsor')
{
    $TYPE = TYPE_SPONSOR;
}
else
{
    usage();
}

if ($HELP)
{
    usage();
}

if (not @ARGUMENTS)
{
    usage();
}

sub usage
{
    print STDERR ("Usage: $0 [-h][-s KEYRING][-d DM_URL][-s SEARCH_TYPE] QUERY [QUERY ...]\n");
    print STDERR "Retrieve permissions granted to Debian Maintainers (DM)\n";
    print STDERR "\n";
    print STDERR "-h, --help\n";
    print STDERR "\t\t\tDisplay this usage summary and exit\n";
    print STDERR "-k, --keyring=KEYRING\n";
    print STDERR "\t\t\tUse the supplied keyring file(s) instead of the default\n";
    print STDERR "\t\t\tkeyring. Separate arguments by a colon (\":\")\n";
    print STDERR "-d, --dmfile=DM_URL\n";
    print STDERR "\t\t\tRetrieve DM permissions from the supplied URL.\n";
    print STDERR "\t\t\tDefault is https://ftp-master.debian.org/dm.txt\n";
    print STDERR "-s, --search=SEARCH_TYPE\n";
    print STDERR "\t\t\tSupplied QUERY arguments are interpreted as:\n";
    print STDERR "\t\t\tpackage name when SEARCH_TYPE is \"package\" (default)\n";
    print STDERR "\t\t\tDM user name id when SEARCH_TYPE is \"uid\"\n";
    print STDERR "\t\t\tsponsor user id when SEARCH_TYPE is \"sponsor\"\n";
    exit 2;
}

sub leave
{
    my $reason = shift;
    chomp $reason;
    print STDERR "$reason\n";
    exit 1;
}

sub lookup_fingerprint
{
    my $fingerprint = shift;
    my $uid = "";

    if (exists $GPG_CACHE{$fingerprint})
    {
        return $GPG_CACHE{$fingerprint};
    }

    my @gpg_arguments;
    foreach my $keyring (split(":", "$KEYRING"))
    {
        if (! -f $keyring)
        {
            leave("Keyring $keyring is not accessible");
        }
        push(@gpg_arguments, ("--keyring", $keyring));
    }
    push(@gpg_arguments, ("--no-options", "--no-auto-check-trustdb", "--no-default-keyring", "--list-key", "--with-colons", encode(locale => $fingerprint)));
    open(CMD, '-|', $GPG, @gpg_arguments) || leave "$GPG: $!\n";
    binmode CMD, ':utf8';
    while (my $l = <CMD>)
    {
        if ($l =~ /^pub/)
        {
            $uid = $l;
            # Consume the rest of the output to avoid a potential SIGPIPE when closing CMD
            my @junk = <CMD>;
            last;
        }
    }
    my @fields = split(":", $uid);
    $uid = $fields[9];
    close(CMD) || leave("gpg returned an error looking for $fingerprint: ". ($? >> 8));

    $GPG_CACHE{$fingerprint} = $uid;

    return $uid;
}

sub parse_data
{
    my $raw_data = shift;
    my $parser = Dpkg::Control->new(type => CTRL_UNKNOWN, allow_duplicate => 1);
    open(my $fh, '+<:utf8', \$raw_data) || leave('unable to read dm data: '.$!);
    my @dm_data = ();

    while ($parser->parse($fh))
    {
        foreach my $package (split(/,/, $parser->{Allow}))
        {
            if ($package =~ m/([a-z0-9\+\-\.]+)\s+\((\w+)\)/s)
            {
                my @package_row = ($1, $parser->{Fingerprint}, $parser->{Uid}, $2, SPONSOR_FINGERPRINT);
                push(@dm_data, \@package_row);
            }
        }
    }
    return @dm_data;
}


sub find_matching_row
{
    my $pattern = shift;
    my $type = shift;
    my @return_rows;
    foreach my $package (@DM_DATA)
    {
        # $package is an array ref in the format
        # (package, dm_fingerprint, dm_uid, sponsor_fingerprint callback)
        push(@return_rows, $package) if ($type eq TYPE_PACKAGE && $pattern eq $package->[0]);
        push(@return_rows, $package) if ($type eq TYPE_UID &&  $package->[2] =~ m/$pattern/);
        if ($type eq TYPE_SPONSOR)
        {
            # the sponsor function is a key id so far, mark we looked it up
            # already
            $package->[3] = lookup_fingerprint($package->[3]);
            $package->[4] = SPONSOR_NAME;
            if ($package->[3] =~ m/$pattern/)
            {
                push(@return_rows, $package);
            }
        }
    }
    return @return_rows;
}

my $http = LWP::UserAgent->new;
$http->timeout(10);
$http->env_proxy;

my $response = $http->get($DM_URL);
if ($response->is_success)
{
    @DM_DATA = parse_data($response->content);
}
else
{
    leave "Could not retrieve DM file: $DM_URL Server returned: " . $response->status_line;
}

foreach my $argument (@ARGUMENTS)
{
    $argument = decode(locale => $argument);
    my @rows = find_matching_row($argument, $TYPE);
    if (not @rows)
    {
        leave("No $TYPE matches $argument");
    }
    foreach my $row (@rows)
    {
        # $package is an array ref in the format
        # (package, dm_fingerprint, dm_uid, sponsor_fingerprint, sponsor_type_flag)
        my $sponsor = $row->[3];
        if ($row->[4] != SPONSOR_NAME)
        {
            $row->[3] = lookup_fingerprint($row->[3]);
        }
        printf("Package: %s DM: %s Sponsor: %s\n", $row->[0], $row->[2], $row->[3] );
    }
}
