# Deletes a repository
package Devscripts::Salsa::del_repo;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use Moo::Role;

sub del_repo {
    my ($self, $reponame) = @_;
    unless ($reponame) {
        ds_warn "Repository name or path is missing";
        return 1;
    }
    my $id   = $self->project2id($reponame) or return 1;
    my $path = $self->project2path($reponame);
    return 1
      if ($ds_yes < 0
        and ds_prompt("You're going to delete $path. Continue (Y/n) ")
        =~ refuse);
    $self->api->delete_project($id);
    ds_warn "Project $path deleted";
    return 0;
}

1;
