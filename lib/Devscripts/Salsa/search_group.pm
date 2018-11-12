# Searches groups using given string
package Devscripts::Salsa::search_group;

use strict;
use Devscripts::Output;
use Moo::Role;

sub search_group {
    my ($self, $group) = @_;
    unless ($group) {
        ds_warn "Searched string is missing";
        return 1;
    }
    my $groups = $self->api->group_without_projects($group);
    if ($groups) {
        $groups = [$groups];
    } else {
        $groups = $self->api->paginator('groups',
            { search => $group, order_by => 'name' })->all;
    }
    unless ($groups and @$groups) {
        ds_warn "No group found";
        return 1;
    }
    foreach (@$groups) {
        print <<END;
Id       : $_->{id}
Name     : $_->{name}
Full name: $_->{full_name}
Full path: $_->{full_path}

END
    }
    return 0;
}

1;
