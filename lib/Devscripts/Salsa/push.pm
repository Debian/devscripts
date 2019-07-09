# Push local work. Like gbp push but able to push uncomplete work
package Devscripts::Salsa::push;
use strict;
use Devscripts::Output;
use Devscripts::Utils;
use Moo::Role;
use Dpkg::IPC;

sub readGbpConf {
    my ($self) = @_;
    my $res = '';
    foreach my $gbpconf (qw(.gbp.conf debian/gbp.conf .git/gbp.conf)) {
        if (-e $gbpconf) {
            open(my $f, $gbpconf);
            while (<$f>) {
                $res .= $_;
                if (/^\s*(debian|upstream)\-(branch|tag)\s*=\s*(.*\S)/) {
                    $self->{"$1_$2"} = $3;
                }
            }
            close $f;
            last;
        }
    }
    if ($self->{debian_tag}) {
        $self->{debian_tag} =~ s/%\(version\)s/.*/g;
        $self->{debian_tag} =~ s/^/^/;
        $self->{debian_tag} =~ s/$/\$/;
    } else {
        my @tmp
          = Dpkg::Source::Format->new(filename => 'debian/source/format')->get;
        $self->{debian_tag} = $tmp[2] eq 'native' ? '.*' : 'debian/.*';
    }
    if ($self->{upstream_tag}) {
        $self->{upstream_tag} =~ s/%(version)s/.*/g;
        $self->{upstream_tag} =~ s/^/^/;
        $self->{upstream_tag} =~ s/$/\$/;
    } else {
        $self->{upstream_tag} = 'upstream/.*';
    }
    $self->{debian_branch}   ||= 'master';
    $self->{upstream_branch} ||= 'upstream';
    return $res;
}

sub push {
    my ($self) = @_;
    $self->readGbpConf;
    my @refs;
    foreach (
        $self->{debian_branch}, $self->{upstream_branch},
        'pristine-tar',         'refs/notes/commits'
    ) {
        if (ds_exec_no_fail(qw(git rev-parse --verify --quiet), $_) == 0) {
            push @refs, $_;
        }
    }
    my $out;
    spawn(exec => ['git', 'tag'], wait_child => 1, to_string => \$out);
    my @tags = grep /(?:$self->{debian_tag}|$self->{upstream_tag})/,
      split(/\r?\n/, $out);
    unless (
        $ds_yes < 0
        and ds_prompt(
                "You're going to push :\n - "
              . join(', ', @refs)
              . "\nand check tags that match:\n - "
              . join(', ', $self->{debian_tag}, $self->{upstream_tag})
              . "\nContinue (Y/n) "
        ) =~ refuse
    ) {
        my $origin;
        eval {
            spawn(
                exec       => ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                wait_child => 1,
                to_string  => \$out,
            );
            chomp $out;
            spawn(
                exec =>
                  ['git', 'config', '--local', '--get', "branch.$out.remote"],
                wait_child => 1,
                to_string  => \$origin,
            );
            chomp $origin;
        };
        if ($origin) {
            ds_verbose 'Origin is ' . $origin;
        } else {
            ds_warn 'Unable to detect remote name, trying "origin"';
            ds_verbose "Error: $@" if ($@);
            $origin = 'origin';
        }
        ds_verbose "Execute 'git push $origin " . join(' ', @refs, '<tags>');
        ds_debug "Tags are: " . join(' ', @tags);
        spawn(
            exec       => ['git', 'push', $origin, @refs, @tags],
            wait_child => 1
        );
    }
    return 0;
}

1;
