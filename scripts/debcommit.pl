#!/usr/bin/perl

=head1 NAME

debcommit - commit changes to a package

=head1 SYNOPSIS

B<debcommit> [B<--release>] [B<--release-use-changelog>] [B<--message=>I<text>] [B<--noact>] [B<--diff>] [B<--confirm>] [B<--edit>] [B<--changelog=>I<path>] [B<--all> | I<files to commit>]

=head1 DESCRIPTION

B<debcommit> generates a commit message based on new text in B<debian/changelog>,
and commits the change to a package's repository. It must be run in a working
copy for the package. Supported version control systems are:
B<cvs>, B<git>, B<hg> (mercurial), B<svk>, B<svn> (subversion),
B<baz>, B<bzr>, B<tla> (arch).

=head1 OPTIONS

=over 4

=item B<-c> B<--changelog> I<path>

Specify an alternate location for the changelog. By default debian/changelog is
used.

=item B<-r> B<--release>

Commit a release of the package. The version number is determined from
debian/changelog, and is used to tag the package in the repository.

Note that svn/svk tagging conventions vary, so debcommit uses
L<svnpath(1)> to determine where the tag should be placed in the
repository.

=item B<-R> B<--release-use-changelog>

When used in conjunction with --release, if there are uncommited
changes to the changelog then derive the commit message from those
changes rather than using the default message.

=item B<-m> I<text> B<--message> I<text>

Specify a commit message to use. Useful if the program cannot determine
a commit message on its own based on debian/changelog, or if you want to
override the default message.

=item B<-n> B<--noact>

Do not actually do anything, but do print the commands that would be run.

=item B<-d> B<--diff>

Instead of commiting, do print the diff of what would have been committed if
this option were not given. A typical usage scenario of this option is the
generation of patches against the current working copy (e.g. when you don't have
commit access right).

=item B<-C> B<--confirm>

Display the generated commit message and ask for confirmation before committing
it. It is also possible to edit the message at this stage; in this case, the
confirmation prompt will be re-displayed after the editing has been performed.

=item B<-e> B<--edit>

Edit the generated commit message in your favorite editor before committing
it.

=item B<-a> B<--all>

Commit all files. This is the default operation when using a VCS other 
than git.

=item I<files to commit>

Specify which files to commit (debian/changelog is added to the list
automatically.)

=item B<-s> B<--strip-message>, B<--no-strip-message>

If this option is set and the commit message has been derived from the 
changelog, the characters "* " will be stripped from the beginning of 
the message.

This option is ignored if more than one line of the message 
begins with "* ".

=item B<--sign-tags>, B<--no-sign-tags>

If this option is set, then tags that debcommit creates will be signed
using gnupg. Currently this is only supported by git.

=back

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables.  Command line options can be used to override
configuration file settings.  Environment variable settings are
ignored for this purpose.  The currently recognised variables are:

=over 4

=item B<DEBCOMMIT_STRIP_MESSAGE>

If this is set to I<yes>, then it is the same as the --strip-message 
command line parameter being used. The default is I<no>.

=item B<DEBCOMMIT_SIGN_TAGS>

If this is set to I<yes>, then it is the same as the --sign-tags command
line parameter being used. The default is I<no>.

=item B<DEBCOMMIT_RELEASE_USE_CHANGELOG>

If this is set to I<yes>, then it is the same as the --release-use-changelog
command line parameter being used. The default is I<no>.

=item B<DEBSIGN_KEYID>

This is the key id used for signing tags. If not set, a default will be
chosen by the revision control system.

=back

=head1 VCS SPECIFIC FEATURES

Each of the features described below is applicable only if the commit message
has been automatically determined from the changelog.

=over 4

=item B<git>

If only a single change is detected in the changelog, B<debcommit> will unfold
it to a single line and behave as if I<--strip-message> was used.

Otherwise, the first change will be unfolded and stripped to form a summary line
and a commit message formed using the summary line followed by a blank line and
the changes as extracted from the changelog. B<debcommit> will then spawn an
editor so that the message may be fine-tuned before committing.

=item B<hg>

The first change detected in the changelog will be unfolded to form a single line
summary. If multiple changes were detected then an editor will be spawned to
allow the message to be fine-tuned.

=item B<tla> / B<baz>

If the commit message contains more than 72 characters, a summary will
be created containing as many full words from the message as will fit within
72 characters, followed by an ellipsis.

=cut

use warnings;
use strict;
use Getopt::Long;
use Cwd;
use File::Basename;
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
   -s --strip-message  Strip the leading '* ' from the commit message
   --no-strip-message  Do not strip a leading '* ' (default)
   --sign-tags         Enable signing of tags (git only)
   --no-sign-tags      Do not sign tags (default)
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

