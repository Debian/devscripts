# Displays protected branches of a project
package Devscripts::Salsa::protected_branches;

use strict;
use Devscripts::Output;
use Moo::Role;

sub protected_branches {
    my ($self, $reponame) = @_;
    unless ($reponame) {
        ds_warn "Repository name is missing";
        return 1;
    }
    my $branches
      = $self->api->protected_branches($self->project2id($reponame));
    if ($branches and @$branches) {
        printf " %-20s | %-25s | %-25s\n", 'Branch', 'Merge', 'Push';
        foreach (@$branches) {
            printf " %-20s | %-25s | %-25s\n", $_->{name},
              $_->{merge_access_levels}->[0]->{access_level_description},
              $_->{push_access_levels}->[0]->{access_level_description};
        }
    }
    return 0;
}

1;
