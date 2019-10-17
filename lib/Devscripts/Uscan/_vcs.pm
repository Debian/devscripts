# Common sub shared between git and svn
package Devscripts::Uscan::_vcs;

use strict;
use Devscripts::Uscan::Utils;

sub _vcs_newfile_base {
    my ($self) = @_;
    my $zsuffix = get_suffix($self->compression);
    my $newfile_base
      = "$self->{pkg}-$self->{search_result}->{newversion}.tar.$zsuffix";
    return $newfile_base;
}

1;
