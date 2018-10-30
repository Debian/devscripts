
=head1 NAME

Devscripts::Uscan::WatchFile - watchfile object for L<uscan>

=head1 SYNOPSIS

  use Devscripts::Uscan::Config;
  use Devscripts::Uscan::WatchFile;
  
  my $config = Devscripts::Uscan::Config->new({
    # Uscan config parameters. Example:
    destdir => '..',
  });

  # You can use Devscripts::Uscan::FindFiles to find watchfiles
  
  my $wf = Devscripts::Uscan::WatchFile->new({
      config      => $config,
      package     => $package,
      pkg_dir     => $pkg_dir,
      pkg_version => $version,
      watchfile   => $watchfile,
  });
  return $wf->status if ( $wf->status );
  
  # Do the job
  return $wf->process_lines;

=head1 DESCRIPTION

Uscan class to parse watchfiles.

=head1 METHODS

=head2 new() I<(Constructor)>

Parse watch file and creates L<Devscripts::Uscan::WatchLine> objects for
each line.

=head3 Required parameters

=over

=item config: L<Devscripts::Uscan::Config> object

=item package: Debian package name

=item pkg_dir: Working directory

=item pkg_version: Current Debian package version

=back

=head2 Main accessors

=over

=item watchlines: ref to the array that contains watchlines objects

=item watch_version: format version of the watchfile

=back

=head2 process_lines()

Method that launches Devscripts::Uscan::WatchLine::process() on each watchline.

=head1 SEE ALSO

L<uscan>, L<Devscripts::Uscan::WatchLine>, L<Devscripts::Uscan::Config>,
L<Devscripts::Uscan::FindFiles>

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

package Devscripts::Uscan::WatchFile;

use strict;
use Devscripts::Uscan::Downloader;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::WatchLine;
use File::Copy qw/copy move/;
use List::Util qw/first/;
use Moo;

use constant {
    ANY_VERSION => '(?:[-_]?(\d[\-+\.:\~\da-zA-Z]*))',
    ARCHIVE_EXT => '(?i)(?:\.(?:tar\.xz|tar\.bz2|tar\.gz|zip|tgz|tbz|txz))',
    DEB_EXT     => '(?:[\+~](debian|dfsg|ds|deb)(\.)?(\d+)?$)',
};
use constant SIGNATURE_EXT => ARCHIVE_EXT . '(?:\.(?:asc|pgp|gpg|sig|sign))';

# Required new() parameters
has config      => (is => 'rw', required => 1);
has package     => (is => 'ro', required => 1);    # Debian package
has pkg_dir     => (is => 'ro', required => 1);
has pkg_version => (is => 'ro', required => 1);
has bare        => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->config->bare });
has download => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->config->download });
has downloader => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        Devscripts::Uscan::Downloader->new({
            timeout => $_[0]->config->timeout,
            agent   => $_[0]->config->user_agent,
            pasv    => $_[0]->config->pasv,
            destdir => $_[0]->config->destdir,
        });
    },
);
has signature => (
    is       => 'rw',
    required => 1,
    lazy     => 1,
    default  => sub { $_[0]->config->signature });
has watchfile => (is => 'ro', required => 1);    # usually debian/watch

# Internal attributes
has origcount     => (is => 'rw');
has origtars      => (is => 'rw', default => sub { [] });
has status        => (is => 'rw', default => sub { 0 });
has watch_version => (is => 'rw');
has watchlines    => (is => 'rw', default => sub { [] });

# Values shared between lines
has shared => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        {
            bare                        => $_[0]->bare,
            components                  => [],
            common_newversion           => undef,
            common_mangled_newversion   => undef,
            download                    => $_[0]->download,
            download_version            => undef,
            origcount                   => undef,
            origtars                    => [],
            previous_download_available => undef,
            previous_newversion         => undef,
            previous_newfile_base       => undef,
            previous_sigfile_base       => undef,
            signature                   => $_[0]->signature,
            uscanlog                    => undef,
        };
    },
);
has keyring => (
    is      => 'ro',
    default => sub { Devscripts::Uscan::Keyring->new });

