# Creates a merge request from current directory (or using parameters)
package Devscripts::Salsa::merge_request;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use Moo::Role;

with 'Devscripts::Salsa::search_project';

sub merge_request {
    my ($self, $dst_project, $dst_branch) = @_;
    my $src_branch  = $self->config->mr_src_branch;
    my $src_project = $self->config->mr_src_project;
    $dst_project ||= $self->config->mr_dst_project;
    $dst_branch  ||= $self->config->mr_dst_branch;
    my $title = $self->config->mr_title;
    my $desc  = $self->config->mr_desc;

    if ($src_branch) {
        unless ($src_project and $dst_project) {
            ds_warn "--mr-src-project and --mr-src-project "
              . "are required when --mr-src-branch is set";
            return 1;
        }
        unless ($src_project =~ m#/#) {
            $src_project = $self->project2path($src_project);
        }
    } else {    # Use current repository to find elements
        ds_verbose "using current branch as source";
        my $out;
        unless ($src_project) {
            # 1. Verify that repo is ready
            spawn(
                exec       => [qw(git status -s -b -uno)],
                wait_child => 1,
                to_string  => \$out
            );
            chomp $out;
            # Case "rebased"
            if ($out =~ /\[/) {
                ds_warn "Current branch isn't pushed, aborting:\n";
                return 1;
            }
            # Case else: nothing after src...dst
            unless ($out =~ /\s(\S+)\.\.\.(\S+)$/s) {
                ds_warn
                  "Current branch as no origin or isn't pushed, aborting\n";
                return 1;
            }
            # 2. Set source branch to current branch
            $src_branch ||= $1;
            ds_verbose "Found current branch: $src_branch";
        }
        unless ($src_project and $dst_project) {
            # Check remote links
            spawn(
                exec       => [qw(git remote --verbose show)],
                wait_child => 1,
                to_string  => \$out,
            );
            my $origin = $self->config->api_url;
            $origin =~ s#api/v4$##;
            # 3. Set source project using "origin" target
            unless ($src_project) {
                if ($out
                    =~ /origin\s+(?:\Q$self->{config}->{git_server_url}\E|\Q$origin\E)(\S*)/m
                ) {
                    $src_project = $1;
                    $src_project =~ s/\.git$//;
                } else {
                    ds_warn
"Unable to find project origin, set it using --mr-src-project";
                    return 1;
                }
            }
            # 4. Steps to find destination project:
            #    - command-line
            #    - GitLab API (search for "forked_from_project"
            #    - "upstream" in git remote
            #    - use source project as destination project

            # 4.1. Stop if dest project has been given in command line
            unless ($dst_project) {
                my $project = $self->api->project($src_project);

                # 4.2. Search original project from GitLab API
                if ($project->{forked_from_project}) {
                    $dst_project
                      = $project->{forked_from_project}->{path_with_namespace};
                }
                if ($dst_project) {
                    ds_verbose "Project was forked from $dst_project";

                    # 4.3. Search for an "upstream" target in `git remote`
                } elsif ($out
                    =~ /upstream\s+(?:\Q$self->{config}->{git_server_url}\E|\Q$origin\E)(\S*)/m
                ) {
                    $dst_project = $1;
                    $dst_project =~ s/\.git$//;
                    ds_verbose 'Use "upstream" target as dst project';
                    # 4.4. Use source project as destination
                } else {
                    ds_warn
"No upstream target found, using current project as target";
                    $dst_project = $src_project;
                }
                ds_verbose "Use $dst_project as dest project";
            }
        }
        # 5. Search for MR title and desc
        unless ($title) {
            ds_warn "Title not set, using last commit";
            spawn(
                exec       => ['git', 'show', '--format=format:%s###%b'],
                wait_child => 1,
                to_string  => \$out,
            );
            $out =~ s/\ndiff.*$//s;
            my ($t, $d) = split /###/, $out;
            chomp $d;
            $title = $t;
            ds_verbose "Title set to $title";
            $desc ||= $d;
            # Replace all bug links by markdown links
            if ($desc) {
                $desc =~ s@#(\d{6,})\b@[#$1](https://bugs.debian.org/$1)@mg;
                ds_verbose "Desc set to $desc";
            }
        }
    }
    if ($dst_project eq 'same') {
        $dst_project = $src_project;
    }
    my $src = $self->api->project($src_project);
    unless ($title) {
        ds_warn "Title is required";
        return 1;
    }
    unless ($src and $src->{id}) {
        ds_warn "Target project not found $src_project";
        return 1;
    }
    my $dst;
    if ($dst_project) {
        $dst = $self->api->project($dst_project);
        unless ($dst and $dst->{id}) {
            ds_warn "Target project not found";
            return 1;
        }
    }
    return 1
      if (
        ds_prompt(
"You're going to push an MR to $dst_project:$dst_branch. Continue (Y/n)"
        ));
    my $res = $self->api->create_merge_request(
        $src->{id},
        {
            source_branch        => $src_branch,
            target_branch        => $dst_branch,
            title                => $title,
            remove_source_branch => $self->config->mr_remove_source_branch,
            squash               => $self->config->mr_allow_squash,
            ($dst  ? (target_project_id => $dst->{id}) : ()),
            ($desc ? (description       => $desc)      : ()),
        });
    ds_warn "MR '$title' posted:";
    ds_warn $res->{web_url};
    return 0;
}

1;
