package Devscripts::Uscan::Downloader;

use strict;
use Cwd qw/cwd abs_path/;
use Devscripts::Uscan::CatchRedirections;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Moo;

our $haveSSL;

BEGIN {
    eval { require LWP::UserAgent; };
    if ($@) {
        my $progname = basename($0);
        if ($@ =~ /^Can\'t locate LWP\/UserAgent\.pm/) {
            die "$progname: you must have the libwww-perl package installed\n"
              . "to use this script";
        } else {
            die "$progname: problem loading the LWP::UserAgent module:\n  $@\n"
              . "Have you installed the libwww-perl package?";
        }
    }
    eval { require LWP::Protocol::https; };
    $haveSSL = $@ ? 0 : 1;
}

has agent =>
  (is => 'rw', default => sub { "Debian uscan $main::uscan_version" });
has timeout => (is => 'rw');
has passive => (
    is      => 'rw',
    default => 'default',
    trigger => sub {
        my ($self, $nv) = @_;
        if ($nv) {
            uscan_verbose "Set passive mode: $self->{passive}";
            $ENV{'FTP_PASSIVE'} = $self->passive;
        } elsif ($ENV{'FTP_PASSIVE'}) {
            uscan_verbose "Unset passive mode";
            delete $ENV{'FTP_PASSIVE'};
        }
    });
has destdir => (is => 'rw');

# 0: no repo, 1: shallow clone, 2: full clone
has gitrepo_state => (
    is      => 'rw',
    default => sub { 0 });
has user_agent => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $user_agent
          = Devscripts::Uscan::CatchRedirections->new(env_proxy => 1);
        $user_agent->timeout($self->timeout);
        $user_agent->agent($self->agent);

        # Strip Referer header for Sourceforge to avoid SF sending back a
        # "200 OK" with a <meta refresh=...> redirect
        $user_agent->add_handler(
            'request_prepare' => sub {
                my ($request, $ua, $h) = @_;
                $request->remove_header('Referer');
            },
            m_hostname => 'sourceforge.net',
        );
        $self->{user_agent} = $user_agent;
    });

has ssl => (is => 'rw', default => sub { $haveSSL });

sub download ($$$$$$$) {
    my ($self, $url, $fname, $optref, $base, $pkg_dir, $mode) = @_;
    my ($request, $response);
    $mode ||= $optref->mode;
    if ($mode eq 'http') {
        if ($url =~ /^https/ and !$self->ssl) {
            uscan_die "$progname: you must have the "
              . "liblwp-protocol-https-perl package installed\n"
              . "to use https URLs";
        }

        # substitute HTML entities
        # Is anything else than "&amp;" required?  I doubt it.
        uscan_verbose "Requesting URL:\n   $url";
        my $headers = HTTP::Headers->new;
        $headers->header('Accept'  => '*/*');
        $headers->header('Referer' => $base);
        $request = HTTP::Request->new('GET', $url, $headers);
        $response = $self->user_agent->request($request, $fname);
        if (!$response->is_success) {
            uscan_warn((defined $pkg_dir ? "In directory $pkg_dir, d" : "D")
                . "ownloading\n  $url failed: "
                  . $response->status_line);
            return 0;
        }
    } elsif ($mode eq 'ftp') {
        uscan_verbose "Requesting URL:\n   $url";
        $request = HTTP::Request->new('GET', "$url");
        $response = $self->user_agent->request($request, $fname);
        if (!$response->is_success) {
            uscan_warn(defined $pkg_dir ? "In directory $pkg_dir, d" : "D")
              . "ownloading\n  $url failed: "
              . $response->status_line;
            return 0;
        }
    } else {    # elsif ($$optref{'mode'} eq 'git')
        my $destdir = $self->destdir;
        my $curdir  = cwd();
        $fname =~ m%(.*)/([^/]*)-([^_/-]*)\.tar\.(gz|xz|bz2|lzma)%;
        my $dst     = $1;
        my $abs_dst = abs_path($dst);
        my $pkg     = $2;
        my $ver     = $3;
        my $suffix  = $4;
        my $gitrepo_dir
          = "$pkg-temporary.$$.git";    # same as outside of downloader
        my ($gitrepo, $gitref) = split /[[:space:]]+/, $url, 2;

        if ($self->gitrepo_state == 0) {
            if ($optref->gitmode eq 'shallow') {
                uscan_exec('git', 'clone', '--bare', '--depth=1', $base,
                    "$destdir/$gitrepo_dir");
                $self->gitrepo_state(1);
            } else {
                uscan_exec('git', 'clone', '--bare', $base,
                    "$destdir/$gitrepo_dir");
                $self->gitrepo_state(2);
            }
        }
        uscan_exec_no_fail(
            'git',                 "--git-dir=$destdir/$gitrepo_dir",
            'archive',             '--format=tar',
            "--prefix=$pkg-$ver/", "--output=$abs_dst/$pkg-$ver.tar",
            $gitref
          ) == 0
          or uscan_die("git archive failed");

        chdir "$abs_dst" or uscan_die("Unable to chdir($abs_dst): $!");
        if ($suffix eq 'gz') {
            uscan_exec("gzip", "-n", "-9", "$pkg-$ver.tar");
        } elsif ($suffix eq 'xz') {
            uscan_exec("xz", "$pkg-$ver.tar");
        } elsif ($suffix eq 'bz2') {
            uscan_exec("bzip2", "$pkg-$ver.tar");
        } elsif ($suffix eq 'lzma') {
            uscan_exec("lzma", "$pkg-$ver.tar");
        } else {
            uscan_warn "Unknown suffix file to repack: $suffix";
            exit 1;
        }
        chdir "$curdir" or uscan_die("Unable to chdir($curdir): $!");
    }
    return 1;
}

1;
