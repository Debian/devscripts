package Devscripts::Salsa;

use strict;

use Devscripts::Output;
use Devscripts::Salsa::Config;

BEGIN {
    eval "use GitLab::API::v4;use GitLab::API::v4::Constants qw(:all)";
    if ($@) {
        print STDERR "You must install GitLab::API::v4\n";
        exit 1;
    }
}
use Moo;

# Command aliases
use constant cmd_aliases => {
    co          => 'checkout',
    ls          => 'list_repos',
    search      => 'search_project',
    search_repo => 'search_project',
    mr          => 'merge_request',
    mrs         => 'merge_requests',
};

has config => (
    is      => 'rw',
    default => sub { Devscripts::Salsa::Config->new->parse },
);

# File cache to avoid polling Gitlab too much
# (used to store ids, paths and names)
has _cache => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        return {} unless ($_[0]->config->cache_file);
        my %h;
        eval {
            require Devscripts::JSONCache;
            tie %h, 'Devscripts::JSONCache', $_[0]->config->cache_file;
            ds_debug "Cache opened";
        };
        if ($@) {
            ds_verbose "Unable to create cache object: $@";
            return {};
        }
        return \%h;
    },
);
has cache => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        $_[0]->_cache->{ $_[0]->config->api_url } //= {};
        return $_[0]->_cache->{ $_[0]->config->api_url };
    },
);

# In memory cache (used to avoid querying the project id twice when using
# update_safe
has projectCache => (
    is      => 'rw',
    default => sub { {} },
);

# GitLab API
has api => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my $r = GitLab::API::v4->new(
            url => $_[0]->config->api_url,
            (
                $_[0]->config->private_token
                ? (private_token => $_[0]->config->private_token)
                : ()
            ),
        );
        $r or ds_die "Unable to create GitLab::API::v4 object";
        return $r;
    },
);

# Accessors that resolve names, ids or paths
has username => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->id2username });

has user_id => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        $_[0]->config->user_id || $_[0]->username2id;
    },
);

has group_id => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->config->group_id || $_[0]->group2id },
);

has group_path => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return undef unless ($self->group_id);
        return $self->cache->{group_path}->{ $self->{group_id} }
          if $self->cache->{group_path}->{ $self->{group_id} };
        return $self->{group_path} if ($self->{group_path});   # Set if --group
        eval {
            $self->{group_path}
              = $self->api->group_without_projects($self->group_id)
              ->{full_path};
            $self->cache->{group_path}->{ $self->{group_id} }
              = $self->{group_path};
        };
        if ($@) {
            ds_verbose $@;
            ds_warn "Unexistent group " . $self->group_id;
            return undef;
        }
        return $self->{group_path};
    },
);

# Main method: launch command
sub run {
    my ($self, $args) = @_;
    binmode STDOUT, ':utf8';

    # Check group or user id
    my $command = $self->config->command;
    if (my $tmp = cmd_aliases->{$command}) {
        $command = $tmp;
    }
    eval { with "Devscripts::Salsa::$command" };
    if ($@) {
        ds_verbose $@;
        ds_die "Unknown command $command";
        return 1;
    }
    return $self->$command(@ARGV);
}

# Utilities

sub levels_name {
    my $res = {

        # needs GitLab::API::v4::Constants 0.11
        # no_access  => $GITLAB_ACCESS_LEVEL_NO_ACCESS,
        guest      => $GITLAB_ACCESS_LEVEL_GUEST,
        reporter   => $GITLAB_ACCESS_LEVEL_REPORTER,
        developer  => $GITLAB_ACCESS_LEVEL_DEVELOPER,
        maintainer => $GITLAB_ACCESS_LEVEL_MASTER,
        owner      => $GITLAB_ACCESS_LEVEL_OWNER,
    }->{ $_[1] };
    ds_die "Unknown access level '$_[1]'" unless ($res);
    return $res;
}

sub levels_code {
    return {
        $GITLAB_ACCESS_LEVEL_GUEST     => 'guest',
        $GITLAB_ACCESS_LEVEL_REPORTER  => 'reporter',
        $GITLAB_ACCESS_LEVEL_DEVELOPER => 'developer',
        $GITLAB_ACCESS_LEVEL_MASTER    => 'maintainer',
        $GITLAB_ACCESS_LEVEL_OWNER     => 'owner',
    }->{ $_[1] };
}

