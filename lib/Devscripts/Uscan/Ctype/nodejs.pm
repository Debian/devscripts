package Devscripts::Uscan::Ctype::nodejs;

use strict;

use Moo;
use JSON;
use Devscripts::Uscan::Output;

has dir => (is => 'ro');
has pkg => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        $_[0]->{dir} . '/package.json';
    });

sub version {
    my ($self) = @_;
    return unless $self->dir and -d $self->dir;
    unless (-r $self->pkg) {
        uscan_warn "Unable to read $self->{pkg}, skipping current version";
        return;
    }
    my ($version, $content);
    {
        local $/ = undef;
        open my $f, $self->pkg;
        $content = <$f>;
        close $f;
    }
    eval { $version = decode_json($content)->{version}; };
    uscan_warn $@ if $@;
    return $version;
}

1;
