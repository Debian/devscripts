# Creates repo using name or path
package Devscripts::Salsa::create_repo;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use Moo::Role;

with "Devscripts::Salsa::Hooks";

sub create_repo {
    my ($self, $reponame) = @_;
    unless ($reponame) {
        ds_warn "Repository name is missing";
        return 1;
    }
    # Get parameters from Devscripts::Salsa::Repo
    my $opts = {
        name       => $reponame,
        path       => $reponame,
        visibility => 'public',
        $self->desc($reponame),
    };
    if ($self->group_id) {
        $opts->{namespace_id} = $self->group_id;
    }
    return 1
      if (
        $ds_yes < 0
        and ds_prompt(
                "You're going to create $reponame in "
              . ($self->group_id ? $self->group_path : 'your namespace')
              . ". Continue (Y/n) "
        ) =~ refuse
      );
    my $repo = eval { $self->api->create_project($opts) };
    if ($@ or !$repo) {
        ds_warn "Project not created: $@";
        return 1;
    }
    ds_warn "Project $repo->{web_url} created";
    $reponame =~ s#^.*/##;
    $self->add_hooks($repo->{id}, $reponame);
    return 0;
}

1;
