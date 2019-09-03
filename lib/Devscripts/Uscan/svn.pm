package Devscripts::Uscan::svn;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Dpkg::IPC;
use File::Path 'remove_tree';
use Moo::Role;

######################################################
# search $newfile $newversion (git mode/versionless)
######################################################
sub svn_search {
    my ($self) = @_;
    my ($newfile, $newversion);
    if ($self->versionless) {
        $newfile = $self->parse_result->{base};
            spawn(
                exec => [
                    'svn',
                    'info',
                    '--show-item',
                    'revision',
                    '--no-newline',
                    $self->parse_result->{base}
                ],
                wait_child => 1,
                to_string  => \$newversion
            );
            # FIXME: default for 'pretty' has to be changed
            if( $self->pretty !~ /git/ ) {
                $newversion = sprintf '0.0~svn%d', $newversion;
            } else {
                $newversion = sprintf $self->pretty, $newversion;
            }
            chomp($newversion);
    }
    ################################################
    # search $newfile $newversion (git mode w/tag)
    ################################################
    elsif ($self->mode eq 'svn') {
        my @args = ('list', $self->parse_result->{base});
        {
            local $, = ' ';
            uscan_verbose "Execute: svn @args";
        }
        open(REFS, "-|", 'svn', @args)
          || uscan_die "$progname: you must have the subversion package installed";
        my @refs;
        my $ref;
        my $version;
        while (<REFS>) {
            chomp;
            uscan_debug "$_";
                $ref = $_;
                foreach my $_pattern (@{ $self->patterns }) {
                    $version = join(".",
                        map { $_ if defined($_) } $ref =~ m&^$_pattern$&);
                    if (
                        mangle(
                            $self->watchfile,  \$self->line,
                            'uversionmangle:', \@{ $self->uversionmangle },
                            \$version
                        )
                    ) {
                        return undef;
                    }
                    push @refs, [$version, $ref];
                }
        }
        if (@refs) {
            @refs = Devscripts::Versort::upstream_versort(@refs);
            my $msg = "Found the following matching refs:\n";
            foreach my $ref (@refs) {
                $msg .= "     $$ref[1] ($$ref[0])\n";
            }
            uscan_verbose "$msg";
            if ($self->shared->{download_version}
                and not $self->versionmode eq 'ignore') {

# extract ones which has $version in the above loop matched with $download_version
                my @vrefs
                  = grep { $$_[0] eq $self->shared->{download_version} } @refs;
                if (@vrefs) {
                    ($newversion, $newfile) = @{ $vrefs[0] };
                } else {
                    uscan_warn
                      "$progname warning: In $self->{watchfile} no matching"
                      . " refs for version "
                      . $self->shared->{download_version}
                      . " in watch line\n  "
                      . $self->{line};
                    return undef;
                }

            } else {
                ($newversion, $newfile) = @{ $refs[0] };
            }
        } else {
            uscan_warn "$progname warning: In $self->{watchfile},\n"
              . " no matching refs for watch line\n"
              . " $self->{line}";
            return undef;
        }
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

sub svn_newfile_base {
    my ($self) = @_;
    my $zsuffix = get_suffix($self->compression);
    my $newfile_base
      = "$self->{pkg}-$self->{search_result}->{newversion}.tar.$zsuffix";
    return $newfile_base;
}

sub svn_clean {}

1;
