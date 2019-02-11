
=head1 NAME

Devscripts::Uscan::Config - uscan configuration object

=head1 SYNOPSIS

  use Devscripts::Uscan::Config;
  my $config = Devscripts::Uscan::Config->new->parse;

=head1 DESCRIPTION

Uscan configuration object. It can scan configuration files
(B</etc/devscripts.conf> and B<~/.devscripts>) and command line arguments.

=cut

package Devscripts::Uscan::Config;

use strict;

use Devscripts::Uscan::Output;
use Exporter 'import';
use Moo;

extends 'Devscripts::Config';

our $CURRENT_WATCHFILE_VERSION = 4;

use constant default_user_agent => "Debian uscan"
  . ($main::uscan_version ? " $main::uscan_version" : '');

our @EXPORT = (qw($CURRENT_WATCHFILE_VERSION));

# I - ACCESSORS

# Options + default values

has bare                     => (is => 'rw');
has check_dirname_level      => (is => 'rw');
has check_dirname_regex      => (is => 'rw');
has compression              => (is => 'rw');
has copyright_file           => (is => 'rw');
has destdir                  => (is => 'rw');
has download                 => (is => 'rw');
has download_current_version => (is => 'rw');
has download_debversion      => (is => 'rw');
has download_version         => (is => 'rw');
has exclusion                => (is => 'rw');
has log                      => (is => 'rw');
has orig                     => (is => 'rw');
has package                  => (is => 'rw');
has pasv                     => (is => 'rw');

# repack to .tar.$zsuffix if 1
has repack     => (is => 'rw');
has safe       => (is => 'rw');
has signature  => (is => 'rw');
has symlink    => (is => 'rw');
has timeout    => (is => 'rw');
has user_agent => (is => 'rw');
has uversion   => (is => 'rw');
has watchfile  => (is => 'rw');

# II - Options

