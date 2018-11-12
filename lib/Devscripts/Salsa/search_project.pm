# Searches projects using given string
package Devscripts::Salsa::search_project;

use strict;
use Devscripts::Output;
use Moo::Role;

sub search_project {
    my ($self, $project) = @_;
    unless ($project) {
        ds_warn "Searched string is missing";
        return 1;
    }
    my $projects = $self->api->project($project);
    if ($projects) {
        $projects = [$projects];
    } else {
        $projects
          = $self->api->paginator('projects',
            { search => $project, order_by => 'name' })->all();
    }
    unless ($projects and @$projects) {
        ds_warn "No projects found";
        return 1;
    }
    foreach (@$projects) {
        print <<END;
Id       : $_->{id}
Name     : $_->{name}
Full path: $_->{path_with_namespace}
END
        print($_->{namespace}->{kind} eq 'group'
            ? "Group id : "
            : "User id  : "
        );
        print "$_->{namespace}->{id}\n";
        print($_->{namespace}->{kind} eq 'group'
            ? "Group    : "
            : "User     : "
        );
        print "$_->{namespace}->{name}\n";
        if ($_->{forked_from_project} and $_->{forked_from_project}->{id}) {
            print
              "Fork of  : $_->{forked_from_project}->{name_with_namespace}\n";
        }
        print "\n";
    }
    return 0;
}

1;
