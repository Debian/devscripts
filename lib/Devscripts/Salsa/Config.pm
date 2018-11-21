# Salsa configuration (inherits from Devscripts::Config)
package Devscripts::Salsa::Config;

use strict;
use Devscripts::Output;
use Moo;

extends 'Devscripts::Config';

# Declare accessors for each option
foreach (qw(
    all api_url cache_file command desc desc_pattern dest_branch rename_head
    disable_irker disable_issues disable_kgb disable_mr disable_tagpending
    enable_issues enable_mr irc_channel git_server_url irker irker_server_url
    irker_host irker_port kgb kgb_server_url mr_allow_squash mr_desc mr_dst_branch
    mr_dst_project mr_remove_source_branch mr_src_branch mr_src_project
    mr_title no_fail path private_token skip source_branch group group_id user
    user_id tagpending tagpending_server_url email email_recipient
    disable_email
    )
) {
    has $_ => (is => 'rw');
}

my $cacheDir;

BEGIN {
    $cacheDir = $ENV{XDG_CACHE_HOME} || $ENV{HOME} . '/.cache';
}

# Options
use constant keys => [

    # General options
    [
        'C|chdir=s', undef,
        sub { return (chdir($_[1]) ? 1 : (0, "$_[1] doesn't exist")) }
    ],
    [
        'cache-file',
        'SALSA_CACHE_FILE',
        sub {
            $_[0]->cache_file($_[1] ? $_[1] : undef);
        },
        "$cacheDir/salsa.json"
    ],
    [
        'no-cache',
        'SALSA_NO_CACHE',
        sub {
            $_[0]->cache_file(undef)
              if ($_[1] !~ /^(?:no|0+)$/i);
            return 1;
        }
    ],
    ['debug', undef, sub { $verbose = 2 }],
    ['info|i', 'SALSA_INFO', sub { info(-1, 'SALSA_INFO', @_) }],
    [
        'path=s',
        'SALSA_REPO_PATH',
        sub {
            $_ = $_[1];
            s#/*(.*)/*#$1#;
            $_[0]->path($_);
            return /^[\w\d\-]+$/ ? 1 : (0, "Bad path $_");
        }
    ],
    ['group=s',    'SALSA_GROUP',    qr/^[\-\w]+$/],
    ['group-id=s', 'SALSA_GROUP_ID', qr/^\d+$/],
    ['token', 'SALSA_TOKEN', sub { $_[0]->private_token($_[1]) }],
    [
        'token-file',
        'SALSA_TOKEN_FILE',
        sub {
            my ($self, $v) = @_;
            return (0, "Unable to open token file") unless (-r $v);
            open F, $v;
            my $s = join '', <F>;
            close F;
            if ($s
                =~ m/^[^#]*(?:SALSA_(?:PRIVATE_)?TOKEN)\s*=\s*(["'])?(\w+)\1?$/m
            ) {
                $self->private_token($2);
                return 1;
            } else {
                return (0, "No token found in file $v");
            }
        }
    ],
    ['user=s',    'SALSA_USER',    qr/^[\-\w]+$/],
    ['user-id=s', 'SALSA_USER_ID', qr/^\d+$/],
    ['verbose',   'SALSA_VERBOSE', sub { $verbose = 1 }],
    ['yes!', 'SALSA_YES', sub { info(1, "SALSA_YES", @_) },],

    # Update/create repo options
    ['all'],
    ['skip=s', 'SALSA_SKIP', undef, sub { [] }],
    [
        'skip-file=s',
        'SALSA_SKIP_FILE',
        sub {
            return 1 unless $_[1];
            return (0, "Unable to read $_[1]") unless (-r $_[1]);
            open my $fh, $_[1];
            push @{ $_[0]->skip }, (map { chomp $_; ($_ ? $_ : ()) } <$fh>);
            return 1;
        }
    ],
    ['no-skip', undef, sub { $_[0]->skip([]); $_[0]->skip_file(undef); }],
    ['desc!', 'SALSA_DESC', 'bool'],
    ['desc-pattern=s', 'SALSA_DESC_PATTERN', qr/\w/, 'Debian package %p'],
    ['enable-issues!'],
    ['disable-issues!'],
    [
        undef, 'SALSA_ENABLE_ISSUES',
        sub { $_[0]->enable($_[1], 'enable_issues', 'disable_issues'); }
    ],
    ['email!'],
    ['disable-email!'],
    [
        undef, 'SALSA_EMAIL',
        sub { $_[0]->enable($_[1], 'email', 'disable_email'); }
    ],
    ['email-recipient=s', 'SALSA_EMAIL_RECIPIENTS', undef, sub { [] },],
    ['enable-mr!'],
    ['disable-mr!'],
    [
        undef, 'SALSA_ENABLE_MR',
        sub { $_[0]->enable($_[1], 'enable_mr', 'disable_mr'); }
    ],
    ['irc-channel|irc=s', 'SALSA_IRC_CHANNEL', qr/\w/],
    ['irker!'],
    ['disable-irker!'],
    [
        undef, 'SALSA_IRKER',
        sub { $_[0]->enable($_[1], 'enable_irker', 'disable_irker'); }
    ],
    ['irker-host=s', 'SALSA_IRKER_HOST', undef, 'ruprecht.snow-crash.org'],
    ['irker-port=s', 'SALSA_IRKER_PORT', qr/^\d*$/],
    ['kgb!'],
    ['disable-kgb!'],
    [undef, 'SALSA_KGB', sub { $_[0]->enable($_[1], 'kgb', 'disable_kgb'); }],
    ['no-fail', 'SALSA_NO_FAIL', 'bool'],
    ['rename-head'],
    ['source-branch=s', 'SALSA_SOURCE_BRANCH', undef, 'master'],
    ['dest-branch=s',   'SALSA_DEST_BRANCH',   undef, 'debian/master'],
    ['tagpending!'],
    ['disable-tagpending!'],
    [
        undef, 'SALSA_TAGPENDING',
        sub { $_[0]->enable($_[1], 'tagpending', 'disable_tagpending'); }
    ],

    # Merge requests options
    ['mr-allow-squash!', 'SALSA_MR_ALLOW_SQUASH', 'bool', 1],
    ['mr-desc=s'],
    ['mr-dst-branch=s', undef, undef, 'master'],
    ['mr-dst-project=s'],
    ['mr-remove-source-branch!', 'SALSA_MR_REMOVE_SOURCE_BRANCH', 'bool', 0],
    ['mr-src-branch=s'],
    ['mr-src-project=s'],
    ['mr-title=s'],

    # Options to manage other Gitlab instances
    [
        'api-url=s',    'SALSA_API_URL',
        qr#^https?://#, 'https://salsa.debian.org/api/v4'
    ],
    [
        'git-server-url=s', 'SALSA_GIT_SERVER_URL',
        qr/^\S+\@\S+/,      'git@salsa.debian.org:'
    ],
    [
        'irker-server-url=s', 'SALSA_IRKER_SERVER_URL',
        qr'^ircs?://',        'ircs://irc.oftc.net:6697/'
    ],
    [
        'kgb-server-url=s', 'SALSA_KGB_SERVER_URL',
        qr'^https?://',     'http://kgb.debian.net:9418/webhook/?channel='
    ],
    [
        'tagpending-server-url=s',
        'SALSA_TAGPENDING_SERVER_URL',
        qr'^https?://',
        'https://webhook.salsa.debian.org/tagpending/'
    ],
];

# Consistency rules
use constant rules => [
    # Reject unless token exists
    sub {
        return (1,
            "SALSA_TOKEN not set in ~/.devscripts. Some commands may fail")
          unless ($_[0]->private_token);
    },
    # Get command
    sub {
        return (0, "No command given, aborting") unless (@ARGV);
        $_[0]->command(shift @ARGV);
        return (0, "Malformed command: " . $_[0]->command)
          unless ($_[0]->command =~ /^[a-z_]+$/);
        return 1;
    },
    sub {
        if (    ($_[0]->group or $_[0]->group_id)
            and ($_[0]->user_id or $_[0]->user)) {
            ds_warn(
                "Both --user-id and --group-id are set, ignore --group-id");
            $_[0]->group(undef);
            $_[0]->group_id(undef);
        }
        return 1;
    },
    sub {
        if ($_[0]->group and $_[0]->group_id) {
            ds_warn("Both --group-id and --group are set, ignore --group");
            $_[0]->group(undef);
        }
        return 1;
    },
    sub {
        if ($_[0]->user and $_[0]->user_id) {
            ds_warn("Both --user-id and --user are set, ignore --user");
            $_[0]->user(undef);
        }
        return 1;
    },
    sub {
        if ($_[0]->email and not @{ $_[0]->email_recipient }) {
            return (0, '--email-recipient needed with --email');
        }
        return 1;
    },
];

sub usage {
    print <<END;
usage: salsa <command> <parameters> <options>

Most used commands:
  - whoami      : gives information on the token owner
  - checkout, co: clone repo in current dir
  - fork        : fork a project
  - mr          : create a merge request
  - push_repo   : push local git repo to upstream repository

See salsa(1) manpage for more.
END
}

sub info {
    my ($num, $key, undef, $nv) = @_;
    $nv = (
          $nv =~ /^yes|1$/ ? $num
        : $nv =~ /^no|0$/i ? 0
        :                    return (0, "Bad $key value"));
    $ds_yes = $nv;
}

sub enable {
    my ($self, $v, $en, $dis) = @_;
    $v = lc($v);
    if ($v eq 'ignore') {
        $self->{$en} = $self->{$dis} = 0;
    } elsif ($v eq 'yes') {
        $self->{$en}  = 1;
        $self->{$dis} = 0;
    } elsif ($v eq 'no') {
        $self->{$en}  = 0;
        $self->{$dis} = 1;
    } else {
        return (0, "Bad value for SALSA_" . uc($en));
    }
    return 1;
}

1;