use constant keys => [
    # 2.1 - Simple parameters that can be set in ~/.devscripts and command line
    [
        'check-dirname-level=s', 'DEVSCRIPTS_CHECK_DIRNAME_LEVEL',
        qr/^[012]$/,             1
    ],
    [
        'check-dirname-regex=s', 'DEVSCRIPTS_CHECK_DIRNAME_REGEX',
        undef,                   'PACKAGE(-.+)?'
    ],
    ['dehs!', 'USCAN_DEHS_OUTPUT', sub { $dehs = $_[1]; 1 }],
    [
        'destdir=s',
        'USCAN_DESTDIR',
        sub {
            if (-d $_[1]) {
                $_[0]->destdir($_[1]) if (-d $_[1]);
                return 1;
            }
            return (0,
                "The directory to store downloaded files(\$destdir): $_[1]");
        },
        '..'
    ],
    ['exclusion!', 'USCAN_EXCLUSION', 'bool',    1],
    ['timeout=i',  'USCAN_TIMEOUT',   qr/^\d+$/, 20],
    [
        'user-agent|useragent=s',
        'USCAN_USER_AGENT',
        qr/\w/,
        sub {
            default_user_agent;
        }
    ],
    ['repack', 'USCAN_REPACK', 'bool'],
    # 2.2 - Simple command line args
    ['bare', undef, 'bool', 0],
    ['compression=s'],
    ['copyright-file=s'],
    ['download-current-version', undef, 'bool'],
    ['download-version=s'],
    ['download-debversion|dversion=s'],
    ['log', undef, 'bool'],
    ['package=s'],
    ['uversion|upstream-version=s'],
    ['watchfile=s'],
    # 2.3 - More complex options

    # "download" and its aliases
    [
        undef,
        'USCAN_DOWNLOAD',
        sub {
            return (1, 'Bad USCAN_DOWNLOAD value, skipping')
              unless ($_[1] =~ /^(?:yes|(no))$/i);
            $_[0]->download(0) if $1;
            return 1;
        }
    ],
    [
        'download|d+',
        undef,
        sub {
            $_[1] =~ s/^yes$/1/i;
            $_[1] =~ s/^no$/0/i;
            return (0, "Wrong number of -d")
              unless ($_[1] =~ /^[0123]$/);
            $_[0]->download($_[1]);
            return 1;
        },
        1
    ],
    [
        'force-download',
        undef,
        sub {
            $_[0]->download(2);
        }
    ],
    ['no-download', undef, sub { $_[0]->download(0); return 1; }],
    ['overwrite-download', undef, sub { $_[0]->download(3) }],

    # "pasv"
    [
        'pasv|passive',
        'USCAN_PASV',
        sub {
            return $_[0]->pasv('default')
              unless ($_[1] =~ /^(yes|0|1|no)$/);
            $_[0]->pasv({
                    yes => 1,
                    1   => 1,
                    no  => 0,
                    0   => 0,
                }->{$1});
            return 1;
        },
        0
    ],

    # "safe" and "symlink" and their aliases
    ['safe|report', 'USCAN_SAFE', 'bool', 0],
    [
        'report-status',
        undef,
        sub {
            $_[0]->safe(1);
            $_[0]->{verbose} ||= 1;
        }
    ],
    ['copy',   undef, sub { $_[0]->symlink('copy') }],
    ['rename', undef, sub { $_[0]->symlink('rename') if ($_[1]); 1; }],
    [
        'symlink!',
        'USCAN_SYMLINK',
        sub {
            $_[0]->symlink(
                  $_[1] =~ /^(no|0|rename)$/   ? $1
                : $_[1] =~ /^(yes|1|symlink)$/ ? 'symlink'
                :                                'no'
            );
            return 1;
        },
        'symlink'
    ],
    # "signature" and its aliases
    ['signature!',                   undef, 'bool', 1],
    ['skipsignature|skip-signature', undef, sub     { $_[0]->signature(-1) }],
    # "verbose" and its aliases
    ['debug', undef, sub { $verbose = 2 }],
    ['no-verbose', undef, sub { $verbose = 0; return 1; }],
    [
        'verbose|v!', 'USCAN_VERBOSE',
        sub { $verbose = ($_[1] =~ /^(?:1|yes)$/i ? 1 : 0) }
    ],
    # Display version
    [
        'version',
        undef,
        sub {
            if ($_[1]) { $_[0]->version; exit 0 }
        }
    ]];

use constant rules => [
    sub {
        my $self = shift;
        if ($self->package) {
            $self->download(0)
              unless ($self->download > 1);    # compatibility
            return (0,
"The --package option requires to set the --watchfile option, too."
            ) unless defined $self->watchfile;
        }
        $self->download(0) if ($self->safe == 1 and $self->download == 1);
        return 1;
    },
    # $signature: -1 = no downloading signature and no verifying signature,
    #              0 = no downloading signature but verifying signature,
    #              1 = downloading signature and verifying signature
    sub {
        my $self = shift;
        $self->signature(-1)
          if $self->download == 0;    # Change default 1 -> -1
        return 1;
    },
    sub {
        if (defined $_[0]->watchfile and @ARGV) {
            return (0, "Can't have directory arguments if using --watchfile");
        }
        return 1;
    },
];

