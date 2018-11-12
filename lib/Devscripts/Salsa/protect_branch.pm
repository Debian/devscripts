# Protects a branch
package Devscripts::Salsa::protect_branch;

use strict;
use Devscripts::Output;
use Moo::Role;

use constant levels => {
    o          => 50,
    owner      => 50,
    m          => 40,
    maintainer => 40,
    d          => 30,
    developer  => 30,
    r          => 20,
    reporter   => 20,
    g          => 10,
    guest      => 10,
};

sub protect_branch {
    my ($self, $reponame, $branch, $merge, $push) = @_;
    unless ($reponame and $branch) {
        ds_warn "usage: $0 protect_branch repo branch merge push";
        return 1;
    }
    if (defined $merge and $merge =~ /^(?:no|0)$/i) {
        $self->api->unprotect_branch($self->project2id($reponame), $branch);
        return 0;
    }
    unless (levels->{$merge} and levels->{$push}) {
        ds_warn
          "usage: $0 protect_branch repo branch <merge level> <push level>";
        return 1;
    }
    my $opts = { name => $branch };
    $opts->{push_access_level}  = (levels->{$push});
    $opts->{merge_access_level} = (levels->{$merge});
    $self->api->protect_branch($self->project2id($reponame), $opts);
    return 0;
}

1;
