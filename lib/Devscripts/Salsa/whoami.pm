# Gives information on token owner
package Devscripts::Salsa::whoami;

use strict;
use Devscripts::Output;
use Moo::Role;

sub whoami {
    my ($self) = @_;
    my $current_user = $self->api->current_user;
    print <<END;
Id      : $current_user->{id}
Username: $current_user->{username}
Name    : $current_user->{name}
Email   : $current_user->{email}
State   : $current_user->{state}
END
    $self->cache->{user}->{ $current_user->{id} } = $current_user->{username};
    $self->cache->{user_id}->{ $current_user->{username} }
      = $current_user->{id};
    return 0;
}

1;
