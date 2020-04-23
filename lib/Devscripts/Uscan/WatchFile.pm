
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
has group         => (is => 'rw', default => sub { [] });
has origcount     => (is => 'rw');
has origtars      => (is => 'rw', default => sub { [] });
has status        => (is => 'rw', default => sub { 0 });
has watch_version => (is => 'rw');
has watchlines    => (is => 'rw', default => sub { [] });

# Values shared between lines
has shared => (
    is      => 'rw',
    lazy    => 1,
    default => \&new_shared,
);

sub new_shared {
    return {
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
}
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

    my $lineNumber = 0;
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

        my $line = Devscripts::Uscan::WatchLine->new({
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
        push @{ $self->group }, $lineNumber
          if ($line->type and $line->type eq 'group');
        push @{ $self->watchlines }, $line;
        $lineNumber++;
    }

    close WATCH
      or $self->status(1),
      uscan_warn "problems reading $$args->{watchfile}: $!";
    $self->watch_version($watch_version);
}

sub process_lines {
    my ($self) = shift;
    return $self->process_group if (@{ $self->group });
    foreach (@{ $self->watchlines }) {

        # search newfile and newversion
        my $res = $_->process;
        $self->status($res) if ($res);
    }
    return $self->{status};
}

sub process_group {
    my ($self) = @_;
    # Build version
    my @cur_versions = split /\+~/, $self->pkg_version;
    my (@new_versions, @last_debian_mangled_uversions, @last_versions);
    my $download    = 0;
    my $last_shared = $self->shared;
    my $last_comp_version;
    # Isolate component and following lines
    foreach my $line (@{ $self->watchlines }) {
        if ($line->type and $line->type eq 'group') {
            $last_shared       = $self->new_shared;
            $last_comp_version = shift @cur_versions;
        }
        $line->shared($last_shared);
        $line->pkg_version($last_comp_version || 0);
    }
    # Check if download is needed
    foreach my $line (@{ $self->watchlines }) {
        next unless ($line->type eq 'group');
        # Stop on error
        if (   $line->parse
            or $line->search
            or $line->get_upstream_url
            or $line->get_newfile_base
            or $line->cmp_versions) {
            $self->{status} += $line->status;
            return $self->{status};
        }
        $download = $line->shared->{download}
          if ($line->shared->{download} > $download);
    }
    foreach my $line (@{ $self->watchlines }) {
        # Set same $download for all
        $line->shared->{download} = $download;
        # Non "group" lines where not initialized
        unless ($line->type eq 'group') {
            if (   $line->parse
                or $line->search
                or $line->get_upstream_url
                or $line->get_newfile_base
                or $line->cmp_versions) {
                $self->{status} += $line->status;
                return $self->{status};
            }
        }
        if ($line->download_file_and_sig) {
            $self->{status} += $line->status;
            return $self->{status};
        }
        if ($line->mkorigtargz) {
            $self->{status} += $line->status;
            return $self->{status};
        }
        if ($line->type eq 'group') {
            push @new_versions, $line->shared->{common_mangled_newversion}
              || $line->shared->{common_newversion}
              || ();
            push @last_versions, $line->parse_result->{lastversion};
            push @last_debian_mangled_uversions,
              $line->parse_result->{mangled_lastversion};
        }
    }
    my $new_version = join '+~', @new_versions;
    $dehs_tags->{'upstream-version'} = $new_version;
    $dehs_tags->{'debian-uversion'}  = join('+~', @last_versions)
      if (grep { $_ } @last_versions);
    $dehs_tags->{'debian-mangled-uversion'} = join '+~',
      @last_debian_mangled_uversions
      if (grep { $_ } @last_debian_mangled_uversions);
    my $mangled_ver
      = Dpkg::Version->new("1:" . $dehs_tags->{'debian-uversion'} . "-0",
        check => 0);
    my $upstream_ver = Dpkg::Version->new("1:$new_version-0", check => 0);
    if ($mangled_ver == $upstream_ver) {
        $dehs_tags->{'status'} = "up to date";
    } elsif ($mangled_ver > $upstream_ver) {
        $dehs_tags->{'status'} = "only older package available";
    } else {
        $dehs_tags->{'status'} = "newer package available";
    }
    foreach my $line (@{ $self->watchlines }) {
        my $path = $line->destfile or next;
        my $ver  = $line->shared->{common_mangled_newversion};
        $path =~ s/\Q$ver\E/$new_version/;
        uscan_warn "rename $line->{destfile} to $path\n";
        rename $line->{destfile}, $path;
        if ($dehs_tags->{"target-path"} eq $line->{destfile}) {
            $dehs_tags->{"target-path"} = $path;
            $dehs_tags->{target} =~ s/\Q$ver\E/$new_version/;
        } else {
            for (
                my $i = 0 ;
                $i < @{ $dehs_tags->{"component-target-path"} } ;
                $i++
            ) {
                if ($dehs_tags->{"component-target-path"}->[$i] eq
                    $line->{destfile}) {
                    $dehs_tags->{"component-target-path"}->[$i] = $path;
                    $dehs_tags->{"component-target"}->[$i]
                      =~ s/\Q$ver\E/$new_version/
                      or die $ver;
                }
            }
        }
        if ($line->signature_available) {
            rename "$line->{destfile}.asc", "$path.asc";
            rename "$line->{destfile}.sig", "$path.sig";
        }
    }
    return 0;
}

1;
