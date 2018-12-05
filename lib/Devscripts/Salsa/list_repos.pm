# Lists repositories of group/user
package Devscripts::Salsa::list_repos;

use strict;
use Devscripts::Output;
use Moo::Role;

sub list_repos {
    my ($self, $match) = @_;
    my $projects;
    my $opts = {
        order_by => 'name',
        sort     => 'asc',
        simple   => 1,
        ($match ? (search => $match) : ()),
    };
    if ($self->group_id) {
        $projects
          = $self->api->paginator('group_projects', $self->group_id, $opts);
    } else {
        $projects
          = $self->api->paginator('user_projects', $self->user_id, $opts);
    }
    unless ($projects) {
        ds_warn "No project found";
        return 1;
    }
    while ($_ = $projects->next) {
        print <<END;
Id  : $_->{id}
Name: $_->{name}
URL : $_->{web_url}

END
    }
    return 0;
}

1;
