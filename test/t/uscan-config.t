use Test::More tests => 4;

BEGIN {
    use_ok('Devscripts::Uscan::Config');
}

@Devscripts::Config::config_files = ('t/config1');
@ARGV = ( '--download-version', '1.0' );

ok(
    $conf = Devscripts::Uscan::Config->new->parse,
    'USCAN_SYMLINK=rename + --download-version'
);

ok($conf->symlink eq 'rename', ' symlink=rename');
ok($conf->download_version eq '1.0',' download_version=1.0');
