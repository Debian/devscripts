# Removes a user from a group
package Devscripts::Salsa::del_user;

use strict;
use Devscripts::Output;
use Moo::Role;

sub del_user {
    my ($self, $user) = @_;
    unless ($user) {
        ds_warn "Usage $0 del_user <user>";
        return 1;
    }
    unless ($self->group_id) {
        ds_warn "Unable to del user without --group-id";
        return 1;
    }

    my $id = $self->username2id($user) or return 1;
    return 1
      if (
        $ds_yes < 0
        and ds_prompt(
"You're going to remove $user from group $self->{group_id}. Continue (Y/n) "
        ) =~ refuse
      );
    $self->api->remove_group_member($self->group_id, $id);
    ds_warn "User $user removed from group " . $self->group_id;
    return 0;
}

1;
