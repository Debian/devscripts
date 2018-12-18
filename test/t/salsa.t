#!/usr/bin/env perl

my $skip;
use File::Temp 'tempdir';
use Test::More;
use strict;

BEGIN {
    eval "use Test::Output;use GitLab::API::v4;";
    $skip = $@ ? 1 : 0;
}

my $pwd = `pwd`;
chomp $pwd;
my ($api, $gitdir);

sub mkDebianDir {
    my $tmpdir = tempdir(CLEANUP => 1);
    chdir $tmpdir;
    system "git init";
    system "git config user.name 'Joe Developer'";
    system 'git config user.email "jd@debian.org"';
    mkdir 'debian';
    open F, ">debian/changelog";
    print F <<EOF;
foobar (0-1) unstable; urgency=low

  * Initial release

 -- Joe Developer <jd\@debian.org>  Mon, 02 Nov 2013 22:21:31 -0100
EOF
    close F;
    open F, ">README.md";
    print F <<EOF;
# Salsa test
EOF
    system "git add *";
    system "git commit -a -m 'Salsa test'";
    system "git checkout -b dev";
    chdir $pwd;
    return $tmpdir;
}

sub run {
    my ($result, $out, @list) = @_;
    @ARGV = ('--no-cache', @list);
    my ($res, $salsa);
    combined_like(
        sub {
            $salsa = Devscripts::Salsa->new({ api => $api });
            $salsa->config->git_server_url($gitdir . '/');
            $res = $salsa->run;
        },
        $out,
        "command: " . join(' ', @list));
    ok($res =~ /^$result$/i, " result is $result");
}

sub run_debug {
    my ($result, $out, @list) = @_;
    @ARGV = ('--no-cache', @list);
    my ($res, $salsa);
    $salsa = Devscripts::Salsa->new({ api => $api });
    $salsa->config->git_server_url($gitdir . '/');
    $res = $salsa->run;
}

SKIP: {
    skip "Missing dependencies" if ($skip);
    require './t/salsa.pm';
    $gitdir = tempdir(CLEANUP => 1);
    sleep 1;
    mkdir "$gitdir/me" or die "$gitdir/me: $!";

    $api = api($gitdir);

    use_ok 'Devscripts::Salsa';
    $Devscripts::Output::die_on_error = 0;
    @Devscripts::Config::config_files = ('t/salsa.conf');

    # Search methods
    run(0, qr/Id\s*:\s*11\nUsername\s*:\s*me/s, 'whoami');
    run(0, qr/Id\s*:\s*2099\nName/s,            'search_group', 'js-team');
    run(0, qr/Id\s*:\s*2099\nName/s,            'search_group', 2099);
    run(0, qr/Id.*\nUsername\s*: me/s,          'search_user', 'me');
    run(0, qr/Id.*\nUsername\s*: me/s,          'search_user', 'm');
    run(0, qr/Id.*\nUsername\s*: me/s,          'search_user', 11);

    # Project methods
    my $repo = mkDebianDir;
    run(0, qr/Project .*created/s, '-C', $repo, '--verbose', 'push_repo', '.');
    chdir $pwd;
    $repo = tempdir(CLEANUP => 1);
    run(0, qr/KGB hook added.*Tagpending hook added/s,
        'update_repo', '--kgb', '--irc=debian', '--tagpending', 'foobar');
    run(0, qr/foobar\s*:\s*OK/s,
        'update_safe', '--kgb', '--irc=debian', '--tagpending', 'foobar');
    run(0, qr{Full path\s*:\s*me/foobar}, 'search', 'foobar');
    run(0, qr{Configuring foobar},
        'rename_branch', 'foobar', '--source-branch=dev',
        '--dest-branch=dev2');
}

done_testing;

1;
