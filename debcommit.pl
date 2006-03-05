#!/usr/bin/perl

=head1 NAME

debcommit - commit changes to a package

=head1 SYNOPSIS

debcommit [--release] [--message=text] [--noact]

=head1 DESCRIPTION

debcommit generates a commit message based on new text in debian/changelog,
and commits the change to a package's cvs, svn, svk, arch, bzr or git
repository. It must be run in a cvs, svn, svk, arch, bzr or git working copy for
the package.

=head1 OPTIONS

=over 4

=item -r --release

Commit a release of the package. The version number is determined from
debian/changelog, and is used to tag the package in cvs, svn, svk, arch or git.
bzr does not yet support symbolic tags, so you will only get a normal
commit.

Note that svn/svk tagging conventions vary, so debcommit uses
L<svnpath(1)> to determine where the tag should be placed in the
repository.

=item -m text --message test

Specify a commit message to use. Useful if the program cannot determine
a commit message on its own based on debian/changelog, or if you want to
override the default message.

=item -n --noact

Do not actually do anything, but do print the commands that would be run.

=over 4

=back

=cut

use warnings;
use strict;
use Getopt::Long;

my $release=0;
my $message;
my $noact=0;
if (! GetOptions(
		 "release" => \$release,
		 "message=s" => \$message,
		 "noact" => \$noact,
		 )) {
    die "Usage: debcommit [--release] [--message=text] [--noact]\n";
}

my $prog=getprog();
if (! -e "debian/changelog") {
    die "debcommit: cannot find debian/changelog\n";
}

if ($release) {
    open (C, "<debian/changelog") || die "debcommit: cannot read debian/changelog: $!";
    my $top=<C>;
    if ($top=~/UNRELEASED/) {
	die "debcommit: debian/changelog says it's UNRELEASED\n";
    }
    close C;
    
    my $version=`dpkg-parsechangelog | grep '^Version:' | cut -f 2 -d ' '`;
    chomp $version;

    $message="releasing version $version" if ! defined $message;
    commit($message);
    tag($version);
}
else {
    $message=getmessage() if ! defined $message;
    commit($message);
}

sub getprog {
    if (-d ".svn") {
	return "svn";
    }
    elsif (-d "CVS") {
	return "cvs";
    }
    elsif (-d "{arch}") {
	# I don't think we can tell just from the working copy
	# whether to use tla or baz, so try baz if it's available,
	# otherwise fall back to tla.
	if (system ("baz --version >/dev/null 2>&1") == 0) {
	    return "baz";
	} else {
	    return "tla";
	}
    }
    elsif (-d ".bzr") {
	return "bzr";
    }
    elsif (-d ".git") {
	return "git";
    }
    else {
	# svk has no useful directories so try to run it.
	my $svkpath=`svk info . 2>/dev/null| grep -i '^Depot Path:' | cut -d ' ' -f 2`;
	if (length $svkpath) {
	    return "svk";
	}
	
	die "debcommit: not in a cvs, subversion, arch, bzr, git or svk working copy\n";
    }
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
    
    if ($prog eq 'cvs' || $prog eq 'svn' || $prog eq 'svk' || $prog eq 'bzr') {
	if (! action($prog, "commit", "-m", $message)) {
	    die "debcommit: commit failed\n";
	}
    }
    elsif ($prog eq 'git') {
	if (! action($prog, "commit", "-a", "-m", $message)) {
	    die "debcommit: commit failed\n";
	}
    }
    elsif ($prog eq 'tla' || $prog eq 'baz') {
	my $summary=$message;
	$summary=~s/^((?:\* )?[^\n]{1,72})(?:(?:\s|\n).*|$)/$1/ms;
	my @args;
	if ($summary eq $message) {
	    $summary=~s/^\* //s;
	    @args=("-s", $summary);
	} else {
	    $summary=~s/^\* //s;
	    @args=("-s", "$summary ...", "-L", $message);
	}
	if (! action($prog, "commit", @args)) {
	    die "debcommit: commit failed\n";
	}
    }
    else {
	die "debcommit: unknown program $prog";
    }
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
	warn "No support for symbolic tags in bzr yet.\n";
    }
    elsif ($prog eq 'git') {
	    $tag=~s/^[0-9]+://; # strip epoch
	    $tag="debian_version_$tag";
    	if (! action($prog, "tag", $tag)) {
	        die "debcommit: failed tagging with $tag\n";
    	}
    }
}

sub getmessage {
    my $ret;

    if ($prog eq 'cvs' || $prog eq 'svn' || $prog eq 'svk' ||
	$prog eq 'tla' || $prog eq 'baz' || $prog eq 'bzr' || $prog eq 'git') {
	$ret='';
	my @diffcmd;

	if ($prog eq 'tla' || $prog eq 'baz') {
	    @diffcmd = ($prog, 'file-diff');
	} elsif ($prog eq 'git') {
	    @diffcmd = ('git-diff', '--cached');
	} else {
	    @diffcmd = ($prog, 'diff');
	}

	open CHLOG, '-|', @diffcmd, 'debian/changelog'
	    or die "debcommit: cannot run $diffcmd[0]: $!\n";

	foreach (<CHLOG>) {
	    next unless /^\+  /;
	    s/^\+  //;
	    next if /^\s*\[.*\]\s*$/; # maintainer name
	    $ret .= $_;
	}
	
	if (! length $ret) {
	    die "debcommit: unable to determine commit message using $prog\nTry using the -m flag.\n";
	}
    }
    else {
	die "debcommit: unknown program $prog";
    }

    chomp $ret;
    return $ret;
}

=head1 LICENSE

GPL

=head1 AUTHOR

Joey Hess <joeyh@debian.org>

=cut
