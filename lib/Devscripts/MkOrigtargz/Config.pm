package Devscripts::MkOrigtargz::Config;

use strict;

use Devscripts::Compression 'compression_is_supported';
use Devscripts::Uscan::Output;
use Exporter 'import';
use Moo;

use constant default_compression => 'xz';

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
    sub {
        $_[0]->{mode} ||= 'symlink';
    },
    sub {
        return (
              (defined $_[0]->{package} and not defined $_[0]->{version})
            ? (0, 'If you use --package, you also have to specify --version')
            : (1));
    },
    sub {
        return (
            @ARGV == 1
            ? ($_[0]->upstream($ARGV[0]))
            : (0, 'Please specify original tarball'));
    },
    sub {
        return (
            -e $_[0]->upstream($ARGV[0])
            ? (1)
            : (0, "Could not read $_[0]->{upstream}: $!"));
    },
    sub {
        my ($self) = @_;
        unless (defined $self->package) {
            # get package name
            my $c = Dpkg::Changelog::Debian->new(range => { count => 1 });
            $c->load('debian/changelog');
            if (my $msg = $c->get_parse_errors()) {
                die "could not parse debian/changelog:\n$msg";
            }
            my ($entry) = @{$c};
            $self->package($entry->get_source());

            # get version number
            unless (defined $self->version) {
                my $debversion = Dpkg::Version->new($entry->get_version());
                if ($debversion->is_native()) {
                    ds_warn
"Package with native version number $debversion; mk-origtargz makes no sense for native packages.\n";
                    exit 0;
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
    }
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
