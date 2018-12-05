# Lists forks of a project
package Devscripts::Salsa::forks;

use strict;
use Devscripts::Output;
use Moo::Role;

sub forks {
    my ($self, @reponames) = @_;
    my $res = 0;
    unless (@reponames) {
        ds_warn "Repository name is missing";
        return 1;
    }
    foreach my $p (@reponames) {
        my $id = $self->project2id($p);
        unless ($id) {
            ds_warn "Project $_ not found";
            $res++;
            next;
        }
        print "$p\n";
        my $forks = $self->api->paginator(
            'project_forks',
            $id,
            {
                state => 'opened',
            });
        unless ($forks) {
            print "\n";
            next;
        }
        while ($_ = $forks->next) {
            print <<END;
\tId  : $_->{id}
\tName: $_->{path_with_namespace}
\tURL : $_->{web_url}

END
        }
    }
    return $res;
}

1;
