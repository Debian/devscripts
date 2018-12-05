# Adds a user in a group with a role
package Devscripts::Salsa::add_user;

use strict;
use Devscripts::Output;
use Moo::Role;

sub add_user {
    my ($self, $level, $user) = @_;
    unless ($level and $user) {
        ds_warn "Usage $0 --group-id 1234 add_user <level> <userid>";
        return 1;
    }
    unless ($self->group_id) {
        ds_warn "Unable to add user without --group or --group-id";
        return 1;
    }

    my $id = $self->username2id($user)  or return 1;
    my $al = $self->levels_name($level) or return 1;
    return 1
      if (
        $ds_yes < 0
        and ds_prompt(
"You're going to accept $user as $level in group $self->{group_id}. Continue (Y/n) "
        ) =~ refuse
      );
    $self->api->add_group_member(
        $self->group_id,
        {
            user_id      => $id,
            access_level => $al,
        });
    ds_warn "User $user added to group "
      . $self->group_id
      . " with role $level";
    return 0;
}

1;
