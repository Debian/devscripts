# Clones or updates a repository using gbp
# TODO: git-dpm ?
package Devscripts::Salsa::checkout;

use strict;
use Devscripts::Output;
use Devscripts::Utils;
use Dpkg::IPC;
use Moo::Role;

sub checkout {
    my ($self, @repos) = @_;
    unless (@repos) {
        ds_warn "Usage $0 checkout <names>";
        return 1;
    }
    my $cdir = `pwd`;
    chomp $cdir;
    foreach (@repos) {
        my $path = $self->project2path($_);
        s#.*/##;
        if (-d $_) {
            chdir $_;
            ds_verbose "Updating existing checkout in $_";
            spawn(
                exec       => ['gbp', 'pull', '--pristine-tar'],
                wait_child => 1
            );
            chdir $cdir;
        } else {
            spawn(
                exec => [
                    'gbp',   'clone',
                    '--all', $self->config->git_server_url . $path . ".git"
                ],
                wait_child => 1,
            );
            ds_warn "$_ ready in $_/";
        }
    }
    return 0;
}

1;
