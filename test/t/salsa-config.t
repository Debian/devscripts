use Test::More tests => 8;

BEGIN {
    use_ok('Devscripts::Salsa::Config');
}

@Devscripts::Config::config_files = ('t/config1');
@ARGV = ('push_repo', '--disable-kgb', '--tagpending', '--irker');

ok($conf = Devscripts::Salsa::Config->new->parse, 'Parse');

ok(($conf->kgb == 0 and $conf->disable_kgb), 'KGB disabled');
ok(($conf->tagpending and $conf->disable_tagpending == 0),
    'Tagpending enabled');
ok(($conf->enable_issues == 0 and $conf->disable_issues),
    'Enable-issues disabled');
ok(($conf->email == 0     and $conf->disable_email == 0), 'Email ignored');
ok(($conf->enable_mr == 1 and $conf->disable_mr == 0),    'MR enabled');
ok(($conf->irker == 1     and $conf->disable_irker == 0), 'Irker enabled');
