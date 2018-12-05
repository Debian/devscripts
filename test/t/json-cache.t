use Test::More;

use strict;

SKIP: {
    eval "use JSON";
    skip "JSON isn't available" if ($@);
    use_ok('Devscripts::JSONCache');

    my %c;

    ok(tie(%c, 'Devscripts::JSONCache', 'test.json'), 'No file');
    $c{a} = 1;
    untie %c;
    ok(-r 'test.json', 'Cache created');
    ok(tie(%c, 'Devscripts::JSONCache', 'test.json'), 'Reuse file');
    ok($c{a} == 1, 'Value saved');
    untie %c;
    unlink 'test.json';

    my %c2;
    eval { tie(%c2, 'Devscripts::JSONCache', 'zzz/test.json') };
    ok($@, "Build refused if write isn't possible");
}
done_testing();
