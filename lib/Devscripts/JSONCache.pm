package Devscripts::JSONCache;

use strict;
use JSON;
use Moo;

has file => (is => 'rw', required => 1);

has saved => (is => 'rw');

has _data => (is => 'rw');

sub save_sec {
    my ($self, $obj) = @_;
    my $tmp = umask;
    umask 0177;
    open(my $fh, '>', $self->file) or ($self->saved(1) and die $!);
    print $fh JSON::to_json($obj);
    close $fh;
    umask $tmp;
}

sub data {
    my ($self) = @_;
    return $self->_data if $self->_data;
    my $res;
    if (-r $self->file) {
        open(F, $self->file) or ($self->saved(1) and die $!);
        $res = JSON::from_json(join('', <F>) || "{}");
        close F;
    } else {
        $self->save_sec({});
        $self->saved(0);
    }
    return $self->_data($res);
}

sub TIEHASH {
    my $r = shift->new({
        file => shift,
        @_,
    });
    # build data
    $r->data;
    return $r;
}

sub FETCH {
    return $_[0]->data->{ $_[1] };
}

sub STORE {
    $_[0]->data->{ $_[1] } = $_[2];
}

sub DELETE {
    delete $_[0]->data->{ $_[1] };
}

sub CLEAR {
    $_[0]->save({});
}

sub EXISTS {
    return exists $_[0]->data->{ $_[1] };
}

sub FIRSTKEY {
    my ($k) = sort { $a cmp $b } keys %{ $_[0]->data };
    return $k;
}

sub NEXTKEY {
    my ($self, $last) = @_;
    my $i    = 0;
    my @keys = map {
        return $_ if ($i);
        $i++ if ($_ eq $last);
        return ()
      }
      sort { $a cmp $b } keys %{ $_[0]->data };
    return @keys ? $keys[0] : ();
}

sub SCALAR {
    return scalar %{ $_[0]->data };
}

sub save {
    return if ($_[0]->saved);
    eval { $_[0]->save_sec($_[0]->data); };
    $_[0]->saved(1);
}

*DESTROY = *UNTIE = *save;

1;
