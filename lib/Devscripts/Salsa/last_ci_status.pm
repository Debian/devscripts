package Devscripts::Salsa::last_ci_status;

use strict;
use Devscripts::Output;
use Moo::Role;

with "Devscripts::Salsa::Repo";

use constant OK      => 'success';
use constant SKIPPED => 'skipped';
use constant FAILED  => 'failed';

sub last_ci_status {
    my ($self, @repos) = @_;
    unless (@repos or $self->config->all) {
        ds_warn "Usage $0 ci_status <names>";
        return 1;
    }
    if (@repos and $self->config->all) {
        ds_warn "--all with a reponame makes no sense";
        return 1;
    }

    # If --all is asked, launch all projects
    @repos = map { $_->[1] } $self->get_repo(0, @repos) unless (@repos);
    my $ret = 0;
    foreach my $repo (@repos) {
        my $id        = $self->project2id($repo) or return 1;
        my $pipelines = $self->api->pipelines($id);
        unless ($pipelines and @$pipelines) {
            ds_warn "No pipelines for $repo";
            $ret++;
            return 1 unless $self->config->no_fail;
        } else {
            my $status = $pipelines->[0]->{status};
            if ($status eq OK) {
                print "Last result for $repo: $status\n";
            } else {
                print STDERR "Last result for $repo: $status\n";
                my $jobs
                  = $self->api->pipeline_jobs($id, $pipelines->[0]->{id});
                my %jres;
                foreach my $job (sort { $a->{id} <=> $b->{id} } @$jobs) {
                    next if $job->{status} eq SKIPPED;
                    push @{ $jres{ $job->{status} } }, $job->{name};
                }
                if ($jres{ OK() }) {
                    print STDERR '    success: '
                      . join(', ', @{ $jres{ OK() } }) . "\n";
                    delete $jres{ OK() };
                }
                foreach my $k (sort keys %jres) {
                    print STDERR '    '
                      . uc($k) . ': '
                      . join(', ', @{ $jres{$k} }) . "\n";
                }
                print STDERR "\n  See: " . $pipelines->[0]->{web_url} . "\n\n";
                if ($status eq FAILED) {
                    $ret++;
                    unless ($self->config->no_fail) {
                        ds_verbose "Use --no-fail to continue";
                        return 1;
                    }
                }
            }
        }
    }
    return $ret;
}

1;
