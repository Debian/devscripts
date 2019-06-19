package Devscripts::Salsa::rename_branch;

use strict;
use Devscripts::Output;
use Moo::Role;

with "Devscripts::Salsa::Repo";

our $prompt = 1;

sub rename_branch {
    my ($self, @reponames) = @_;
    my $res   = 0;
    my @repos = $self->get_repo($prompt, @reponames);
    return @repos unless (ref $repos[0]);    # get_repo returns 1 when fails
    foreach (@repos) {
        my $id = $_->[0];
        ds_verbose "Configuring $_->[1]";
        my $project = $self->api->project($_->[0]);
        eval {
            $self->api->create_branch(
                $id,
                {
                    ref    => $self->config->source_branch,
                    branch => $self->config->dest_branch,
                });
            $self->api->delete_branch($id, $self->config->source_branch);
        };
        if ($@) {
            $res++;
            if ($self->config->no_fail) {
                ds_verbose $@;
                ds_warn
"Branch rename has failed for $_->[1]. Use --verbose to see errors\n";
                next;
            } else {
                ds_warn $@;
                return 1;
            }
        }
    }
    return $res;
}

1;
