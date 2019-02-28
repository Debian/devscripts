# Lists merge requests proposed to a project
package Devscripts::Salsa::merge_requests;

use strict;
use Devscripts::Output;
use Moo::Role;

sub merge_requests {
    my ($self, @reponames) = @_;
    my $res = 1;
    unless (@reponames) {
        ds_warn "Repository name is missing";
        return 1;
    }
    foreach my $p (@reponames) {
        my $id    = $self->project2id($p);
        my $count = 0;
        unless ($id) {
            ds_warn "Project $_ not found";
            return 1;
        }
        print "$p\n";
        my $mrs = $self->api->paginator(
            'merge_requests',
            $id,
            {
                state => 'opened',
            });
        while ($_ = $mrs->next) {
            $res = 0;
            my $status = $_->{work_in_progress} ? 'WIP' : $_->{merge_status};
            print <<END;
\tId    : $_->{id}
\tTitle : $_->{title}
\tAuthor: $_->{author}->{username}
\tStatus: $status
\tUrl   : $_->{web_url}

END
        }
        unless ($count) {
            print "\n";
            next;
        }
    }
    return $res;
}

1;
