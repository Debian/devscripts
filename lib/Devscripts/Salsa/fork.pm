# Forks a project given by full path into group/user namespace
package Devscripts::Salsa::fork;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use Moo::Role;

with 'Devscripts::Salsa::chechout';

sub fork {
    my ($self, $project) = @_;
    my $path = $self->main_path or return 1;
    $self->api->fork_project($project, { namespace => $path });
    my $p = $project;
    $p =~ s#.*/##;
    $self->chechout($p);
    chdir $p;
    spawn(
        exec => [
            qw(git remote add upstream),
            $self->config->git_server_url . $project
        ],
        wait_child => 1
    );
    return 0;
}

1;
