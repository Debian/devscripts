#!/usr/bin/perl

=head1 NAME

debcommit - commit changes to a package

=head1 SYNOPSIS

B<debcommit> [I<options>] [B<--all> | I<files to commit>]

=head1 DESCRIPTION

B<debcommit> generates a commit message based on new text in B<debian/changelog>,
and commits the change to a package's repository. It must be run in a working
copy for the package. Supported version control systems are:
B<cvs>, B<git>, B<hg> (mercurial), B<svk>, B<svn> (Subversion),
B<baz>, B<bzr>, B<tla> (arch), B<darcs>.

=head1 OPTIONS

=over 4

=item B<-c>, B<--changelog> I<path>

Specify an alternate location for the changelog. By default debian/changelog is
used.

=item B<-r>, B<--release>

Commit a release of the package. The version number is determined from
debian/changelog, and is used to tag the package in the repository.

Note that svn/svk tagging conventions vary, so debcommit uses
svnpath(1) to determine where the tag should be placed in the
repository.

=item B<-R>, B<--release-use-changelog>

When used in conjunction with B<--release>, if there are uncommitted
changes to the changelog then derive the commit message from those
changes rather than using the default message.

=item B<-m> I<text>, B<--message> I<text>

Specify a commit message to use. Useful if the program cannot determine
a commit message on its own based on debian/changelog, or if you want to
override the default message.

=item B<-n>, B<--noact>

Do not actually do anything, but do print the commands that would be run.

=item B<-d>, B<--diff>

Instead of committing, do print the diff of what would have been committed if
this option were not given. A typical usage scenario of this option is the
generation of patches against the current working copy (e.g. when you don't have
commit access right).

=item B<-C>, B<--confirm>

Display the generated commit message and ask for confirmation before committing
it. It is also possible to edit the message at this stage; in this case, the
confirmation prompt will be re-displayed after the editing has been performed.

=item B<-e>, B<--edit>

Edit the generated commit message in your favorite editor before committing
it.

=item B<-a>, B<--all>

Commit all files. This is the default operation when using a VCS other
than git.

=item B<-s>, B<--strip-message>, B<--no-strip-message>

If this option is set and the commit message has been derived from the
changelog, the characters "* " will be stripped from the beginning of
the message.

This option is set by default and ignored if more than one line of
the message begins with "[*+-] ".

=item B<--sign-commit>, B<--no-sign-commit>

If this option is set, then the commits that debcommit creates will be
signed using gnupg. Currently this is only supported by git, hg, and bzr.

=item B<--sign-tags>, B<--no-sign-tags>

If this option is set, then tags that debcommit creates will be signed
using gnupg. Currently this is only supported by git.

=item B<--changelog-info>

If this option is set, the commit author and date will be determined from
the Maintainer and Date field of the first paragraph in F<debian/changelog>.
This is mainly useful when using B<debchange>(1) with the B<--no-mainttrailer>
option.

=back

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables.  Command line options can be used to override
configuration file settings.  Environment variable settings are
ignored for this purpose.  The currently recognised variables are:

=over 4

=item B<DEBCOMMIT_STRIP_MESSAGE>

If this is set to I<no>, then it is the same as the B<--no-strip-message>
command line parameter being used. The default is I<yes>.

=item B<DEBCOMMIT_SIGN_TAGS>

If this is set to I<yes>, then it is the same as the B<--sign-tags> command
line parameter being used. The default is I<no>.

=item B<DEBCOMMIT_SIGN_COMMITS>

If this is set to I<yes>, then it is the same as the B<--sign-commit>
command line parameter being used. The default is I<no>.

=item B<DEBCOMMIT_RELEASE_USE_CHANGELOG>

If this is set to I<yes>, then it is the same as the B<--release-use-changelog>
command line parameter being used. The default is I<no>.

=item B<DEBSIGN_KEYID>

This is the key id used for signing tags. If not set, a default will be
chosen by the revision control system.

=back

=head1 VCS SPECIFIC FEATURES

=over 4

=item B<tla> / B<baz>

If the commit message contains more than 72 characters, a summary will
be created containing as many full words from the message as will fit within
72 characters, followed by an ellipsis.

=back

Each of the features described below is applicable only if the commit message
has been automatically determined from the changelog.

