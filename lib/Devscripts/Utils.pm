package Devscripts::Utils;

use strict;
use Devscripts::Output;
use Exporter 'import';
use IPC::Run qw(run);

our @EXPORT = qw(ds_exec ds_exec_no_fail);

sub ds_exec_no_fail {
    {
        local $, = ' ';
        ds_debug "Execute: @_...";
    }
    run \@_, '>', '/dev/null';
    return $?;
}

sub ds_exec {
    {
        local $, = ' ';
        ds_debug "Execute: @_...";
    }
    run \@_;
    if ($?) {
        local $, = ' ';
        ds_die "Command failed (@_)";
    }
}

1;
