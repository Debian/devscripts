# Searches users using given string
package Devscripts::Salsa::search_user;

use strict;
use Devscripts::Output;
use Moo::Role;

sub search_user {
    my ($self, $user) = @_;
    unless ($user) {
        ds_warn "User name is missing";
        return 1;
    }
    my $users = $self->api->user($user);
    if ($users) {
        $users = [$users];
    } else {
        $users = $self->api->paginator('users', { search => $user })->all();
    }
    unless ($users and @$users) {
        ds_warn "No user found";
        return 1;
    }
    foreach (@$users) {
        print <<END;
Id       : $_->{id}
Username : $_->{username}
Name     : $_->{name}
State    : $_->{state}

END
    }
    return 0;
}

1;
