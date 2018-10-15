package Devscripts::MkOrigtargz::Config;

use strict;

use Devscripts::Compression qw'compression_is_supported
  compression_guess_from_file
  compression_get_property';
use Devscripts::Uscan::Output;
use Exporter 'import';
use File::Which;
use Moo;

use constant default_compression => 'xz';
# regexp-assemble << END
# tar\.gz
# tgz
# tar\.bz2
# tbz2?
# tar\.lzma
# tlz(?:ma?)?
# tar\.xz
# txz
# tar\.Z
# tar
# END
use constant tar_regex =>
  qr/t(?:ar(?:\.(?:[gx]z|lzma|bz2|Z))?|lz(?:ma?)?|[gx]z|bz2?)$/;

extends 'Devscripts::Config';

# Command-line parameters
has component      => (is => 'rw');
has compression    => (is => 'rw');
has copyright_file => (is => 'rw');
has directory      => (is => 'rw');
has exclude_file   => (is => 'rw');
has package        => (is => 'rw');
has signature      => (is => 'rw');
has signature_file => (is => 'rw');
has repack         => (is => 'rw');
has repack_suffix  => (is => 'rw');
has unzipopt       => (is => 'rw');
has version        => (is => 'rw');

# Internal accessors
has mode          => (is => 'rw');
has orig          => (is => 'rw', default => sub { 'orig' });
has excludestanza => (is => 'rw', default => sub { 'Files-Excluded' });
has upstream      => (is => 'rw');
has upstream_type => (is => 'rw');
has upstream_comp => (is => 'rw');

use constant keys => [
    ['package=s'],
    ['version|v=s'],
    [
        'component|c=s',
        undef,
        sub {
            if ($_[1]) {
                $_[0]->orig("orig-$_[1]");
                $_[0]->excludestanza("Files-Excluded-$_[1]");
            }
            1;

        }
    ],
    ['directory|C=s'],
    ['exclude-file=s',   undef, undef, sub { [] }],
    ['copyright-file=s', undef, undef, sub { [] }],
    ['signature=i',      undef, undef, 0],
    ['signature-file=s', undef, undef, ''],
    [
        'compression=s',
        undef,
        sub {
            return (0, "Unknown compression scheme $_[1]")
              unless compression_is_supported($_[1]);
            $_[0]->compression($_[1]);
        },
    ],
    ['symlink', undef, \&setmode],
    ['rename',  undef, \&setmode],
    ['copy',    undef, \&setmode],
    ['repack'],
    ['repack-suffix|S=s', undef, undef, ''],
    ['unzipopt=s'],
];

use constant rules => [
    # Check --package if --version is used
    sub {
        return (
              (defined $_[0]->{package} and not defined $_[0]->{version})
            ? (0, 'If you use --package, you also have to specify --version')
            : (1));
    },
    # Check that a tarball has been given and store it in $self->upstream
    sub {
        return (0, 'Please specify original tarball') unless (@ARGV == 1);
        $_[0]->upstream($ARGV[0]);
        return (
            -r $_[0]->upstream
            ? (1)
            : (0, "Could not read $_[0]->{upstream}: $!"));
    },
    # Get Debian pakage name an version unless given
    sub {
        my ($self) = @_;
        unless (defined $self->package) {
            # get package name
            my $c = Dpkg::Changelog::Debian->new(range => { count => 1 });
            $c->load('debian/changelog');
            if (my $msg = $c->get_parse_errors()) {
                return (0, "could not parse debian/changelog:\n$msg");
            }
            my ($entry) = @{$c};
            $self->package($entry->get_source());

            # get version number
            unless (defined $self->version) {
                my $debversion = Dpkg::Version->new($entry->get_version());
                if ($debversion->is_native()) {
                    return (0,
                            "Package with native version number $debversion; "
                          . "mk-origtargz makes no sense for native packages."
                    );
                }
                $self->version($debversion->version());
            }

            unshift @{ $self->copyright_file }, "debian/copyright"
              if -r "debian/copyright";

            # set destination directory
            unless (defined $self->directory) {
                $self->directory('..');
            }
        } else {
            unless (defined $self->directory) {
                $self->directory('.');
            }
        }
        return 1;
    },
    # Get upstream type and compression
    sub {
        my ($self) = @_;
        my $mime = compression_guess_from_file($self->upstream);

        if (defined $mime and $mime eq 'zip') {
            $self->upstream_type('zip');
            my ($prog, $pkg);
            if ($self->upstream =~ /\.xpi$/i) {
                $self->upstream_comp('xpi');
                $prog = 'xpi-unpack';
                $pkg  = 'mozilla-devscripts';
            } else {
                $self->upstream_comp('zip');
                $prog = $pkg = 'unzip';
            }
            return (0,
                    "$prog binary not found."
                  . " You need to install the package $pkg"
                  . " to be able to repack "
                  . $self->upstream_type
                  . " upstream archives.\n")
              unless (which $prog);
        } elsif ($self->upstream =~ tar_regex) {
            $self->upstream_type('tar');
            if ($self->upstream =~ /\.tar$/) {
                $self->upstream_comp('');
            } else {
                unless (
                    $self->upstream_comp(
                        compression_guess_from_file($self->upstream))
                ) {
                    return (0,
                        "Unknown compression used in $self->{upstream}");
                }
            }
        } else {
            # TODO: Should we ignore the name and only look at what file knows?
            return (0,
                    'Parameter '
                  . $self->upstream
                  . ' does not look like a tar archive or a zip file.');
        }
        return 1;
    },
    # Default compression
    sub {
        my ($self) = @_;
        # Case 1: format is 1.0
        if (-r 'debian/source/format') {
            open F, 'debian/source/format';
            my $str = <F>;
            unless ($str =~ /^([\d\.]+)/ and $1 >= 2.0) {
                ds_warn
"Source format is earlier than 2.0, switch compression to gzip";
                $self->compression('gzip');
                $self->repack(1) unless ($self->upstream_comp eq 'gzip');
            }
            close F;
        } elsif (-d 'debian') {
            ds_warn "Missing debian/source/format, switch compression to gzip";
            $self->compression('gzip');
            $self->repack(1) unless ($self->upstream_comp eq 'gzip');
        } elsif ($self->upstream_type eq 'tar') {
            # Uncompressed tar
            if (!$self->upstream_comp) {
                $self->repack(1);
            }
        }
        # Set to default. Will be changed after setting do_repack
        $self->compression('default')
          unless ($self->compression);
        return 1;
    },
    sub {
        my ($self) = @_;
        $self->{mode} ||= 'symlink';
    },
];

sub setmode {
    my ($self, $nv, $kname) = @_;
    return unless ($nv);
    if (defined $self->mode and $self->mode ne $kname) {
        return (0, "--$self->{mode} and --$kname are mutually exclusive");
    }
    $self->mode($kname);
}

1;
