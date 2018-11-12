# Updates user role in a group
package Devscripts::Salsa::update_user;

use strict;
use Devscripts::Output;
use Moo::Role;

sub update_user {
    my ($self, $level, $user) = @_;
    unless ($level and $user) {
        ds_warn "Usage $0 update_user <level> <userid>";
        return 1;
    }
    unless ($self->group_id) {
        ds_warn "Unable to update user without --group-id";
        return 1;
    }

    my $id = $self->username2id($user);
    my $al = $self->levels_name($level);
    return 1
      if (
        $ds_yes < 0
        and ds_prompt(
"You're going to accept $user as $level in group $self->{group_id}. Continue (Y/n) "
        ) =~ refuse
      );
    $self->api->update_group_member(
        $self->group_id,
        $id,
        {
            access_level => $al,
        });
    ds_warn "User $user removed from group " . $self->group_id;
    return 0;
}

1;
