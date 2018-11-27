# Updates repositories
package Devscripts::Salsa::update_repo;

use strict;
use Devscripts::Output;
use GitLab::API::v4::Constants qw(:all);
use Moo::Role;

with "Devscripts::Salsa::Repo";

our $prompt = 1;

sub update_repo {
    my ($self, @reponames) = @_;
    if ($ds_yes < 0 and $self->config->command eq 'update_repo') {
        ds_warn
          "update_repo can't be launched when -i is set, use update_safe";
        return 1;
    }
    unless (@reponames or $self->config->all) {
        ds_warn "Repository name is missing";
        return 1;
    }
    if (@reponames and $self->config->all) {
        ds_warn "--all with a reponame makes no sense";
        return 1;
    }
    return $self->_update_repo(@reponames);
}

sub _update_repo {
    my ($self, @reponames) = @_;
    my $res = 0;
    # Common options
    my $configparams = { wiki_enabled => 0, };
    # visibility can be modified only by group owners
    $configparams->{visibility} = 'public'
      if $self->access_level >= $GITLAB_ACCESS_LEVEL_OWNER;
    # get repo list using Devscripts::Salsa::Repo
    my @repos = $self->get_repo($prompt, @reponames);
    return @repos unless (ref $repos[0]);    # get_repo returns 1 when fails
    foreach (@repos) {
        ds_verbose "Configuring $_->[1]";
        my $id  = $_->[0];
        my $str = $_->[1];
        eval {
            # apply new parameters
            $self->api->edit_project($id,
                { %$configparams, $self->desc($_->[1]) });
            # add hooks if needed
            $str =~ s#^.*/##;
            $self->add_hooks($id, $str);
        };
        if ($@) {
            $res++;
            if ($self->config->no_fail) {
                ds_verbose $@;
                ds_warn
"update_repo has failed for $_->[1]. Use --verbose to see errors\n";
                next;
            } else {
                ds_warn $@;
                return 1;
            }
        } elsif ($self->config->rename_head) {
            # 1 - creates new branch if --rename-head
            my $project = $self->api->project($id);
            if ($project->{default_branch} ne $self->config->dest_branch) {
                eval {
                    $self->api->create_branch(
                        $id,
                        {
                            ref    => $self->config->source_branch,
                            branch => $self->config->dest_branch,
                        });
                };
                if ($@) {
                    ds_debug $@ if ($@);
                    $project = undef;
                }

                eval {
                    $self->api->edit_project($id,
                        { default_branch => $self->config->dest_branch });
                    # delete old branch only if "create_branch" succeed
                    if ($project) {
                        $self->api->delete_branch($id,
                            $self->config->source_branch);
                    }
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
            } else {
                ds_verbose "Head already renamed for $str";
            }
        }
        ds_verbose "Project $str updated";
    }
    return $res;
}

sub access_level {
    my ($self) = @_;
    my $user_id = $self->api->current_user()->{id};
    if ($self->group_id) {
        my $tmp = $self->api->group_member($self->group_id, $user_id);
        unless ($tmp) {
            ds_warn "You're not member of this group";
            return 0;
        }
        return $tmp->{access_level};
    }
    return $GITLAB_ACCESS_LEVEL_OWNER;
}

1;
