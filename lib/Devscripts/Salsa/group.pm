# Lists members of a group
package Devscripts::Salsa::group;

use strict;
use Devscripts::Output;
use Moo::Role;

sub group {
    my ($self) = @_;
    my $count = 0;
    unless ($self->group_id) {
        ds_warn "Usage $0 --group-id 1234 group";
        return 1;
    }
    my $users = $self->api->paginator('group_members', $self->group_id);
    while ($_ = $users->next) {
        $count++;
        my $access_level = $self->levels_code($_->{access_level});
        print <<END;
Id          : $_->{id}
Username    : $_->{username}
Name        : $_->{name}
Access level: $access_level
State       : $_->{state}

END
    }
    unless ($count) {
        ds_warn "No users found";
        return 1;
    }
    return 0;
}

1;
