use Test::More tests => 6;

BEGIN {
    use_ok('Devscripts::Uscan::Config');
}

@Devscripts::Config::config_files = ('t/config1');
@ARGV = ( '--download-version', '1.0', '-dd' );

ok(
    $conf = Devscripts::Uscan::Config->new->parse,
    'USCAN_SYMLINK=rename + --download-version'
);

ok($conf->symlink eq 'rename', ' symlink=rename');
ok($conf->download_version eq '1.0',' download_version=1.0');
ok($conf->user_agent =~ /^Debian uscan/, qq' user agent starts with "Debian uscan" ($conf->{user_agent})');
ok($conf->download == 2, 'Force download');
