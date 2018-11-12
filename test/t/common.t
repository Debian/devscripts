#!/usr/bin/perl

package Config::Test;

use Moo;

extends 'Devscripts::Config';

use constant keys => [
    ['test!',  'TEST', 'bool', 1],
    ['str=s',  'STR',  qr/^a/, 'ab'],
    ['str2=s', 'STR2', qr/^a/, 'bb'],
    ['array=s', 'ARRAY', undef, sub { [] }],
];

package main;

use Test::More tests => 39;

BEGIN {
    use_ok('Devscripts::Config');
}

my $conf;
$Devscripts::Output::die_on_error = 0;

@Devscripts::Config::config_files = ();

ok($conf = Config::Test->new->parse, 'No conf files, no args');
ok($conf->{test} == 1,    ' test=1');
ok($conf->{str} eq 'ab',  ' str=ab');
ok($conf->{str2} eq 'bb', ' str2=bb');

@Devscripts::Config::config_files = ('t/config1');

ok($conf = Config::Test->new->parse, 'Conf files, no args');
ok($conf->{test} == 0,    ' test=0');
ok($conf->{str} eq 'az',  ' str=az');
ok($conf->{str2} eq 'a1', ' str2=a1');
if (ok(ref $conf->{array}, ' array')) {
    ok($conf->{array}->[0] eq "b c",    '  "b c" found');
    ok($conf->{array}->[1] eq "a",      '  "a" found');
    ok($conf->{array}->[2] eq "d",      '  "d" found');
    ok(scalar @{ $conf->{array} } == 3, '  3 elements');
}

@ARGV = ('--noconf');

ok($conf = Config::Test->new->parse, '--noconf');
ok($conf->{test} == 1,    ' test=1');
ok($conf->{str} eq 'ab',  ' str=ab');
ok($conf->{str2} eq 'bb', ' str2=bb');

@ARGV = ('--conffile', 't/config2');

ok($conf = Config::Test->new->parse, '--conffile t/config2');
ok($conf->{test} == 1,      ' test=1');
ok($conf->{str} eq 'ab',    ' str=ab');
ok($conf->{str2} eq 'axzx', ' str2=axzx');

@ARGV = ('--conffile', '+t/config2');

ok($conf = Config::Test->new->parse, '--conffile +t/config2');
ok($conf->{test} == 0,      ' test=0');
ok($conf->{str} eq 'az',    ' str=az');
ok($conf->{str2} eq 'axzx', ' str2=axzx');

@ARGV = ('--test', '--str2=ac');

ok($conf = Config::Test->new->parse, '--test --str2=ac');
ok($conf->{test} == 1,    ' test=1');
ok($conf->{str} eq 'az',  ' str=az');
ok($conf->{str2} eq 'ac', ' str2=ac');

@ARGV = ('--noconf', '--str2', 'ac', '--notest');

ok($conf = Config::Test->new->parse, '--noconf --no-test --str2=ac');
ok($conf->{test} == 0,    ' test=0');
ok($conf->{str} eq 'ab',  ' str=ab');
ok($conf->{str2} eq 'ac', ' str2=ac');

@ARGV = ('--noconf', '--array', 'a', '--array=b');
ok($conf = Config::Test->new->parse, '--noconf --array a --array=b');
ok(ref $conf->{array},         'Multiple options are allowed');
ok($conf->{array}->[0] eq 'a', ' first value is a');
ok($conf->{array}->[1] eq 'b', ' second value is b');

# Redirect STDERR to $out;
my $out;
{
    no warnings;
    open F, ">&STDERR";
}
close STDERR;
open STDERR, '>', \$out;
eval {
    @ARGV = ('--noconf', '--str2', 'bc');
    $conf = Config::Test->new->parse;
};

# Restore STDERR
close STDERR;
open STDERR, ">&F";
fail($@) if ($@);
ok($out =~ /Bad str2 value/, '--str2=bc is rejected');

