use Test::More tests => 8;

BEGIN {
    use_ok('Devscripts::Uscan::Config');
    use_ok('Devscripts::Uscan::Output');
}

@Devscripts::Config::config_files = ('t/config1');
@ARGV = ( '--download-version', '1.0', '-dd', '--no-verbose' );

ok(
    $conf = Devscripts::Uscan::Config->new->parse,
    'USCAN_SYMLINK=rename + --download-version'
);

ok($conf->symlink eq 'rename', ' symlink=rename');
ok($conf->download_version eq '1.0',' download_version=1.0');
ok($conf->user_agent =~ /^Debian uscan/, qq' user agent starts with "Debian uscan" ($conf->{user_agent})');
ok($conf->download == 2, 'Force download');
ok($verbose == 0, 'Verbose is disabled');
