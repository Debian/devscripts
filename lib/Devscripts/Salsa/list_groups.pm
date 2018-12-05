# Lists subgroups of a group or groups of a user
package Devscripts::Salsa::list_groups;

use strict;
use Devscripts::Output;
use Moo::Role;

sub list_groups {
    my ($self, $match) = @_;
    my $groups;
    my $opts = {
        order_by => 'name',
        sort     => 'asc',
        ($match ? (search => $match) : ()),
    };
    if ($self->group_id) {
        $groups
          = $self->api->paginator('group_subgroups', $self->group_id, $opts);
    } else {
        $groups = $self->api->paginator('groups', $opts);
    }
    eval {
        while ($_ = $groups->next) {
            my $parent = $_->{parent_id} ? "Parent id: $_->{parent_id}\n" : '';
            print <<END;
Id       : $_->{id}
Name     : $_->{name}
Full path: $_->{full_path}
$parent
END
        }
    };
    if ($@) {
        ds_warn "No groups found";
        return 1;
    }
    return 0;
}

1;