sub BUILD {
    my ($self, $args) = @_;
    my $watch_version = 0;
    my $nextline;
    $dehs_tags = {};

    uscan_verbose "Process watch file at: $args->{watchfile}\n"
      . "    package = $args->{package}\n"
      . "    version = $args->{pkg_version}\n"
      . "    pkg_dir = $args->{pkg_dir}";

    $self->origcount(0);    # reset to 0 for each watch file
    unless (open WATCH, $args->{watchfile}) {
        uscan_warn "could not open $args->{watchfile}: $!";
        return 1;
    }

    while (<WATCH>) {
        next if /^\s*\#/;
        next if /^\s*$/;
        s/^\s*//;

      CHOMP:

        # Reassemble lines split using \
        chomp;
        if (s/(?<!\\)\\$//) {
            if (eof(WATCH)) {
                uscan_warn
                  "$args->{watchfile} ended with \\; skipping last line";
                $self->status(1);
                last;
            }
            if ($watch_version > 3) {

                # drop leading \s only if version 4
                $nextline = <WATCH>;
                $nextline =~ s/^\s*//;
                $_ .= $nextline;
            } else {
                $_ .= <WATCH>;
            }
            goto CHOMP;
        }

        # "version" must be the first field
        if (!$watch_version) {

            # Looking for "version" field.
            if (/^version\s*=\s*(\d+)(\s|$)/) {    # Found
                $watch_version = $1;

                # Note that version=1 watchfiles have no "version" field so
                # authorizated values are >= 2 and <= CURRENT_WATCHFILE_VERSION
                if (   $watch_version < 2
                    or $watch_version
                    > $Devscripts::Uscan::Config::CURRENT_WATCHFILE_VERSION) {
                    # "version" field found but has no authorizated value
                    uscan_warn
"$args->{watchfile} version number is unrecognised; skipping watch file";
                    last;
                }

                # Next line
                next;
            }

            # version=1 is deprecated
            else {
                uscan_warn
                  "$args->{watchfile} is an obsolete version 1 watch file;\n"
                  . "   please upgrade to a higher version\n"
                  . "   (see uscan(1) for details).";
                $watch_version = 1;
            }
        }

        # "version" is fixed, parsing lines now

        # Are there any warnings from this part to give if we're using dehs?
        dehs_output if ($dehs);

        # Handle shell \\ -> \
        s/\\\\/\\/g if $watch_version == 1;

        # Handle @PACKAGE@ @ANY_VERSION@ @ARCHIVE_EXT@ substitutions
        s/\@PACKAGE\@/$args->{package}/g;
        s/\@ANY_VERSION\@/ANY_VERSION/ge;
        s/\@ARCHIVE_EXT\@/ARCHIVE_EXT/ge;
        s/\@SIGNATURE_EXT\@/SIGNATURE_EXT/ge;
        s/\@DEB_EXT\@/DEB_EXT/ge;

        push @{ $self->watchlines }, Devscripts::Uscan::WatchLine->new({
                # Shared between lines
                config     => $self->config,
                downloader => $self->downloader,
                shared     => $self->shared,
                keyring    => $self->keyring,

                # Other parameters
                line          => $_,
                pkg           => $self->package,
                pkg_dir       => $self->pkg_dir,
                pkg_version   => $self->pkg_version,
                watch_version => $watch_version,
                watchfile     => $self->watchfile,
        });
    }

    close WATCH
      or $self->status(1),
      uscan_warn "problems reading $$args->{watchfile}: $!";
    $self->watch_version($watch_version);
}

sub process_lines {
    my ($self) = shift;
    foreach (@{ $self->watchlines }) {

        # search newfile and newversion
        my $res = $_->process;
        $self->status($res);
    }
    return $self->{status};
}

1;
