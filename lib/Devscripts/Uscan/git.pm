package Devscripts::Uscan::git;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Dpkg::IPC;
use Exporter qw(import);
use File::Path 'remove_tree';

our @EXPORT = qw(git_search git_upstream_url git_newfile_base git_clean);

######################################################
# search $newfile $newversion (git mode/versionless)
######################################################
sub git_search {
    my ($self) = @_;
    my ( $newfile, $newversion );
    if ( $self->versionless ) {
        $newfile = $self->parse_result->{filepattern};  # HEAD or heads/<branch>
        if ( $self->pretty eq 'describe' ) {
            $self->gitmode('full');
        }
        if (    $self->gitmode eq 'shallow'
            and $self->parse_result->{filepattern} eq 'HEAD' )
        {
            uscan_exec(
                'git', 'clone', '--bare', '--depth=1',
                $self->parse_result->{base},
                "$self->{config}->{destdir}/" . $self->gitrepo_dir
            );
            $self->downloader->gitrepo_state(1);
        }
        elsif ( $self->gitmode eq 'shallow'
            and $self->parse_result->{filepattern} ne 'HEAD' )
        {    # heads/<branch>
            $newfile =~ s&^heads/&&;    # Set to <branch>
            uscan_exec(
                'git',
                'clone',
                '--bare',
                '--depth=1',
                '-b',
                "$newfile",
                $self->parse_result->{base},
                "$self->{config}->{destdir}/" . $self->gitrepo_dir
            );
            $self->downloader->gitrepo_state(1);
        }
        else {
            uscan_exec(
                'git', 'clone', '--bare',
                $self->parse_result->{base},
                "$self->{config}->{destdir}/" . $self->gitrepo_dir
            );
            $self->downloader->gitrepo_state(2);
        }
        if ( $self->pretty eq 'describe' ) {

            # use unannotated tags to be on safe side
            spawn(
                exec => [
                    'git',
                    "--git-dir=$self->{config}->{destdir}/$self->{gitrepo_dir}",
                    'describe',
                    '--tags'
                ],
                wait_child => 1,
                to_string  => \$newversion
            );
            $newversion =~ s/-/./g;
            chomp($newversion);
            if (
                mangle(
                    $self->watchfile,  \$self->line,
                    'uversionmangle:', \@{ $self->uversionmangle },
                    \$newversion
                )
              )
            {
                return undef;
            }
        }
        else {
            spawn(
                exec => [
                    'git',
                    "--git-dir=$self->{config}->{destdir}/$self->{gitrepo_dir}",
                    'log',
                    '-1',
                    "--date=format:$self->{date}",
                    "--pretty=$self->{pretty}"
                ],
                wait_child => 1,
                to_string  => \$newversion
            );
            chomp($newversion);
        }
    }
    ################################################
    # search $newfile $newversion (git mode w/tag)
    ################################################
    elsif ( $self->mode eq 'git' ) {
        uscan_verbose "Execute: git ls-remote $self->{base}";
        open( REFS, "-|", 'git', 'ls-remote', $self->parse_result->{base} )
          || uscan_die "$progname: you must have the git package installed";
        my @refs;
        my $ref;
        my $version;
        while (<REFS>) {
            chomp;
            uscan_debug "$_";
            if (m&^\S+\s+([^\^\{\}]+)$&) {
                $ref = $1;    # ref w/o ^{}
                foreach my $_pattern ( @{ $self->patterns } ) {
                    $version = join( ".",
                        map { $_ if defined($_) } $ref =~ m&^$_pattern$& );
                    if (
                        mangle(
                            $self->watchfile,  \$self->line,
                            'uversionmangle:', \@{ $self->uversionmangle },
                            \$version
                        )
                      )
                    {
                        return undef;
                    }
                    push @refs, [ $version, $ref ];
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
            if ( $self->shared->{download_version} ) {

# extract ones which has $version in the above loop matched with $download_version
                my @vrefs =
                  grep { $$_[0] eq $self->shared->{download_version} } @refs;
                if (@vrefs) {
                    ( $newversion, $newfile ) = @{ $vrefs[0] };
                }
                else {
                    uscan_warn
                      "$progname warning: In $self->{watchfile} no matching"
                      . " refs for version $self->{download_version}"
                      . " in watch line\n  $self->{line}";
                    return undef;
                }

            }
            else {
                ( $newversion, $newfile ) = @{ $refs[0] };
            }
        }
        else {
            uscan_warn "$progname warning: In $self->{watchfile},\n"
              . " no matching refs for watch line\n"
              . " $self->{line}";
            return undef;
        }
    }
    return ( $newversion, $newfile );
}

sub git_upstream_url {
    my ($self) = @_;
    my $upstream_url =
      $self->parse_result->{base} . ' ' . $self->search_result->{newfile};
    return $upstream_url;
}

sub git_newfile_base {
    my ($self) = @_;
    my $zsuffix = get_suffix( $self->compression );
    my $newfile_base =
      "$self->{pkg}-$self->{search_result}->{newversion}.tar.$zsuffix";
    return $newfile_base;
}

sub git_clean {
    my ($self) = @_;

    # If git cloned repo exists and not --debug ($verbose=1) -> remove it
    if ( $self->downloader->gitrepo_state > 0 and $verbose < 1 ) {
        my $err;
        remove_tree "$self->{config}->{destdir}/" . $self->gitrepo_dir,
          { error => \$err };
        if (@$err) {
            local $, = "\n\t";
            uscan_warn "Errors during git repo clean:\n\t@$err";
        }
        $self->downloader->gitrepo_state(0);
    }
    return 0;
}

1;
