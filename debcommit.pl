#!/usr/bin/perl

=head1 NAME

debcommit - commit changes to a package

=head1 SYNOPSIS

debcommit [--release] [--message=text] [--noact]

=head1 DESCRIPTION

debcommit generates a commit message based on new text in debian/changelog,
and commits the change to a package's cvs, svn, or arch repository. It must
be run in a cvs, svn, or arch working copy for the package.

=head1 OPTIONS

=over 4

=item -r --release

Commit a release of the package. The version number is determined from
debian/changelog, and is used to tag the package in cvs, svn, or arch.

Note that svn tagging conventions vary, so debcommit uses
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
	die "cannot find debian/changelog\n";
}

if ($release) {
	open (C, "<debian/changelog") || die "cannot read debian/changelog: $!";
	my $top=<C>;
	if ($top=~/UNRELEASED/) {
		die "debian/changelog says it's UNRELEASED\n";
	}
	close C;

	my $version=`dpkg-parsechangelog | grep Version: | cut -f 2 -d ' '`;
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
	else {
		die "not in a cvs or subversion working copy\n";
	}
}

sub action {
	my $prog=shift;
	print $prog." ".join(" ", map { if (/[^-A-Za-z0-9]/) { "'$_'" } else { $_ } } @_)."\n";
	return 1 if $noact;
	if (system($prog, @_) != 0) {
		return 0;
	}
	else {
		return 1;
	}
}

sub commit {
	my $message=shift;

	if ($prog eq 'cvs' || $prog eq 'svn') {
		if (! action($prog, "commit", "-m", $message)) {
			die "commit failed\n";
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
			die "commit failed\n";
		}
	}
	else {
		die "unknown program $prog";
	}
}

sub tag {
	my $tag=shift;

	if ($prog eq 'svn') {
		my $svnpath=`svnpath`;
		chomp $svnpath;
		my $tagpath=`svnpath tags`;
		chomp $tagpath;
		
		if (! action("svn", "copy", $svnpath, "$tagpath/$tag", "-m", "tagging version $tag")) {
			if (! action("svn", "mkdir", $tagpath, "-m", "create tag directory") ||
			    ! action("svn", "copy", $svnpath, "$tagpath/$tag", "-m", "tagging version $tag")) {
				die "failed tagging with $tag\n";
			}
		}
	}
	elsif ($prog eq 'cvs') {
		$tag=~s/^[0-9]+://; # strip epoch
		$tag=~tr/./_/;      # mangle for cvs
		if (! action("cvs", "tag", "-f", $tag)) {
			die "failed tagging with $tag\n";
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
			die "failed tagging with $tag\n";
		}
	}
}

sub getmessage {
	my $ret;

	if ($prog eq 'cvs' || $prog eq 'svn' ||
	    $prog eq 'tla' || $prog eq 'baz') {
		$ret='';
		my $subcommand;
		if ($prog eq 'cvs' || $prog eq 'svn') {
			$subcommand = 'diff';
		} else {
			$subcommand = 'file-diff';
		}
		foreach my $line (`$prog $subcommand debian/changelog`) {
			next unless $line=~/^\+  /;
			$line=~s/^\+  //;
			next if $line=~/^\s*\[.*\]\s*$/; # maintainer name
			$ret.=$line;
		}
		
		if (! length $ret) {
			die "Unable to determine commit message using $prog\nTry using the -m flag.\n";
		}
	}
	else {
		die "unknown program $prog";
	}

	chomp $ret;
	return $ret;
}

=head1 LICENSE

GPL

=head1 AUTHOR

Joey Hess <joeyh@debian.org>

=cut