# help methods
sub usage {
    my ($self) = @_;
    print <<"EOF";
Usage: $progname [options] [dir ...]
  Process watch files in all .../debian/ subdirs of those listed (or the
  current directory if none listed) to check for upstream releases.
Options:
    --no-conf, --noconf
                   Don\'t read devscripts config files;
                   must be the first option given
    --no-verbose   Don\'t report verbose information.
    --verbose, -v  Report verbose information.
    --debug, -vv   Report verbose information including the downloaded
                   web pages as processed to STDERR for debugging.
    --dehs         Send DEHS style output (XML-type) to STDOUT, while
                   send all other uscan output to STDERR.
    --no-dehs      Use only traditional uscan output format (default)
    --download, -d
                   Download the new upstream release (default)
    --force-download, -dd
                   Download the new upstream release, even if up-to-date
                   (may not overwrite the local file)
    --overwrite-download, -ddd
                   Download the new upstream release, even if up-to-date
                  (may overwrite the local file)
    --no-download, --nodownload
                   Don\'t download and report information.
		   Previously downloaded tarballs may be used.
                   Change default to --skip-signature.
    --signature    Download signature and verify (default)
    --no-signature Don\'t download signature but verify if already downloaded.
    --skip-signature
                   Don\'t bother download signature nor verify it.
    --safe, --report
                   avoid running unsafe scripts by skipping both the repacking
                   of the downloaded package and the updating of the new
                   source tree.  Change default to --no-download and
                   --skip-signature.
    --report-status (= --safe --verbose)
    --download-version VERSION
                   Specify the version which the upstream release must
                   match in order to be considered, rather than using the
                   release with the highest version
    --download-debversion VERSION
		   Specify the Debian package version to download the
		   corresponding upstream release version.  The
		   dversionmangle and uversionmangle rules are
		   considered.
    --download-current-version
                   Download the currently packaged version
    --check-dirname-level N
                   Check parent directory name?
                   N=0   never check parent directory name
                   N=1   only when $progname changes directory (default)
                   N=2   always check parent directory name
    --check-dirname-regex REGEX
                   What constitutes a matching directory name; REGEX is
                   a Perl regular expression; the string \`PACKAGE\' will
                   be replaced by the package name; see manpage for details
                   (default: 'PACKAGE(-.+)?')
    --destdir      Path of directory to which to download.
    --package PACKAGE
                   Specify the package name rather than examining
                   debian/changelog; must use --upstream-version and
                   --watchfile with this option, no directory traversing
                   will be performed, no actions (even downloading) will be
                   carried out
    --upstream-version VERSION
                   Specify the current upstream version in use rather than
                   parsing debian/changelog to determine this
    --watchfile FILE
                   Specify the watch file rather than using debian/watch;
                   no directory traversing will be done in this case
    --bare         Disable all site specific special case codes to perform URL
                   redirections and page content alterations.
    --no-exclusion Disable automatic exclusion of files mentioned in
                   debian/copyright field Files-Excluded and Files-Excluded-*
    --pasv         Use PASV mode for FTP connections
    --no-pasv      Don\'t use PASV mode for FTP connections (default)
    --no-symlink   Don\'t rename nor repack upstream tarball
    --timeout N    Specifies how much time, in seconds, we give remote
                   servers to respond (default 20 seconds)
    --user-agent, --useragent
                   Override the default user agent string
    --log          Record md5sum changes of repackaging
    --help         Show this message
    --version      Show version information

Options passed on to mk-origtargz:
    --symlink      Create a correctly named symlink to downloaded file (default)
    --rename       Rename instead of symlinking
    --copy         Copy instead of symlinking
    --repack       Repack downloaded archives to change compression
    --compression [ gzip | bzip2 | lzma | xz ]
                   When the upstream sources are repacked, use compression COMP
                   for the resulting tarball (default: gzip)
    --copyright-file FILE
                   Remove files matching the patterns found in FILE

Default settings modified by devscripts configuration files:
$self->{modified_conf_msg}
EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version $main::uscan_version
This code is copyright 1999-2006 by Julian Gilbey and 2018 by Xavier Guimard,
all rights reserved.
Original code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

1;
__END__
=head1 SEE ALSO

L<uscan>, L<Devscripts::Config>

=head1 AUTHOR

B<uscan> was originally written by Christoph Lameter
E<lt>clameter@debian.orgE<gt> (I believe), modified by Julian Gilbey
E<lt>jdg@debian.orgE<gt>. HTTP support was added by Piotr Roszatycki
E<lt>dexter@debian.orgE<gt>. B<uscan> was rewritten in Perl by Julian Gilbey.
Xavier Guimard E<lt>yadd@debian.orgE<gt> rewrote uscan in object
oriented Perl.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2006 by Julian Gilbey <jdg@debian.org>,
2018 by Xavier Guimard <yadd@debian.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
