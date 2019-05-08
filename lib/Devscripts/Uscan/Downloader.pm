package Devscripts::Uscan::Downloader;

use strict;
use Cwd qw/cwd abs_path/;
use Devscripts::Uscan::CatchRedirections;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Dpkg::IPC;
use File::DirList;
use File::Find;
use File::Temp qw/tempdir/;
use File::Touch;
use Moo;
use URI;

our $haveSSL;

has git_upstream => (is => 'rw');

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
has pasv    => (
    is      => 'rw',
    default => 'default',
    trigger => sub {
        my ($self, $nv) = @_;
        if ($nv) {
            uscan_verbose "Set passive mode: $self->{pasv}";
            $ENV{'FTP_PASSIVE'} = $self->pasv;
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
has git_export_all => (
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

has headers => (
    is      => 'ro',
    default => sub { {} });

sub download ($$$$$$$$) {
    my ($self, $url, $fname, $optref, $base, $pkg_dir, $pkg, $mode) = @_;
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
        my $uri_o = URI->new($url);
        foreach my $k (keys %{ $self->headers }) {
            if ($k =~ /^(.*?)@(.*)$/) {
                my $baseUrl = $1;
                my $hdr     = $2;
                if ($url =~ m#^\Q$baseUrl\E(?:/.*)?$#) {
                    $headers->header($hdr => $self->headers->{$k});
                    uscan_verbose "Set per-host custom header $hdr for $url";
                } else {
                    uscan_debug "$url does not start with $1";
                }
            } else {
                uscan_warn "Malformed http-header: $k";
            }
        }
        $request  = HTTP::Request->new('GET', $url, $headers);
        $response = $self->user_agent->request($request, $fname);
        if (!$response->is_success) {
            uscan_warn((defined $pkg_dir ? "In directory $pkg_dir, d" : "D")
                . "ownloading\n  $url failed: "
                  . $response->status_line);
            return 0;
        }
    } elsif ($mode eq 'ftp') {
        uscan_verbose "Requesting URL:\n   $url";
        $request  = HTTP::Request->new('GET', "$url");
        $response = $self->user_agent->request($request, $fname);
        if (!$response->is_success) {
            uscan_warn(
                  (defined $pkg_dir ? "In directory $pkg_dir, d" : "D")
                . "ownloading\n  $url failed: "
                  . $response->status_line);
            return 0;
        }
    } else {    # elsif ($$optref{'mode'} eq 'git')
        my $destdir = $self->destdir;
        my $curdir  = cwd();
        $fname =~ m%(.*)/$pkg-([^_/]*)\.tar\.(gz|xz|bz2|lzma|zstd?)%;
        my $dst     = $1;
        my $abs_dst = abs_path($dst);
        my $ver     = $2;
        my $suffix  = $3;
        my $gitrepo_dir
          = "$pkg-temporary.$$.git";    # same as outside of downloader
        my ($gitrepo, $gitref) = split /[[:space:]]+/, $url, 2;
        my $clean = sub {
            uscan_exec_no_fail('rm', '-fr', $gitrepo_dir);
        };
        my $clean_and_die = sub {
            $clean->();
            uscan_die @_;
        };

        if ($mode eq 'svn') {
            my $tempdir   = tempdir(CLEANUP => 1);
            my $old_umask = umask(oct('022'));
            uscan_exec('svn', 'export', $url, "$tempdir/$pkg-$ver");
            umask($old_umask);
            find({
                    wanted => sub {
                        return if !-d $File::Find::name;
                        my ($newest) = grep { $_ ne '.' && $_ ne '..' }
                          map { $_->[13] } @{ File::DirList::list($_, 'M') };
                        return if !$newest;
                        my $touch
                          = File::Touch->new(reference => $_ . '/' . $newest);
                        $touch->touch($_);
                    },
                    bydepth  => 1,
                    no_chdir => 1,
                },
                "$tempdir/$pkg-$ver"
            );
            uscan_exec(
                'tar',          '-C',
                $tempdir,       '--sort=name',
                '--owner=root', '--group=root',
                '-cvf',         "$abs_dst/$pkg-$ver.tar",
                "$pkg-$ver"
            );
        } elsif ($self->git_upstream) {
            my ($infodir, $attr_file, $attr_bkp);
            if ($self->git_export_all) {
                # override any export-subst and export-ignore attributes
                spawn(
                    exec      => [qw|git rev-parse --git-path info/|],
                    to_string => \$infodir,
                );
                chomp $infodir;
                mkdir $infodir unless -e $infodir;
                spawn(
                    exec => [qw|git rev-parse --git-path info/attributes|],
                    to_string => \$attr_file,
                );
                chomp $attr_file;
                spawn(
                    exec =>
                      [qw|git rev-parse --git-path info/attributes-uscan|],
                    to_string => \$attr_bkp,
                );
                chomp $attr_bkp;
                rename $attr_file, $attr_bkp if -e $attr_file;
                my $attr_fh;

                unless (open($attr_fh, '>', $attr_file)) {
                    rename $attr_bkp, $attr_file if -e $attr_bkp;
                    uscan_die("could not open $attr_file for writing");
                }
                print $attr_fh "* -export-subst\n* -export-ignore\n";
                close $attr_fh;
            }

            uscan_exec_no_fail('git', 'archive', '--format=tar',
                "--prefix=$pkg-$ver/", "--output=$abs_dst/$pkg-$ver.tar",
                $gitref) == 0
              or $clean_and_die->("git archive failed");

            if ($self->git_export_all) {
                # restore attributes
                if (-e $attr_bkp) {
                    rename $attr_bkp, $attr_file;
                } else {
                    unlink $attr_file;
                }
            }
        } else {
            if ($self->gitrepo_state == 0) {
                if ($optref->gitmode eq 'shallow') {
                    my $tag = $gitref;
                    $tag =~ s#^refs/(?:tags|heads)/##;
                    uscan_exec('git', 'clone', '--bare', '--depth=1', '-b',
                        $tag, $base, "$destdir/$gitrepo_dir");
                    $self->gitrepo_state(1);
                } else {
                    uscan_exec('git', 'clone', '--bare', $base,
                        "$destdir/$gitrepo_dir");
                    $self->gitrepo_state(2);
                }
            }
            if ($self->git_export_all) {
                # override any export-subst and export-ignore attributes
                my ($infodir, $attr_file);
                spawn(
                    exec => [
                        'git', "--git-dir=$destdir/$gitrepo_dir",
                        'rev-parse', '--git-path', 'info/'
                    ],
                    to_string => \$infodir,
                );
                chomp $infodir;
                mkdir $infodir unless -e $infodir;
                spawn(
                    exec => [
                        'git',       "--git-dir=$destdir/$gitrepo_dir",
                        'rev-parse', '--git-path',
                        'info/attributes'
                    ],
                    to_string => \$attr_file,
                );
                chomp $attr_file;
                my $attr_fh;
                $clean_and_die->("could not open $attr_file for writing")
                  unless open($attr_fh, '>', $attr_file);
                print $attr_fh "* -export-subst\n* -export-ignore\n";
                close $attr_fh;
            }

            uscan_exec_no_fail(
                'git',                 "--git-dir=$destdir/$gitrepo_dir",
                'archive',             '--format=tar',
                "--prefix=$pkg-$ver/", "--output=$abs_dst/$pkg-$ver.tar",
                $gitref
              ) == 0
              or $clean_and_die->("git archive failed");
        }

        chdir "$abs_dst" or $clean_and_die->("Unable to chdir($abs_dst): $!");
        if ($suffix eq 'gz') {
            uscan_exec("gzip", "-n", "-9", "$pkg-$ver.tar");
        } elsif ($suffix eq 'xz') {
            uscan_exec("xz", "$pkg-$ver.tar");
        } elsif ($suffix eq 'bz2') {
            uscan_exec("bzip2", "$pkg-$ver.tar");
        } elsif ($suffix eq 'lzma') {
            uscan_exec("lzma", "$pkg-$ver.tar");
            #} elsif ($suffix =~ /^zstd?$/) {
            #    uscan_exec("zstd", "$pkg-$ver.tar");
        } else {
            $clean_and_die->("Unknown suffix file to repack: $suffix");
        }
        chdir "$curdir" or $clean_and_die->("Unable to chdir($curdir): $!");
        $clean->();
    }
    return 1;
}

1;
