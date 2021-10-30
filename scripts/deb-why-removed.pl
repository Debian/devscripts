#!/usr/bin/perl
#
# Copyright © 2017-2019 Guillem Jover <guillem@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use File::Basename;
use File::Path qw(make_path);
use File::Copy qw(cp);
use File::Spec;
use Getopt::Long qw(:config posix_default no_ignorecase);
use HTTP::Tiny;
use Dpkg::Index;
use Devscripts::Output;

my $VERSION = '0.0';
my ($PROGNAME) = $0 =~ m{(?:.*/)?([^/]*)};

my %url_map = ('debian' => 'https://ftp-master.debian.org/removals-full.822');
my $default_url_origin = 'debian';

#
# Functions
#

sub version {
    print "$PROGNAME $VERSION (devscripts ###VERSION###)\n";
}

sub usage {
    print <<HELP;
Usage: $PROGNAME [<option>...] <package>...

Options:
  -u, --url URL     URL to the removals deb822 file list (defaults to
                      <$url_map{$default_url_origin}>).
      --no-refresh  Do not refresh the cached removals file even if old.
  -h, -?, --help    Print this help text.
      --version     Print the version.
HELP
}

# XXX: DAK produces broken output, fix it up here before we process it.
#
# The two current bogus instances are, at least two fused paragraphs, and
# bogus "sh: 0: getcwd() failed: No such file or directory" command output
# interpersed within the file.
sub fixup_broken_metadata {
    my $cachefile = shift;
    my $para_sep  = 1;

    open my $fh_old, '<', $cachefile
      or ds_error("cannot open cache file $cachefile for fixup");
    open my $fh_new, '>', "$cachefile.new"
      or ds_error("cannot open cache file $cachefile.new for fixup");
    while (my $line = <$fh_old>) {
        if ($line =~ m/^\s*$/) {
            $para_sep = 1;
        } elsif (not $para_sep and $line =~ m/^Date:/) {
            # XXX: We assume each paragraph starts with a Date: field, and
            # inject the missing newline.
            print {$fh_new} "\n";
        } else {
            $para_sep = 0;
        }

        # XXX: Fixup shell output detritus.
        if ($line =~ s/sh: 0: getcwd\(\) failed: No such file or directory//) {
            # Remove the trailing line so that the next line gets folded back
            # into this one.
            chomp $line;
        }

        print {$fh_new} $line;
    }
    close $fh_new or ds_error("cannot write cache file $cachefile.new");
    close $fh_old;

    # Preserve the original mtime so that mirroring works.
    my ($atime, $mtime) = (stat $cachefile)[8, 9];
    utime $atime, $mtime, "$cachefile.new";

    rename "$cachefile.new", $cachefile
      or ds_error("cannot replace cache file with fixup version");
}

sub cache_file {
    my ($url, $cachefile) = @_;

    cp($url, $cachefile) or ds_error("cannot copy removal metadata: $!");
    fixup_broken_metadata($cachefile);
}

sub cache_http {
    my ($url, $cachefile) = @_;

    my $http = HTTP::Tiny->new(verify_SSL => 1);
    my $resp = $http->mirror($url, $cachefile);

    unless ($resp->{success}) {
        ds_error(
            "cannot fetch removal metadata: $resp->{status} $resp->{reason}");
    }

    if ($resp->{status} != 304) {
        fixup_broken_metadata($cachefile);
    }
}

#
# Main program
#

my $opts;

GetOptions(
    'url|u=s'    => \$opts->{'url'},
    'no-refresh' => \$opts->{'no-refresh'},
    'help|h|?'   => sub { usage();   exit 0 },
    'version'    => sub { version(); exit 0 },
  )
  or die "\nUsage: $PROGNAME [<option>...] <package>...\n"
  . "Run $PROGNAME --help for more details.\n";

unless (@ARGV) {
    ds_error('need at least one package name as an argument');
}

my $url = $opts->{url} // $default_url_origin;
$url = $url_map{$url} if $url_map{$url};

my $cachehome = $ENV{XDG_CACHE_HOME};
$cachehome ||= File::Spec->catdir($ENV{HOME}, '.cache') if length $ENV{HOME};
if (length $cachehome == 0) {
    ds_error("unknown user home, cannot download removal metadata");
}
my $cachedir = File::Spec->catdir($cachehome, 'devscripts', 'deb-why-removed');
my $cachefile = File::Spec->catfile($cachedir, basename($url));

if (not -d $cachedir) {
    make_path($cachedir);
}

if (not -e $cachefile or (-e _ and not $opts->{'no-refresh'})) {
    # Normalize the URL.
    $url =~ s{^file://}{};

    # Cache the file locally.
    if (-e $url) {
        cache_file($url, $cachefile);
    } else {
        cache_http($url, $cachefile);
    }
}

my $meta
  = Dpkg::Index->new(
    get_key_func => sub { return $_[0]->{Sources} // $_[0]->{Binaries} // '' },
  );

$meta->load($cachefile, compression => 0);

STANZA: foreach my $entry ($meta->get) {
    foreach my $pkg (@ARGV) {
        # XXX: Skip bogus entries with no indexable fields.
        next
          if not defined $entry->{Sources}
          and not defined $entry->{Binaries};

        next
          if ($entry->{Sources} // '')  !~ m/\Q$pkg\E_/
          && ($entry->{Binaries} // '') !~ m/\Q$pkg\E_/;

        print $entry->output();
        print "\n";
        next STANZA;
    }
}

=encoding utf8

=head1 NAME

deb-why-removed - shows the reason a package was removed from the archive

=head1 SYNOPSIS

B<deb-why-removed> [I<option>...] I<package>...

=head1 DESCRIPTION

This program will download the removals metadata from the archive, search
and print the entries within for a source or binary package name match.

=head1 OPTIONS

=over 4

=item B<-u>, B<--url> I<URL>

URL to the archive removals deb822-formatted file list.
This can be either an actual URL (https://, http://, file://), an pathname
or an origin name.
Currently the only origin name known is B<debian>.

=item B<--no-refresh>

Do not refresh the cached removals file even if there is a newer version
in the archive.

=item B<-h>, B<-?>, B<--help>

Show a help message and exit.

=item B<--version>

Show the program version.

=back

=head1 FILES

=over 4

=item I<cachedir>B</devscripts/deb-why-removed/>

This directory contains the cached removal files downloaded from the archive.
I<cachedir> will be either B<$XDG_CACHE_HOME> or if that is not defined
B<$HOME/.cache/>.

=back

=head1 SEE ALSO

L<https://ftp-master.debian.org/#removed>

=cut
