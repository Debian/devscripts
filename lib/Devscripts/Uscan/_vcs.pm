# Common sub shared between git and svn
package Devscripts::Uscan::_vcs;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Exporter 'import';
use File::Basename;

our @EXPORT = ('get_refs');

our $progname = basename($0);

sub _vcs_newfile_base {
    my ($self) = @_;
    my $zsuffix = get_suffix($self->compression);
    my $newfile_base
      = "$self->{pkg}-$self->{search_result}->{newversion}.tar.$zsuffix";
    return $newfile_base;
}

sub get_refs {
    my ($self, $command, $ref_pattern, $package) = @_;
    my @command = @$command;
    my ($newfile, $newversion);
    {
        local $, = ' ';
        uscan_verbose "Execute: @command";
    }
    open(REFS, "-|", @command)
      || uscan_die "$progname: you must have the $package package installed";
    my @refs;
    my $ref;
    my $version;
    while (<REFS>) {
        chomp;
        uscan_debug "$_";
        if ($_ =~ $ref_pattern) {
            $ref = $1;
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
    return ($newversion, $newfile);
}

1;
