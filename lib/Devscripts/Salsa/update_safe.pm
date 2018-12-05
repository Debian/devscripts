# launches check_repo and launch uscan_repo if user agrees with this changes
package Devscripts::Salsa::update_safe;

use strict;
use Devscripts::Output;
use Moo::Role;

with 'Devscripts::Salsa::check_repo';
with 'Devscripts::Salsa::update_repo';

sub update_safe {
    my $self = shift;
    my ($res, $fails) = $self->_check_repo(@_);
    return 0 unless ($res);
    return $res
      if (ds_prompt("$res packages misconfigured, update them ? (Y/n) ")
        =~ refuse);
    $Devscripts::Salsa::update_repo::prompt = 0;
    return $self->_update_repo(@$fails);
}

1;