my $release=0;
my $message;
my $release_use_changelog=0;
my $noact=0;
my $diffmode=0;
my $confirm=0;
my $edit=0;
my $all=0;
my $stripmessage=0;
my $signtags=0;
my $changelog="debian/changelog";
my $keyid;

# Now start by reading configuration files and then command line
# The next stuff is boilerplate

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DEBCOMMIT_STRIP_MESSAGE' => 'no',
		       'DEBCOMMIT_SIGN_TAGS' => 'no',
		       'DEBCOMMIT_RELEASE_USE_CHANGELOG' => 'no',
		       'DEBSIGN_KEYID' => '',
		      );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
        $shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'DEBCOMMIT_STRIP_MESSAGE'} =~ /^(yes|no)$/
	or $config_vars{'DEBCOMMIT_STRIP_MESSAGE'}='no';
    $config_vars{'DEBCOMMIT_SIGN_TAGS'} =~ /^(yes|no)$/
	or $config_vars{'DEBCOMMIT_SIGN_TAGS'}='no';
    $config_vars{'DEBCOMMIT_RELEASE_USE_CHANGELOG'} =~ /^(yes|no)$/
	or $config_vars{'DEBCOMMIT_RELEASE_USE_CHANGELOG'}='no';

    foreach my $var (sort keys %config_vars) {
        if ($config_vars{$var} ne $config_default{$var}) {
            $modified_conf_msg .= "  $var=$config_vars{$var}\n";
        }
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $stripmessage = $config_vars{'DEBCOMMIT_STRIP_MESSAGE'} eq 'no' ? 0 : 1;
    $signtags = $config_vars{'DEBCOMMIT_SIGN_TAGS'} eq 'no' ? 0 : 1;
    $release_use_changelog = $config_vars{'DEBCOMMIT_RELEASE_USE_CHANGELOG'} eq 'no' ? 0 : 1;
    if (exists $config_vars{'DEBSIGN_KEYID'} &&
	length $config_vars{'DEBSIGN_KEYID'}) {
	$keyid=$config_vars{'DEBSIGN_KEYID'};
    }
}

# Now read the command line arguments

Getopt::Long::Configure("bundling");
if (! GetOptions(
		 "r|release" => \$release,
		 "m|message=s" => \$message,
		 "n|noact" => \$noact,
		 "d|diff" => \$diffmode,
		 "C|confirm" => \$confirm,
		 "e|edit" => \$edit,
		 "a|all" => \$all,
		 "c|changelog=s" => \$changelog,
		 "s|strip-message!" => \$stripmessage,
		 "sign-tags!" => \$signtags,
		 "R|release-use-changelog!" => \$release_use_changelog,
		 "h|help" => sub { usage(); exit 0; },
		 "v|version" => sub { version(); exit 0; },
		 )) {
    die "Usage: debcommit [--release] [--release-use-changelog] [--message=text] [--noact] [--diff] [--confirm] [--edit] [--changelog=path] [--all | files to commit]\n";
}

my @files_to_commit = @ARGV;
if (@files_to_commit && !grep(/$changelog/,@files_to_commit)) {
    push @files_to_commit, $changelog;
}

my $prog=getprog();
if (! -e $changelog) {
    die "debcommit: cannot find $changelog\n";
}

$message=getmessage() if ! defined $message and (not $release or $release_use_changelog);

if ($release) {
    open (C, "<$changelog" ) || die "debcommit: cannot read $changelog: $!";
    my $top=<C>;
    if ($top=~/UNRELEASED/) {
	die "debcommit: $changelog says it's UNRELEASED\nTry running dch --release first\n";
    }
    close C;
    
    my $version=`dpkg-parsechangelog | grep '^Version:' | cut -f 2 -d ' '`;
    chomp $version;

    $message="releasing version $version" if ! defined $message;
    commit($message);
    tag($version);
}
else {
    if ($edit) {
	$message = edit($message);
    }
    commit($message) if not $confirm or confirm($message);
}

