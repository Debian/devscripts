{

    package MockRESTClient;
    use URI;
    use Moo;
    extends 'GitLab::API::v4::RESTClient';

    has _mocks => (
        is       => 'ro',
        default  => sub { [] },
        init_arg => undef,
    );

    sub mock_endpoints {
        my $self = shift;

        while (@_) {
            my $method  = shift;
            my $path_re = shift;
            my $sub     = shift;

            push @{ $self->_mocks() }, [$method, $path_re, $sub];
        }

        return;
    }

    sub _http_tiny_request {
        my ($self, $req_method, $req) = @_;

        die "req_method may only be 'request' at this time"
          if $req_method ne 'request';

        my ($method, $url, $options) = @$req;

        my $path = URI->new($url)->path();
        $path =~ s{^.*api/v4/}{};

        foreach my $mock (@{ $self->_mocks() }) {
            my ($handler_method, $path_re, $sub) = @$mock;

            next if $method ne $handler_method;

            my @captures = ($path =~ $path_re);
            next if !@captures;    # No captures still returns a 1.

            my ($status, $content)
              = $sub->([$method, $url, $options], @captures);
            $content = JSON::to_json($content) if ref $content;

            return {
                status  => $status,
                success => ($status =~ m{^2\d\d$}) ? 1 : 0,
                defined($content) ? (content => $content) : (),
            };
        }

        die "No mock endpoint matched the $method '$path' endpoint";
    }
}

sub api {
    my ($gitdir) = @_;
    my @users = ({
        id       => 11,
        username => 'me',
        name     => 'Me',
        email    => 'me@debian.org',
        state    => 'active'
    });
    my @teams = ({
        id        => 2099,
        name      => 'Debian JavaScript Maintainers',
        full_name => 'Debian JavaScript Maintainers',
        full_path => 'js-team',
    });
    my @projects;
    my $next_id = 1;

    my $api = GitLab::API::v4->new(
        url               => 'https://example.com/api/v4',
        rest_client_class => 'MockRESTClient',
    );

    $api->rest_client->mock_endpoints(
        GET  => qr{^user$}  => sub { 200, $users[0] },
        GET  => qr{^users$} => sub { 200, \@users },
        POST => qr{^users$} => sub {
            my ($req) = @_;
            my $user = decode_json($req->[2]->{content});
            $user->{id} = $next_id;
            $next_id++;
            push @users, $user;
            return 204;
        },
        GET => qr{^users?/(\d+)$} => sub {
            my ($req, $id) = @_;
            foreach my $user (@users) {
                next if $user->{id} != $id;
                return 200, $user;
            }
            return 404;
        },
        GET => qr{^users/(\D+)$} => sub {
            my ($req, $id) = @_;
            foreach my $user (@users) {
                next if $user->{username} != $id;
                return 200, $user;
            }
            return 404;
        },
        GET => qr{^groups$} => sub {
            200, \@teams;
        },
        GET => qr{^groups/([^/]+)$} => sub {
            my ($req, $name) = @_;
            foreach my $team (@teams) {
                next if $team->{full_path} ne $name;
                return 200, $team;
            }
            return 404;
        },
        PUT => qr{^users/(\d+)$} => sub {
            my ($req, $id) = @_;
            my $data = decode_json($req->[2]->{content});
            foreach my $user (@users) {
                next if $user->{id} != $id;
                %$user = (%$user, %$data,);
                return 204;
            }
            return 404;
        },
        DELETE => qr{^users/(\d+)$} => sub {
            my ($req, $id) = @_;
            my @new;
            foreach my $user (@users) {
                next if $user->{id} == $id;
                push @new, $user;
            }
            return 404 if @new == @users;
            @users = @new;
            return 204;
        },
        # Projects
        POST => qr{^projects$} => sub {
            my $content = JSON::from_json($_[0]->[2]->{content});
            mkdir "$gitdir/me/$content->{path}";
            $ENV{"GIT_CONFIG_NOGLOBAL"} = 1;
            print
`cd $gitdir/me/$content->{path};git init;git config receive.denyCurrentBranch ignore;cd -`;
            $content->{id}        = scalar @projects + 1;
            $content->{hooks}     = [];
            $content->{namespace} = {
                kind => 'user',
                id   => 11,
                name => 'me',
            };
            $content->{path_with_namespace} = 'me/' . $content->{path};
            $content->{web_url} = 'http://no.org/me/' . $content->{path};
            push @projects, $content;
            return 200, $content;
        },
        GET => qr{^projects/(\d+)/hooks} => sub {
            my ($req, $id) = @_;
            my $res = eval { $projects[$id - 1]->{hooks} };
            return ($res ? (200, $res) : (404));
        },
        GET => qr{^projects/(\d+)/services/(\w+)} => sub {
            my ($req, $id, $service) = @_;
            return 404;
        },
        GET => qr{^projects$} => sub {
            my ($req) = @_;
            return (200, \@projects) unless ($req->[1] =~ /search=([^&]+)/);
            my $str = $1;
            my @res;
            foreach (@projects) {
                if ($_->{name} =~ /\Q$str\E/) {
                    push @res, $_;
                }
            }
            return 200, \@res;
        },
        GET => qr{^projects/([a-z]+)(?:%2F(\w+))*$} => sub {
            my ($req, @path) = @_;
            my $repo = pop @path;
            my $path = join '/', @path;
            foreach (@projects) {
                if ($_->{namespace}->{name} eq $path and $_->{path} eq $repo) {
                    return 200, $_;
                }
            }
            return 404;
        },
        GET => qr{^projects/(\d+)$} => sub {
            my ($req, $id) = @_;
            return 404 unless ($_ = $projects[$id - 1]);
            return 200, $_;
        },
        PUT => qr{^projects/(\d+)} => sub {
            my ($req, $id) = @_;
            return 404 unless ($_ = $projects[$id - 1]);
            my $content = JSON::from_json($req->[2]->{content});
            foreach my $k (keys %$content) {
                $_->{$k} = $content->{$k};
            }
            return 200, {};
        },
        POST => qr{^projects/(\d+)/hooks} => sub {
            my ($req, $id) = @_;
            return 404 unless ($_ = $projects[$id - 1]);
            my $content = JSON::from_json($req->[2]->{content});
            push @{ $_->{hooks} }, $content;
            return 200, {};
        },
        POST => qr{^projects/(\d+)/repository/branches} => sub {
            return 200, {};
        },
        DELETE => qr{^projects/(\d+)/repository/branches/([\w\-\.]+)$} => sub {
            return 200, {};
        },
    );
    return $api;
}

1;
