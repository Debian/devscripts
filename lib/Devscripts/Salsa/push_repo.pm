# Creates GitLab repo from local path
package Devscripts::Salsa::push_repo;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use Moo::Role;

with "Devscripts::Salsa::create_repo";

sub push_repo {
    my ($self, $reponame) = @_;
    unless ($reponame) {
        ds_warn "Repository path is missing";
        return 1;
    }
    unless (-d $reponame) {
        ds_warn "$reponame isn't a directory";
        return 1;
    }
    chdir $reponame;
    eval {
        spawn(
            exec       => ['dpkg-parsechangelog', '--show-field', 'Source'],
            to_string  => \$reponame,
            wait_child => 1,
        );
    };
    if ($@) {
        ds_warn $@;
        return 1;
    }
    chomp $reponame;
    my $out;
    spawn(
        exec       => ['git', 'remote', 'show'],
        to_string  => \$out,
        wait_child => 1,
    );
    if ($out =~ /^origin$/m) {
        ds_warn "git origin is already configured:\n$out";
        return 1;
    }
    my $path = $self->project2path('') or return 1;
    my $url = $self->config->git_server_url . "$path$reponame";
    spawn(
        exec       => ['git', 'remote', 'add', 'origin', $url],
        wait_child => 1,
    );
    my $res = $self->create_repo($reponame);
    if ($res) {
        return 1
          unless (
            ds_prompt(
"Project still exists, do you want to try to push local repo ? (y/N) "
            ) =~ accept
          );
    }
    spawn(
        exec =>
          ['git', 'push', '--all', '--verbose', '--set-upstream', 'origin'],
        wait_child => 1,
    );
    spawn(
        exec       => ['git', 'push', '--tags', '--verbose', 'origin'],
        wait_child => 1,
    );
    return 0;
}

1;
