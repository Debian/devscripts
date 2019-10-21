package Devscripts::Uscan::svn;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::_vcs;
use Dpkg::IPC;
use File::Path 'remove_tree';
use Moo::Role;

######################################################
# search $newfile $newversion (svn mode/versionless)
######################################################
sub svn_search {
    my ($self) = @_;
    my ($newfile, $newversion);
    if ($self->versionless) {
        $newfile = $self->parse_result->{base};
        spawn(
            exec => [
                'svn',          'info',
                '--show-item',  'last-changed-revision',
                '--no-newline', $self->parse_result->{base}
            ],
            wait_child => 1,
            to_string  => \$newversion
        );
        chomp($newversion);
        $newversion = sprintf '0.0~svn%d', $newversion;
        if (
            mangle(
                $self->watchfile,  \$self->line,
                'uversionmangle:', \@{ $self->uversionmangle },
                \$newversion
            )
        ) {
            return undef;
        }

    }
    ################################################
    # search $newfile $newversion (svn mode w/tag)
    ################################################
    elsif ($self->mode eq 'svn') {
        my @args = ('list', $self->parse_result->{base});
        ($newversion, $newfile)
          = get_refs($self, ['svn', @args], qr/(.+)/, 'subversion');
        return undef if !defined $newversion;
    }
    return ($newversion, $newfile);
}

sub svn_upstream_url {
    my ($self) = @_;
    my $upstream_url = $self->parse_result->{base};
    if (!$self->versionless) {
        $upstream_url .= '/' . $self->search_result->{newfile};
    }
    return $upstream_url;
}

*svn_newfile_base = \&Devscripts::Uscan::_vcs::_vcs_newfile_base;

sub svn_clean { }

1;
