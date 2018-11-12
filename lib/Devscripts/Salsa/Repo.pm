# Common method to get projects
package Devscripts::Salsa::Repo;

use strict;
use Devscripts::Output;
use Moo::Role;

with "Devscripts::Salsa::Hooks";

sub get_repo {
    my ($self, $prompt, @reponames) = @_;
    my @repos;
    if ($self->config->all and @reponames == 0) {
        my $projects;
        # This rule disallow trying to configure all "Debian" projects:
        #  - Debian id is 2
        #  - next is 1987
        if ($self->group_id) {
            $projects
              = $self->api->paginator('group_projects', $self->group_id)->all;
        } elsif ($self->user_id) {
            $projects
              = $self->api->paginator('user_projects', $self->user_id)->all;
        } else {
            ds_warn "Missing or invalid token";
            return 1;
        }
        unless ($projects) {
            ds_warn "No projects found";
            return 1;
        }
        @repos = map {
            $self->projectCache->{ $_->{path_with_namespace} } = $_->{id};
            [$_->{id}, $_->{name}]
        } @$projects;
        if (@{ $self->config->skip }) {
            @repos = map {
                my $res = 1;
                foreach my $k (@{ $self->config->skip }) {
                    $res = 0 if ($_->[1] =~ m#(?:.*/)?\Q$k\E#);
                }
                $res ? $_ : ();
            } @repos;
        }
        if ($ds_yes > 0 or !$prompt) {
            ds_verbose "Found " . @repos . " projects";
        } else {
            unless (
                ds_prompt(
                        "You're going to configure "
                      . @repos
                      . " projects, continue (N/y)?"
                ) =~ accept
            ) {
                ds_warn "Aborting";
                return 1;
            }
        }
    } else {
        @repos = map { [$self->project2id($_), $_] } @reponames;
    }
    return @repos;
}

1;