=over 4

=item B<git>

If only a single change is detected in the changelog, B<debcommit> will unfold
it to a single line and behave as if B<--strip-message> was used.

Otherwise, the first change will be unfolded and stripped to form a summary line
and a commit message formed using the summary line followed by a blank line and
the changes as extracted from the changelog. B<debcommit> will then spawn an
editor so that the message may be fine-tuned before committing.

=item B<hg> / B<darcs>

The first change detected in the changelog will be unfolded to form a single line
summary. If multiple changes were detected then an editor will be spawned to
allow the message to be fine-tuned.

=item B<bzr>

If the changelog entry used for the commit message closes any bugs then B<--fixes>
options to "bzr commit" will be generated to associate the revision and the bugs.

=back

=cut

use warnings;
use strict;
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use Cwd;
use File::Basename;
use File::HomeDir;
use File::Temp;
my $progname = basename($0);

my $modified_conf_msg;

sub usage {
    print <<"EOT";
Usage: $progname [options] [files to commit]
       $progname --version
       $progname --help

Generates a commit message based on new text in debian/changelog,
and commit the change to a package\'s repository.

Options:
   -c --changelog=path Specify the location of the changelog
   -r --release        Commit a release of the package and create a tag
   -R --release-use-changelog
                       Take any uncommitted changes in the changelog in
                       to account when determining the commit message
                       for a release
   -m --message=text   Specify a commit message
   -n --noact          Dry run, no actual commits
   -d --diff           Print diff on standard output instead of committing
   -C --confirm        Ask for confirmation of the message before commit
   -e --edit           Edit the message in EDITOR before commit
   -a --all            Commit all files (default except for git)
   -s --strip-message  Strip the leading '* ' from the commit message (default)
   --no-strip-message  Do not strip a leading '* '
   --sign-commit       Enable signing of the commit (git, hg, and bzr)
   --no-sign-commit    Do not sign the commit (default)
   --sign-tags         Enable signing of tags (git only)
   --no-sign-tags      Do not sign tags (default)
   --changelog-info    Use author and date information from the changelog
                       for the commit (git, hg, and bzr)
   -h --help           This message
   -v --version        Version information

   --no-conf, --noconf
                   Don\'t read devscripts config files;
                   must be the first option given

Default settings modified by devscripts configuration files:
$modified_conf_msg

EOT
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright by Joey Hess <joeyh\@debian.org>, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

my $release = 0;
my $message;
my $release_use_changelog = 0;
my $noact                 = 0;
my $diffmode              = 0;
my $confirm               = 0;
my $edit                  = 0;
my $all                   = 0;
my $stripmessage          = 1;
my $signcommit            = 0;
my $signtags              = 0;
my $changelog;
my $changelog_info = 0;
my $keyid;
my ($package, $version, $date, $maintainer);
my $onlydebian = 0;

# Now start by reading configuration files and then command line
# The next stuff is boilerplate

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars  = (
        'DEBCOMMIT_STRIP_MESSAGE'         => 'yes',
        'DEBCOMMIT_SIGN_COMMITS'          => 'no',
        'DEBCOMMIT_SIGN_TAGS'             => 'no',
        'DEBCOMMIT_RELEASE_USE_CHANGELOG' => 'no',
        'DEBSIGN_KEYID'                   => '',
    );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
        $shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    $shell_cmd .= 'for file in ' . join(" ", @config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{ keys %config_vars } = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'DEBCOMMIT_STRIP_MESSAGE'} =~ /^(yes|no)$/
      or $config_vars{'DEBCOMMIT_STRIP_MESSAGE'} = 'yes';
    $config_vars{'DEBCOMMIT_SIGN_COMMITS'} =~ /^(yes|no)$/
      or $config_vars{'DEBCOMMIT_SIGN_COMMITS'} = 'no';
    $config_vars{'DEBCOMMIT_SIGN_TAGS'} =~ /^(yes|no)$/
      or $config_vars{'DEBCOMMIT_SIGN_TAGS'} = 'no';
    $config_vars{'DEBCOMMIT_RELEASE_USE_CHANGELOG'} =~ /^(yes|no)$/
      or $config_vars{'DEBCOMMIT_RELEASE_USE_CHANGELOG'} = 'no';

    foreach my $var (sort keys %config_vars) {
        if ($config_vars{$var} ne $config_default{$var}) {
            $modified_conf_msg .= "  $var=$config_vars{$var}\n";
        }
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $stripmessage = $config_vars{'DEBCOMMIT_STRIP_MESSAGE'} eq 'no' ? 0 : 1;
    $signcommit   = $config_vars{'DEBCOMMIT_SIGN_COMMITS'} eq 'no'  ? 0 : 1;
    $signtags     = $config_vars{'DEBCOMMIT_SIGN_TAGS'} eq 'no'     ? 0 : 1;
    $release_use_changelog
      = $config_vars{'DEBCOMMIT_RELEASE_USE_CHANGELOG'} eq 'no' ? 0 : 1;
    if (exists $config_vars{'DEBSIGN_KEYID'}
        && length $config_vars{'DEBSIGN_KEYID'}) {
        $keyid = $config_vars{'DEBSIGN_KEYID'};
    }
}

# Find a good default for the changelog file location

for (qw"debian/changelog changelog") {
    if (-e $_) {
        $changelog = $_;
        last;
    }
}

# Now read the command line arguments

if (
    !GetOptions(
        "r|release"                => \$release,
        "m|message=s"              => \$message,
        "n|noact"                  => \$noact,
        "d|diff"                   => \$diffmode,
        "C|confirm"                => \$confirm,
        "e|edit"                   => \$edit,
        "a|all"                    => \$all,
        "c|changelog=s"            => \$changelog,
        "s|strip-message!"         => \$stripmessage,
        "sign-commit!"             => \$signcommit,
        "sign-tags!"               => \$signtags,
        "changelog-info!"          => \$changelog_info,
        "R|release-use-changelog!" => \$release_use_changelog,
        "h|help"                   => sub { usage(); exit 0; },
        "v|version"                => sub { version(); exit 0; },
        'noconf|no-conf' => sub { die '--noconf must be first option'; },
    )
) {
    die "Usage: $progname [options] [--all | files to commit]\n";
}

if ($diffmode) {
    $confirm = 0;
    $edit    = 0;
}

my @files_to_commit = @ARGV;
if (@files_to_commit && !grep(/$changelog/, @files_to_commit)) {
    push @files_to_commit, $changelog;
}

# Main program

my $prog = getprog();
if (!defined $changelog) {
    die "debcommit: Could not find a Debian changelog\n";
}
if (!-e $changelog) {
    die "debcommit: cannot find $changelog\n";
}

$message = getmessage()
  if !defined $message and (not $release or $release_use_changelog);

if ($release || $changelog_info) {
    require Dpkg::Changelog::Parse;
    my $log = Dpkg::Changelog::Parse::changelog_parse(file => $changelog);
    if ($release) {
        if ($log->{Distribution} =~ /UNRELEASED/) {
            die
"debcommit: $changelog says it's UNRELEASED\nTry running dch --release first\n";
        }
        $package = $log->{Source};
        $version = $log->{Version};

        $message = "releasing package $package version $version"
          if !defined $message;
    }
    if ($changelog_info) {
        $maintainer = $log->{Maintainer};
        $date       = $log->{Date};
    }
}

if ($edit) {
    my $modified = 0;
    ($message, $modified) = edit($message);
    die "$progname: Commit message not modified / saved; aborting\n"
      unless $modified;
}

if (not $confirm or confirm($message)) {
    commit($message);
    tag($package, $version) if $release;
}

# End of code, only subs below

sub getprog {
    if (-d "debian") {
        if (-d "debian/.svn") {
            # SVN has .svn even in subdirs...
            if (!-d ".svn") {
                $onlydebian = 1;
            }
            return "svn";
        } elsif (-d "debian/CVS") {
            # CVS has CVS even in subdirs...
            if (!-d "CVS") {
                $onlydebian = 1;
            }
            return "cvs";
        } elsif (-d "debian/{arch}") {
            # I don't think we can tell just from the working copy
            # whether to use tla or baz, so try baz if it's available,
            # otherwise fall back to tla.
            if (system("baz --version >/dev/null 2>&1") == 0) {
                return "baz";
            } else {
                return "tla";
            }
        } elsif (-d "debian/_darcs") {
            $onlydebian = 1;
            return "darcs";
        }
    }
    if (-d ".svn") {
        return "svn";
    }
    if (-d "CVS") {
        return "cvs";
    }
    if (-d "{arch}") {
        # I don't think we can tell just from the working copy
        # whether to use tla or baz, so try baz if it's available,
        # otherwise fall back to tla.
        if (system("baz --version >/dev/null 2>&1") == 0) {
            return "baz";
        } else {
            return "tla";
        }
    }
    if (-d ".bzr") {
        return "bzr";
    }
    if (-e ".git") {
# With certain forms of git checkouts, .git can be a file instead of a directory
        return "git";
    }
    if (-d ".hg") {
        return "hg";
    }
    if (-d "_darcs") {
        return "darcs";
    }

    # Test for this file to avoid interactive prompting from svk.
    if (-d File::HomeDir->my_home . "/.svk/local") {
        # svk has no useful directories so try to run it.
        my $svkpath
          = `svk info . 2>/dev/null| grep -i '^Depot Path:' | cut -d ' ' -f 3`;
        if (length $svkpath) {
            return "svk";
        }
    }

    # .bzr, .git, .hg, or .svn may be in a parent directory, rather than the
    # current directory, if multiple packages are kept in one repository.
    my $dir = getcwd();
    while ($dir =~ s/[^\/]*\/?$// && length $dir) {
        if (-d "$dir/.bzr") {
            return "bzr";
        }
        if (-e "$dir/.git") {
            return "git";
        }
        if (-d "$dir/.hg") {
            return "hg";
        }
        if (-d "$dir/.svn") {
            return "svn";
        }
    }

    die
"debcommit: not in a cvs, Subversion, baz, bzr, git, hg, svk or darcs working copy\n";
}

sub action {
    my $prog = shift;
    if ($prog eq "darcs" && $onlydebian) {
        splice(@_, 1, 0, "--repodir=debian");
    }
    print $prog, " ", join(
        " ",
        map {
            if   (/[^-A-Za-z0-9]/) { "'$_'" }
            else                   { $_ }
        } @_
      ),
      "\n";
    return 1 if $noact;
    return (system($prog, @_) != 0) ? 0 : 1;
}

sub bzr_find_fixes {
    my $message = shift;

    require Dpkg::Changelog::Entry::Debian;
    require Dpkg::Vendor::Ubuntu;

    my @debian_closes = Dpkg::Changelog::Entry::Debian::find_closes($message);
    my $launchpad_closes
      = Dpkg::Vendor::Ubuntu::find_launchpad_closes($message);

    my @fixes_arg = ();
    map { push(@fixes_arg, ("--fixes", "deb:" . $_)) } @debian_closes;
    map { push(@fixes_arg, ("--fixes", "lp:" . $_)) } @$launchpad_closes;
    return @fixes_arg;
}

sub commit {
    my $message = shift;

    die "debcommit: can't specify a list of files to commit when using --all\n"
      if (@files_to_commit and $all);

    my $action_rc;    # return code of external command
    if ($prog =~ /^(cvs|svn|svk|hg)$/) {
        if (!@files_to_commit && $onlydebian) {
            @files_to_commit = ("debian");
        }
        my @extra_args;
        if ($changelog_info && $prog eq 'hg') {
            push(@extra_args, '-u', $maintainer, '-d', $date);
        }
        $action_rc
          = $diffmode
          ? action($prog, "diff", @files_to_commit)
          : action($prog, "commit", "-m", $message, @extra_args,
            @files_to_commit);
        if ($prog eq 'hg' && $action_rc && $signcommit) {
            my @sign_args;
            push(@sign_args, '-k', $keyid) if $keyid;
            push(@sign_args, '-u', $maintainer, '-d', $date)
              if $changelog_info;
            if (!action($prog, 'sign', @sign_args)) {
                die "$progname: failed to sign commit\n";
            }
        }
    } elsif ($prog eq 'git') {
        if (!@files_to_commit && ($all || $release)) {
            # check to see if the WC is clean. git-commit would exit
            # nonzero, so don't run it in --all or --release mode.
            my $status = `git status --porcelain`;
            if (!$status) {
                print $status;
                return;
            }
        }
        if ($diffmode) {
            $action_rc = action($prog, "diff", @files_to_commit);
        } else {
            if ($all) {
                @files_to_commit = ("-a");
            }
            my @extra_args = ();
            if ($changelog_info) {
                @extra_args = ("--author=$maintainer", "--date=$date");
            }
            if ($signcommit) {
                my $sign = '--gpg-sign';
                $sign .= "=$keyid" if $keyid;
                push(@extra_args, $sign);
            }
            $action_rc = action($prog, "commit", "-m", $message, @extra_args,
                @files_to_commit);
        }
    } elsif ($prog eq 'tla' || $prog eq 'baz') {
        my $summary = $message;
        $summary =~ s/^((?:\* )?[^\n]{1,72})(?:(?:\s|\n).*|$)/$1/ms;
        my @args;
        if (!$diffmode) {
            if ($summary eq $message) {
                $summary =~ s/^\* //s;
                @args = ("-s", $summary);
            } else {
                $summary =~ s/^\* //s;
                @args = ("-s", "$summary ...", "-L", $message);
            }
        }
        push(@args, (($prog eq 'tla') ? '--' : ()), @files_to_commit,)
          if @files_to_commit;
        $action_rc = action($prog, $diffmode ? "diff" : "commit", @args);
    } elsif ($prog eq 'bzr') {
        if ($diffmode) {
            $action_rc = action($prog, "diff", @files_to_commit);
        } else {
            my @extra_args = bzr_find_fixes($message);
            if ($changelog_info) {
                eval {
                    require Date::Format;
                    require Date::Parse;
                };
                if ($@) {
                    my $error
                      = "$progname: Couldn't format the changelog date: ";
                    if ($@ =~ m%^Can\'t locate Date%) {
                        $error
                          .= "the libtimedate-perl package is not installed";
                    } else {
                        $error .= "couldn't load Date::Format/Date::Parse: $@";
                    }
                    die "$error\n";
                }
                my @time = Date::Parse::strptime($date);
                my $time
                  = Date::Format::strftime('%Y-%m-%d %H:%M:%S %z', \@time);
                push(@extra_args,
                    "--author=$maintainer", "--commit-time=$time");
            }
            my @sign_args;
            if ($signcommit) {
                push(@sign_args, "-Ocreate_signatures=always");
                if ($keyid) {
                    push(@sign_args, "-Ogpg_signing_key=$keyid");
                }
            }
            $action_rc = action($prog, @sign_args, "commit", "-m", $message,
                @extra_args, @files_to_commit);
        }
    } elsif ($prog eq 'darcs') {
        if (!@files_to_commit && ($all || $release)) {
            # check to see if the WC is clean. darcs record would exit
            # nonzero, so don't run it in --all or --release mode.
            $action_rc = action($prog, "status");
            if (!$action_rc) {
                return;
            }
        }
        if ($diffmode) {
            $action_rc = action($prog, "diff", @files_to_commit);
        } else {
            my $fh = File::Temp->new(TEMPLATE => '.commit-tmp.XXXXXX');
            $fh->print("$message\n");
            $fh->close();
            $action_rc = action($prog, "record", "--logfile", "$fh", "-a",
                @files_to_commit);
        }
    } else {
        die "debcommit: unknown program $prog";
    }
    die "debcommit: commit failed\n" if (!$action_rc);
}

sub tag {
    my ($package, $tag, $tag_msg) = @_;

    # Make the message here so we can mangle $tag later, if needed
    $tag_msg
      = !defined $message
      ? "tagging package $package version $tag"
      : "$message";

    if ($prog eq 'svn' || $prog eq 'svk') {
        my $svnpath = `svnpath`;
        chomp $svnpath;
        my $tagpath = `svnpath tags`;
        chomp $tagpath;

        if (!action($prog, "copy", $svnpath, "$tagpath/$tag", "-m", $tag_msg))
        {
            if (
                !action(
                    $prog, "mkdir", $tagpath, "-m", "create tag directory"
                )
                || !action(
                    $prog, "copy", $svnpath, "$tagpath/$tag",
                    "-m",  $tag_msg
                )
            ) {
                die "debcommit: failed tagging with $tag\n";
            }
        }
    } elsif ($prog eq 'cvs') {
        $tag =~ s/^[0-9]+://;    # strip epoch
        $tag =~ tr/./_/;         # mangle for cvs
        $tag = "debian_version_$tag";
        if (!action("cvs", "tag", "-f", $tag)) {
            die "debcommit: failed tagging with $tag\n";
        }
    } elsif ($prog eq 'tla' || $prog eq 'baz') {
        my $archpath = `archpath`;
        chomp $archpath;
        my $tagpath = `archpath releases--\Q$tag\E`;
        chomp $tagpath;
        my $subcommand;
        if ($prog eq 'baz') {
            $subcommand = "branch";
        } else {
            $subcommand = "tag";
        }

        if (!action($prog, $subcommand, $archpath, $tagpath)) {
            die "debcommit: failed tagging with $tag\n";
        }
    } elsif ($prog eq 'bzr') {
        if (action("$prog tags >/dev/null 2>&1")) {
            if (!action($prog, "tag", $tag)) {
                die "debcommit: failed tagging with $tag\n";
            }
        } else {
            die
              "debcommit: bazaar or branch version too old to support tags\n";
        }
    } elsif ($prog eq 'git') {
        $tag =~ tr/~/_/;    # mangle for git
        $tag =~ tr/:/%/;
        if ($tag =~ /-/) {
            # not a native package, so tag as a debian release
            $tag = "debian/$tag";
        }

        if ($signtags) {
            my $tag_msg = "tagging package $package version $tag";
            if (defined $keyid) {
                if (
                    !action(
                        $prog,  "tag", "-a",     "-u",
                        $keyid, "-m",  $tag_msg, $tag
                    )
                ) {
                    die "debcommit: failed tagging with $tag\n";
                }
            } else {
                if (!action($prog, "tag", "-a", "-s", "-m", $tag_msg, $tag)) {
                    die "debcommit: failed tagging with $tag\n";
                }
            }
        } elsif (!action($prog, "tag", "-a", "-m", $tag_msg, $tag)) {
            die "debcommit: failed tagging with $tag\n";
        }
    } elsif ($prog eq 'hg') {
        $tag =~ s/^[0-9]+://;    # strip epoch
        $tag = "debian-$tag";
        if (!action($prog, "tag", "-m", $tag_msg, $tag)) {
            die "debcommit: failed tagging with $tag\n";
        }
    } elsif ($prog eq 'darcs') {
        if (!action($prog, "tag", $tag)) {
            die "debcommit: failed tagging with $tag\n";
        }
    } else {
        die "debcommit: unknown program $prog";
    }
}

sub getmessage {
    my $ret;

    if ($prog =~ /^(cvs|svn|svk|tla|baz|bzr|git|hg|darcs)$/) {
        $ret = '';
        my @diffcmd;

        if ($prog eq 'tla') {
            @diffcmd = ($prog, 'diff', '-D', '-w', '--');
        } elsif ($prog eq 'baz') {
            @diffcmd = ($prog, 'file-diff');
        } elsif ($prog eq 'bzr') {
            @diffcmd = ($prog, 'diff', '--diff-options', '-wu');
        } elsif ($prog eq 'git') {
            if (git_repo_has_commits()) {
                if ($all) {
                    @diffcmd = ('git', 'diff', '-w', '--no-color');
                } else {
                    @diffcmd = ('git', 'diff', '-w', '--cached', '--no-color');
                }
            } else {
                # No valid head!  Rather than fail, cheat and use 'diff'
                @diffcmd = ('diff', '-u', '/dev/null');
            }
        } elsif ($prog eq 'svn') {
            @diffcmd = (
                $prog, 'diff', '--diff-cmd', '/usr/bin/diff', '--extensions',
                '-wu'
            );
        } elsif ($prog eq 'svk') {
            $ENV{'SVKDIFF'} = '/usr/bin/diff -w -u';
            @diffcmd = ($prog, 'diff');
        } elsif ($prog eq 'darcs') {
            @diffcmd = ($prog, 'diff', '--diff-opts=-wu');
            if ($onlydebian) {
                push(@diffcmd, '--repodir=debian');
            }
        } else {
            @diffcmd = ($prog, 'diff', '-w');
        }

        open CHLOG, '-|', @diffcmd, $changelog
          or die "debcommit: cannot run $diffcmd[0]: $!\n";

        foreach (<CHLOG>) {
            next unless s/^\+(  |\t)//;
            next if /^\s*\[.*\]\s*$/;    # maintainer name
            $ret .= $_;
        }

        if (!length $ret) {
            if ($release) {
                return;
            } else {
                my $info = '';
                if ($prog eq 'git') {
                    $info
                      = ' (do you mean "debcommit -a" or did you forget to run "git add"?)';
                }
                die
"debcommit: unable to determine commit message using $prog$info\nTry using the -m flag.\n";
            }
        } else {
            if ($prog =~ /^(git|hg|darcs)$/ and not $diffmode) {
                my $count = () = $ret =~ /^\s*[\*\+-] /mg;

                if ($count == 1) {
                    # Unfold
                    $ret =~ s/\n\s+/ /mg;
                } else {
                    my $summary = '';

                    # We're constructing a message that can be used as a
                    # good starting point, the user will need to fine-tune it
                    $edit = 1;

                    $summary = $ret;
                    # Strip off the second and subsequent changes
                    $summary =~ s/(^\* .*?)^\s*[\*\+-] .*/$1/ms;
                    # Unfold
                    $summary =~ s/\n\s+/ /mg;

                    if ($prog eq 'git') {
                        $summary =~ s/^\* //;
                        $ret = $summary . "\n" . $ret;
                    } else {
                        # Strip off the first change so that we can prepend
                        # the unfolded version
                        $ret =~ s/^\* .*?(^\s*[\*\+-] .*)/$1\n/msg;
                        $ret = $summary . $ret;
                    }
                }
            }

            if ($stripmessage or $prog eq 'git') {
                my $count = () = $ret =~ /^[ \t]*[\*\+-] /mg;
                if ($count == 1) {
                    $ret =~ s/^[ \t]*[\*\+-] //;
                    $ret =~ s/^[ \t]*//mg;
                }
            }
        }
    } else {
        die "debcommit: unknown program $prog";
    }

    chomp $ret;
    return $ret;
}

sub confirm {
    my $confirmmessage = shift;
    print $confirmmessage, "\n--\n";
    while (1) {
        print "OK to commit? [Y/n/e] ";
        $_ = <STDIN>;
        return 0 if /^n/i;
        if (/^(y|$)/i) {
            $message = $confirmmessage;
            return 1;
        } elsif (/^e/i) {
            ($confirmmessage) = edit($confirmmessage);
            print "\n", $confirmmessage, "\n--\n";
        }
    }
}

# The string returned by edit is chomp()ed, so anywhere we present that string
# to the user again needs to have a \n tacked on to the end.
sub edit {
    my $message = shift;
    my $fh      = File::Temp->new(TEMPLATE => '.commit-tmp.XXXXXX')
      || die "$progname: unable to create a temporary file.\n";
    # Ensure the message we present to the user has an EOL on the last line.
    chomp($message);
    $fh->print("$message\n");
    $fh->close();
    my $mtime = (stat("$fh"))[9];
    defined $mtime
      || die
"$progname: unable to retrieve modification time for temporary file: $!\n";
    $mtime--;
    utime $mtime, $mtime, $fh->filename;
    system("sensible-editor $fh");
    open(FH, '<', "$fh")
      || die "$progname: unable to open temporary file for reading\n";
    $message = "";

    while (<FH>) {
        $message .= $_;
    }
    close(FH);
    my $newmtime = (stat("$fh"))[9];
    defined $newmtime
      || die
"$progname: unable to retrieve modification time for updated temporary file: $!\n";
    chomp $message;
    return ($message, $mtime != $newmtime);
}

sub git_repo_has_commits {
    my $command = "git rev-parse --verify --quiet HEAD >/dev/null";
    system $command;
    return ($? >> 8 == 0) ? 1 : 0;
}

=head1 LICENSE

This code is copyright by Joey Hess <joeyh@debian.org>, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.

=head1 AUTHOR

Joey Hess <joeyh@debian.org>

=head1 SEE ALSO

B<debchange>(1), B<svnpath>(1)

=cut