sub username2id {
    my ($self, $user) = @_;
    $user ||= $self->config->user || $self->api->current_user->{id};
    unless ($user) {
        return ds_warn "Token seems invalid";
        return 1;
    }
    unless ($user =~ /^\d+$/) {
        return $self->cache->{user_id}->{$user}
          if $self->cache->{user_id}->{$user};
        my $users = $self->api->users({ username => $user });
        return ds_die "Username '$user' not found"
          unless ($users and @$users);
        ds_verbose "$user id is $users->[0]->{id}";
        $self->cache->{user_id}->{$user} = $users->[0]->{id};
        return $users->[0]->{id};
    }
    return $user;
}

sub id2username {
    my ($self, $id) = @_;
    $id ||= $self->config->user_id || $self->api->current_user->{id};
    return $self->cache->{user}->{$id} if $self->cache->{user}->{$id};
    my $res = eval { $self->api->user($id)->{username} };
    if ($@) {
        ds_verbose $@;
        return ds_die "$id not found";
    }
    ds_verbose "$id is $res";
    $self->cache->{user}->{$id} = $res;
    return $res;
}

sub group2id {
    my ($self, $name) = @_;
    $name ||= $self->config->group;
    return unless $name;
    if ($self->cache->{group_id}->{$name}) {
        $self->group_path($self->cache->{group_id}->{$name}->{path});
        return $self->group_id($self->cache->{group_id}->{$name}->{id});
    }
    my $groups = $self->api->group_without_projects($name);
    if ($groups) {
        $groups = [$groups];
    } else {
        $self->api->groups({ search => $name });
    }
    return ds_die "No group found" unless ($groups and @$groups);
    if (scalar @$groups > 1) {
        ds_warn "More than one group found:";
        foreach (@$groups) {
            print <<END;
Id       : $_->{id}
Name     : $_->{name}
Full name: $_->{full_name}
Full path: $_->{full_path}

END
        }
        return ds_die "Set the chosen group id using --group-id.";
    }
    ds_verbose "$name id is $groups->[0]->{id}";
    $self->cache->{group_id}->{$name}->{path}
      = $self->group_path($groups->[0]->{full_path});
    $self->cache->{group_id}->{$name}->{id} = $groups->[0]->{id};
    return $self->group_id($groups->[0]->{id});
}

sub project2id {
    my ($self, $project) = @_;
    return $project if ($project =~ /^\d+$/);
    my $res;
    $project = $self->project2path($project);
    if ($self->projectCache->{$project}) {
        ds_debug "use cached id for $project";
        return $self->projectCache->{$project};
    }
    unless ($project =~ /^\d+$/) {
        eval { $res = $self->api->project($project)->{id}; };
        if ($@) {
            ds_verbose $@;
            ds_warn "Project $project not found:";
            return undef;
        }
    }
    ds_verbose "$project id is $res";
    $self->projectCache->{$project} = $res;
    return $res;
}

sub project2path {
    my ($self, $project) = @_;
    return $project if ($project =~ m#/#);
    my $path = $self->main_path;
    return undef unless ($path);
    ds_verbose "Project $project => $path/$project";
    return "$path/$project";
}

sub main_path {
    my ($self) = @_;
    my $path;
    if ($self->config->path) {
        $path = $self->config->path;
    } elsif (my $tmp = $self->group_path) {
        $path = $tmp;
    } elsif ($self->user_id) {
        $path = $self->username;
    } else {
        ds_warn "Unable to determine project path";
        return undef;
    }
    return $path;
}

# GitLab::API::v4 does not permit to call /groups/:id with parameters.
# It takes too much time for the "debian" group, since it returns the list of
# all projects together with all the details of the projects
sub GitLab::API::v4::group_without_projects {
    my $self = shift;
    return $self->_call_rest_client('GET', 'groups/:group_id', [@_],
        { query => { with_custom_attributes => 0, with_projects => 0 } });
}

1;
