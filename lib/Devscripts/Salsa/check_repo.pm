# Parses repo to check if parameters are well set
package Devscripts::Salsa::check_repo;

use strict;
use Devscripts::Output;
use Moo::Role;

with "Devscripts::Salsa::Repo";

sub check_repo {
    my $self = shift;
    my ($res) = $self->_check_repo(@_);
    return $res;
}

sub _check_repo {
    my ($self, @reponames) = @_;
    my $res = 0;
    my @fail;
    unless (@reponames or $self->config->all) {
        ds_warn "Repository name is missing";
        return 1;
    }
    if (@reponames and $self->config->all) {
        ds_warn "--all with a reponame makes no sense";
        return 1;
    }
    # Get repo list from Devscripts::Salsa::Repo
    my @repos = $self->get_repo(0, @reponames);
    return @repos unless (ref $repos[0]);
    foreach my $repo (@repos) {
        my ($id, $name) = @$repo;
        ds_debug "Checking $name ($id)";
        my @err;
        my $project = eval { $self->api->project($id) };
        unless ($project) {
            ds_debug $@;
            ds_warn "Project $name not found";
            next;
        }
        # check description
        my %prms = $self->desc($name);
        if ($self->config->desc) {
            push @err, "bad description: $project->{description}"
              if ($prms{description} ne $project->{description});
        }
        # check issues/MR authorizations
        foreach (qw(issues_enabled merge_requests_enabled ci_config_path)) {
            push @err, "$_ should be $prms{$_}"
              if (defined $prms{$_} and $project->{$_} ne $prms{$_});
        }
        # only public projects are accepted
        push @err, "private" unless ($project->{visibility} eq "public");
        # Default branch
        if ($self->config->rename_head) {
            push @err, "Default branch is $project->{default_branch}"
              if ($project->{default_branch} ne $self->config->dest_branch);
        }
        # Webhooks (from Devscripts::Salsa::Hooks)
        my $hooks = $self->enabled_hooks($id);
        unless (defined $hooks) {
            ds_warn "Unable to get $name hooks";
            next;
        }
        # KGB
        if ($self->config->kgb and not $hooks->{kgb}) {
            push @err, "kgb missing";
        } elsif ($self->config->disable_kgb and $hooks->{kgb}) {
            push @err, "kgb enabled";
        } elsif ($self->config->kgb) {
            push @err,
              "bad irc channel: "
              . substr($hooks->{kgb}->{url},
                length($self->config->kgb_server_url))
              if $hooks->{kgb}->{url} ne $self->config->kgb_server_url
              . $self->config->irc_channel->[0];
            my @wopts = @{ $self->config->kgb_options };
            my @gopts = sort @{ $hooks->{kgb}->{options} };
            my $i     = 0;
            while (@gopts and @wopts) {
                my $a;
                $a = ($wopts[0] cmp $gopts[0]);
                if ($a == -1) {
                    push @err, "Missing KGB option " . shift(@wopts);
                } elsif ($a == 1) {
                    push @err, 'Unwanted KGB option ' . shift(@gopts);
                } else {
                    shift @wopts;
                    shift @gopts;
                }
            }
            push @err, map { "Missing KGB option $_" } @wopts;
            push @err, map { "Unwanted KGB option $_" } @gopts;
        }
        # Email-on-push
        if ($self->config->email
            and not($hooks->{email} and %{ $hooks->{email} })) {
            push @err, "email-on-push missing";
        } elsif (
            $self->config->email
            and $hooks->{email}->{recipients} ne join(
                ' ',
                map {
                    my $a = $_;
                    my $b = $name;
                    $b =~ s#.*/##;
                    $a =~ s/%p/$b/;
                    $a
                } @{ $self->config->email_recipient })
        ) {
            push @err, "bad email recipients " . $hooks->{email}->{recipients};
        } elsif ($self->config->disable_email and $hooks->{kgb}) {
            push @err, "email-on-push enabled";
        }
        # Irker
        if ($self->config->irker and not $hooks->{irker}) {
            push @err, "irker missing";
        } elsif (
            $self->config->irker
            and $hooks->{irker}->{recipients} ne join(
                ' ',
                map {
                    "#$_"
                } @{ $self->config->irc_channel })
        ) {
            push @err, "bad irc channel: " . $hooks->{irker}->{recipients};
        } elsif ($self->config->disable_irker and $hooks->{irker}) {
            push @err, "irker enabled";
        }
        # Tagpending
        if ($self->config->tagpending and not $hooks->{tagpending}) {
            push @err, "tagpending missing";
        } elsif ($self->config->disable_tagpending
            and $hooks->{tagpending}) {
            push @err, "tagpending enabled";
        }
        # report errors
        if (@err) {
            $res++;
            push @fail, $name;
            print "$name:\n";
            print "\t$_\n" foreach (@err);
        } else {
            ds_verbose "$name: OK";
        }
    }
    return ($res, \@fail);
}

1;
