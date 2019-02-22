# Lists repositories of group/user
package Devscripts::Salsa::list_repos;

use strict;
use Devscripts::Output;
use Moo::Role;

sub list_repos {
    my ($self, $match) = @_;
    my $projects;
    my $count = 0;
    my $opts  = {
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
    while ($_ = $projects->next) {
        $count++;
        print <<END;
Id  : $_->{id}
Name: $_->{name}
URL : $_->{web_url}

END
    }
    unless ($count) {
        ds_warn "No projects found";
        return 1;
    }
    return 0;
}

1;