sub getprog {
    if (-d "debian") {
	if (-d "debian/.svn") {
	    return "svn";
	} elsif (-d "debian/CVS") {
	    return "cvs";
	} elsif (-d "debian/{arch}") {
	    # I don't think we can tell just from the working copy
	    # whether to use tla or baz, so try baz if it's available,
	    # otherwise fall back to tla.
	    if (system ("baz --version >/dev/null 2>&1") == 0) {
		return "baz";
	    } else {
		return "tla";
	    }
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
	if (system ("baz --version >/dev/null 2>&1") == 0) {
	    return "baz";
	} else {
	    return "tla";
	}
    }
    if (-d ".bzr") {
	return "bzr";
    }
    if (-d ".git") {
	return "git";
    }
    if (-d ".hg") {
	return "hg";
    }

    # Test for this file to avoid interactive prompting from svk.
    if (-d "$ENV{HOME}/.svk/local") {
    	# svk has no useful directories so try to run it.
	my $svkpath=`svk info . 2>/dev/null| grep -i '^Depot Path:' | cut -d ' ' -f 3`;
	if (length $svkpath) {
	    return "svk";
	}
    }

    # .git may be in a parent directory, rather than the current
    # directory, if multiple packages are kept in one git repository.
    my $dir=getcwd();
    while ($dir=~s/[^\/]*\/?$// && length $dir) {
    	if (-d "$dir/.git") {
    		return "git";
    	}
    }

    die "debcommit: not in a cvs, subversion, baz, bzr, git, hg, or svk working copy\n";
}

sub action {
    my $prog=shift;
    print $prog, " ",
      join(" ", map { if (/[^-A-Za-z0-9]/) { "'$_'" } else { $_ } } @_), "\n";
    return 1 if $noact;
    return (system($prog, @_) != 0) ? 0 : 1;
}

sub commit {
    my $message=shift;
    
    die "debcommit: can't specify a list of files to commit when using --all\n"
	if (@files_to_commit and $all);

    my $action_rc;  # return code of external command
    if ($prog =~ /^(cvs|svn|svk|bzr|hg)$/) {
        $action_rc = $diffmode
	    ? action($prog, "diff", @files_to_commit)
	    : action($prog, "commit", "-m", $message, @files_to_commit);
    }
    elsif ($prog eq 'git') {
	if (! @files_to_commit && $all) {
	    # check to see if the WC is clean. git-commit would exit
	    # nonzero, so don't run it.
	    my $status=`LANG=C git status`;
	    if ($status=~/nothing to commit \(working directory clean\)/) {
		    print $status;
		    return;
	    }
	}
	if ($diffmode) {
	    $action_rc = action($prog, "diff", @files_to_commit);
	} else {
	    if ($all) {
	        @files_to_commit=("-a")
	    }
	    $action_rc = action($prog, "commit", "-m", $message, @files_to_commit);
	}
    }
    elsif ($prog eq 'tla' || $prog eq 'baz') {
	my $summary=$message;
	$summary=~s/^((?:\* )?[^\n]{1,72})(?:(?:\s|\n).*|$)/$1/ms;
	my @args;
	if (! $diffmode) {
	    if ($summary eq $message) {
		$summary=~s/^\* //s;
		@args=("-s", $summary);
	    } else {
		$summary=~s/^\* //s;
		@args=("-s", "$summary ...", "-L", $message);
	    }
	}
        push(
            @args,
            (($prog eq 'tla') ? '--' : ()),
            @files_to_commit,
        ) if @files_to_commit;
	$action_rc = action($prog, $diffmode ? "diff" : "commit", @args);
    }
    else {
	die "debcommit: unknown program $prog";
    }
    die "debcommit: commit failed\n" if (! $action_rc);
}

sub tag {
    my $tag=shift;
    
    if ($prog eq 'svn' || $prog eq 'svk') {
	my $svnpath=`svnpath`;
	chomp $svnpath;
	my $tagpath=`svnpath tags`;
	chomp $tagpath;
	
	if (! action($prog, "copy", $svnpath, "$tagpath/$tag",
		     "-m", "tagging version $tag")) {
	    if (! action($prog, "mkdir", $tagpath,
			 "-m", "create tag directory") ||
		! action($prog, "copy", $svnpath, "$tagpath/$tag",
			 "-m", "tagging version $tag")) {
		die "debcommit: failed tagging with $tag\n";
	    }
	}
    }
    elsif ($prog eq 'cvs') {
	$tag=~s/^[0-9]+://; # strip epoch
	$tag=~tr/./_/;      # mangle for cvs
	$tag="debian_version_$tag";
	if (! action("cvs", "tag", "-f", $tag)) {
	    die "debcommit: failed tagging with $tag\n";
	}
    }
    elsif ($prog eq 'tla' || $prog eq 'baz') {
	my $archpath=`archpath`;
	chomp $archpath;
	my $tagpath=`archpath releases--\Q$tag\E`;
	chomp $tagpath;
	my $subcommand;
	if ($prog eq 'baz') {
	    $subcommand="branch";
	} else {
	    $subcommand="tag";
	}
	
	if (! action($prog, $subcommand, $archpath, $tagpath)) {
	    die "debcommit: failed tagging with $tag\n";
	}
    }
    elsif ($prog eq 'bzr') {
	if (action("$prog tags >/dev/null 2>&1")) {
	    if (! action($prog, "tag", $tag)) {
		die "debcommit: failed tagging with $tag\n";
	    }
        } else {
		die "debcommit: bazaar or branch version too old to support tags\n";
        }
    }
    elsif ($prog eq 'git') {
	$tag=~s/^[0-9]+://; # strip epoch
	if ($tag=~/-/) {
		# not a native package, so tag as a debian release
		$tag="debian/$tag";
	}

	if ($signtags) {
		if (defined $keyid) {
			if (! action($prog, "tag", "-u", $keyid, "-m",
			             "tagging version $tag", $tag)) {
	        		die "debcommit: failed tagging with $tag\n";
			}
		}
		else {
			if (! action($prog, "tag", "-s", "-m",
			             "tagging version $tag", $tag)) {
	        		die "debcommit: failed tagging with $tag\n";
			}
		}
	}
	elsif (! action($prog, "tag", $tag)) {
	        die "debcommit: failed tagging with $tag\n";
    	}
    }
    elsif ($prog eq 'hg') {
	    $tag="debian-$tag";
    	if (! action($prog, "tag", "-m", "tagging version $tag", $tag)) {
	        die "debcommit: failed tagging with $tag\n";
    	}
    }
    else {
	die "debcommit: unknown program $prog";
    }
}

sub getmessage {
    my $ret;

    if ($prog =~ /^(cvs|svn|svk|tla|baz|bzr|git|hg)$/) {
	$ret='';
	my @diffcmd;

	if ($prog eq 'tla') {
	    @diffcmd = ($prog, 'diff', '-D', '-w', '--');
	} elsif ($prog eq 'baz') {
	    @diffcmd = ($prog, 'file-diff');
	} elsif ($prog eq 'bzr') {
	    @diffcmd = ($prog, 'diff', '--using', '/usr/bin/diff', '--diff-options', '-wu');
	} elsif ($prog eq 'git') {
	    if ($all) {
		@diffcmd = ('git', 'diff', '-w', '--no-color');
	    } else {
		@diffcmd = ('git', 'diff', '-w', '--cached', '--no-color');
	    }
	} elsif ($prog eq 'svn') {
	    @diffcmd = ($prog, 'diff', '--diff-cmd', '/usr/bin/diff', '--extensions', '-wu');
	} elsif ($prog eq 'svk') {
	    $ENV{'SVKDIFF'} = '/usr/bin/diff -w -u';
	    @diffcmd = ($prog, 'diff');
	} else {
	    @diffcmd = ($prog, 'diff', '-w');
	}

	open CHLOG, '-|', @diffcmd, $changelog
	    or die "debcommit: cannot run $diffcmd[0]: $!\n";

	foreach (<CHLOG>) {
	    next unless s/^\+(  |\t)//;
	    next if /^\s*\[.*\]\s*$/; # maintainer name
	    $ret .= $_;
	}
	
	if (! length $ret) {
	    if ($release) {
		return;
	    } else {
		my $info='';
		if ($prog eq 'git') {
		    $info = ' (do you mean "debcommit -a" or did you forget to run "git add"?)';
		}
		die "debcommit: unable to determine commit message using $prog$info\nTry using the -m flag.\n";
	    }
	} else {

	    if ($prog =~ /^(git|hg)$/) {
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
		    $summary =~ s/^\* // if $prog eq 'git' or $stripmessage;

		    if ($prog eq 'git') {
			$ret = $summary . "\n" . $ret;
		    } else {
			# Strip off the first change so that we can prepend
			# the unfolded version
			$ret =~ s/^\* .*?(^\s*[\*\+-] .*)/$1/msg;
			$ret = $summary . $ret;
		    }
		}
	    }

	    if ($stripmessage or $prog eq 'git') {
		my $count = () = $ret =~ /^\* /mg;
		if ($count == 1) {
		    $ret =~ s/^\* //;
		}
	    }
	}
    }
    else {
	die "debcommit: unknown program $prog";
    }

    chomp $ret;
    return $ret;
}

sub confirm {
    my $confirmmessage=shift;
    print $confirmmessage, "\n--\n";
    while(1) {
	print "OK to commit? [Y/n/e] ";
	$_ = <STDIN>;
	return 0 if /^n/i;
	if (/^(y|$)/i) {
	    $message = $confirmmessage;
	    return 1;
	} elsif (/^e/i) {
	    $confirmmessage = edit($confirmmessage);
	    print "\n", $confirmmessage, "\n--\n";
	}
    }
}

sub edit {
    my $message=shift;
    my $tempfile=".commit-tmp";
    open(FH, ">$tempfile") || die "debcommit: unable to create a temporary file.\n";
    print FH $message;
    close FH;
    system("sensible-editor $tempfile");
    open(FH, "<$tempfile") || die "debcommit: unable to open temporary file for reading\n";
    $message = "";
    while(<FH>) {
	$message .= $_;
    }
    close FH;
    unlink($tempfile);
    return $message;
}
=head1 LICENSE

This code is copyright by Joey Hess <joeyh@debian.org>, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.

=head1 AUTHOR

Joey Hess <joeyh@debian.org>

=head1 SEE ALSO

L<svnpath(1)>.

=cut
