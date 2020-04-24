# Common hooks library
package Devscripts::Salsa::Hooks;

use strict;
use Devscripts::Output;
use Moo::Role;

sub add_hooks {
    my ($self, $repo_id, $repo) = @_;
    if (   $self->config->kgb
        or $self->config->disable_kgb
        or $self->config->tagpending
        or $self->config->disable_tagpending
        or $self->config->irker
        or $self->config->disable_irker
        or $self->config->email
        or $self->config->disable_email) {
        my $hooks = $self->enabled_hooks($repo_id);
        return 1 unless (defined $hooks);
        # KGB hook (IRC)
        if ($self->config->kgb or $self->config->disable_kgb) {
            unless ($self->config->irc_channel->[0]
                or $self->config->disable_kgb) {
                ds_warn "--kgb needs --irc-channel";
                return 1;
            }
            if ($self->config->irc_channel->[1]) {
                ds_warn "KGB accepts only one --irc-channel value,";
            }
            if ($hooks->{kgb}) {
                ds_warn "Deleting old kgb (was $hooks->{kgb}->{url})";
                $self->api->delete_project_hook($repo_id, $hooks->{kgb}->{id});
            }
            if ($self->config->irc_channel->[0]
                and not $self->config->disable_kgb) {
                # TODO: if useful, add parameters for this options
                eval {
                    $self->api->create_project_hook(
                        $repo_id,
                        {
                            url => $self->config->kgb_server_url
                              . $self->config->irc_channel->[0],
                            map { ($_ => 1) } @{ $self->config->kgb_options },
                        });
                    ds_verbose "KGB hook added to project $repo_id (channel: "
                      . $self->config->irc_channel->[0] . ')';
                };
                if ($@) {
                    ds_warn "Fail to add KGB hook: $@";
                    if (!$self->config->no_fail) {
                        return 1;
                    }
                }
            }
        }
        # Irker hook (IRC)
        if ($self->config->irker or $self->config->disable_irker) {
            unless ($self->config->irc_channel->[0]
                or $self->config->disable_irker) {
                ds_warn "--irker needs --irc-channel";
                return 1;
            }
            if ($hooks->{irker}) {
                no warnings;
                ds_warn
"Deleting old irker (redirected to $hooks->{irker}->{recipients})";
                $self->api->delete_project_service($repo_id, 'irker');
            }
            if ($self->config->irc_channel->[0]
                and not $self->config->disable_irker) {
                # TODO: if useful, add parameters for this options
                my $ch = join(' ',
                    map { '#' . $_ } @{ $self->config->irc_channel });
                $self->api->edit_project_service(
                    $repo_id, 'irker',
                    {
                        active      => 1,
                        server_host => $self->config->irker_host,
                        (
                            $self->config->irker_port
                            ? (server_port => $self->config->irker_port)
                            : ()
                        ),
                        default_irc_uri   => $self->config->irker_server_url,
                        recipients        => $ch,
                        colorize_messages => 1,
                    });
                ds_verbose
                  "Irker hook added to project $repo_id (channel: $ch)";
            }
        }
        # email on push
        if ($self->config->email or $self->config->disable_email) {
            if ($hooks->{email}) {
                no warnings;
                ds_warn
"Deleting old email-on-push (redirected to $hooks->{email}->{recipients})";
                $self->api->delete_project_service($repo_id, 'emails-on-push');
            }
            if (@{ $self->config->email_recipient }
                and not $self->config->disable_email) {
                # TODO: if useful, add parameters for this options
                $self->api->edit_project_service(
                    $repo_id,
                    'emails-on-push',
                    {
                        recipients => join(' ',
                            map { my $a = $_; $a =~ s/%p/$repo/; $a }
                              @{ $self->config->email_recipient }),
                    });
                no warnings;
                ds_verbose
                  "Email-on-push hook added to project $repo_id (recipients: "
                  . join(' ', @{ $self->config->email_recipient }) . ')';
            }
        }
        # Tagpending hook
        if ($self->config->tagpending or $self->config->disable_tagpending) {
            if ($hooks->{tagpending}) {
                ds_warn
                  "Deleting old tagpending (was $hooks->{tagpending}->{url})";
                $self->api->delete_project_hook($repo_id,
                    $hooks->{tagpending}->{id});
            }
            my $repo_name = $self->api->project($repo_id)->{name};
            unless ($self->config->disable_tagpending) {
                eval {
                    $self->api->create_project_hook(
                        $repo_id,
                        {
                            url => $self->config->tagpending_server_url
                              . $repo_name,
                            push_events => 1,
                        });
                    ds_verbose "Tagpending hook added to project $repo_id";
                };
                if ($@) {
                    ds_warn "Fail to add Tagpending hook: $@";
                    if (!$self->config->no_fail) {
                        return 1;
                    }
                }
            }
        }
    }
    return 0;
}

sub enabled_hooks {
    my ($self, $repo_id) = @_;
    my $hooks;
    my $res = {};
    if (   $self->config->kgb
        or $self->config->disable_kgb
        or $self->config->tagpending
        or $self->config->disable_tagpending) {
        $hooks = eval { $self->api->project_hooks($repo_id) };
        if ($@) {
            ds_warn "Unable to check hooks for project $repo_id";
            return undef;
        }
        foreach my $h (@{$hooks}) {
            $res->{kgb} = {
                id      => $h->{id},
                url     => $h->{url},
                options => [grep { $h->{$_} and $h->{$_} eq 1 } keys %$h],
              }
              if $h->{url} =~ /\Q$self->{config}->{kgb_server_url}\E/;
            $res->{tagpending} = {
                id  => $h->{id},
                url => $h->{url},
              }
              if $h->{url} =~ /\Q$self->{config}->{tagpending_server_url}\E/;
        }
    }
    if (    ($self->config->email or $self->config->disable_email)
        and $_ = $self->api->project_service($repo_id, 'emails-on-push')
        and $_->{active}) {
        $res->{email} = $_->{properties};
    }
    if (    ($self->config->irker or $self->config->disable_irker)
        and $_ = $self->api->project_service($repo_id, 'irker')
        and $_->{active}) {
        $res->{irker} = $_->{properties};
    }
    return $res;
}

sub desc {
    my ($self, $repo) = @_;
    my @res = ();
    if ($self->config->desc) {
        my $str = $self->config->desc_pattern;
        $str  =~ s/%P/$repo/g;
        $repo =~ s#.*/##;
        $str  =~ s/%p/$repo/g;
        push @res, description => $str;
    }
    if ($self->config->disable_issues) {
        push @res, issues_enabled => 0;
    } elsif ($self->config->enable_issues) {
        push @res, issues_enabled => 1;
    }
    if ($self->config->disable_mr) {
        push @res, merge_requests_enabled => 0;
    } elsif ($self->config->enable_mr) {
        push @res, merge_requests_enabled => 1;
    }
    if ($self->config->ci_config_path) {
        push @res, ci_config_path => $self->config->ci_config_path;
    }
    return @res;
}

1;
