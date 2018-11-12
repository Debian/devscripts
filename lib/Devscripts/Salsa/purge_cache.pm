# Empties the Devscripts::JSONCache
package Devscripts::Salsa::purge_cache;

use strict;
use Devscripts::Output;
use Moo::Role;

sub purge_cache {
    my @keys = keys %{ $_[0]->_cache };
    delete $_[0]->_cache->{$_} foreach (@keys);
    ds_verbose "Cache empty";
    return 0;
}

1;
