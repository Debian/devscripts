# Launch request to join a group
package Devscripts::Salsa::join;

use strict;
use Devscripts::Output;
use Moo::Role;

sub join {
    my ($self, $group) = @_;
    unless ($group ||= $self->config->group || $self->config->group_id) {
        ds_warn "Group is missing";
        return 1;
    }
    my $gid = $self->group2id($group);
    $self->api->group_access_requests($gid);
    ds_warn "Request launched to group $group ($gid)";
    return 0;
}

1;
