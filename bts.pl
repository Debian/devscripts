#! /usr/bin/perl -w

# bts: This program provides a convenient interface to the Debian
# Bug Tracking System.
#
# Written by Joey Hess <joeyh@debian.org>
# Modifications by Julian Gilbey <jdg@debian.org>
# Copyright 2001-2003 Joey Hess <joeyh@debian.org>
# Modifications Copyright 2001-2003 Julian Gilbey <jdg@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=head1 NAME

bts - developers' command line interface to the BTS

=cut
#'

use 5.006_000;
use strict;
use File::Basename;
use File::Copy;
use File::Spec;
use File::Temp qw/tempfile/;
use IO::Handle;
use lib '/usr/share/devscripts';
use Devscripts::DB_File_Lock;
use Fcntl qw(O_RDWR O_RDONLY O_CREAT F_SETFD);

my $it = undef;
my $lwp_broken = undef;
sub have_lwp() {
    return $lwp_broken if defined $lwp_broken;
    eval {
	require LWP;
	require LWP::UserAgent;
	require HTTP::Status;
	require HTTP::Date;
    };

    if ($@) {
	if ($@ =~ m%^Can\'t locate LWP/%) {
	    $lwp_broken="the libwww-perl package is not installed";
	} else {
	    $lwp_broken="couldn't load LWP::UserAgent: $@";
	}
    }
    else { $lwp_broken=''; }
    return $lwp_broken ? 0 : 1;
}

# Constants
sub MIRROR_ERROR      { 0; }
sub MIRROR_DOWNLOADED { 1; }
sub MIRROR_UP_TO_DATE { 2; }


my $progname = basename($0);
my $version='###VERSION###';
my $debug = (exists $ENV{'DEBUG'} and $ENV{'DEBUG'}) ? 1 : 0;

# The official list is found at master.debian.org:/etc/debbugs/config
# in the variable @gTags; we copy it verbatim here.
our (@gTags, @valid_tags, %valid_tags);
@gTags = ( "patch", "wontfix", "moreinfo", "unreproducible", "fixed",
           "potato", "woody", "sid", "help", "security", "upstream",
           "pending", "sarge", "sarge-ignore", "experimental", "d-i", 
           "confirmed", "ipv6", "lfs", "fixed-in-experimental",
           "fixed-upstream", "l10n"
         );

*valid_tags = \@gTags;
%valid_tags = map { $_ => 1 } @valid_tags;
my @valid_severities=qw(wishlist minor normal important
			serious grave critical);

my $browser;  # Will set if necessary
my $btsurl='http://bugs.debian.org/';
my $btscgiurl='http://bugs.debian.org/cgi-bin/';
my $btsemail='control@bugs.debian.org';

my $cachedir=$ENV{'HOME'}."/.devscripts_cache/bts/";
my $timestampdb=$cachedir."bts_timestamps.db";
my $prunestamp=$cachedir."bts_prune.timestamp";

my %timestamp;
END {
    # This works even if we haven't tied it
    untie %timestamp;
}

# Can delete after sarge is released
my $oldcachedir=$ENV{'HOME'}."/.bts_cache/";
my $oldorigdir=$oldcachedir."orig/";
# my $timestamp=$cachedir."orig/manual.timestamp";

my %clonedbugs = ();

=head1 SYNOPSIS

B<bts> [options] command [args] [#comment] [.|, command [args] [#comment]] ...

=head1 DESCRIPTION

This is a command line interface to the bug tracking system, intended mainly
for use by developers. It lets the BTS be manipulated using simple commands
that can be run at the prompt or in a script, does various sanity checks on
the input, and constructs and sends a mail to the BTS control address for
you.

In general, the command line interface is the same as what you would write
in a mail to control@bugs.debian.org, just prefixed with "bts". For
example:

 % bts close 85942
 % bts severity 69042 normal
 % bts merge 69042 43233
 % bts retitle 69042 blah blah

A few additional commands have been added for your convenience, and this
program is less strict about what constitutes a valid bug number. For example,
"close Bug#85942" is understood, as is "close #85942".

Also, for your convenience, this program allows you to abbreviate commands
to the shortest unique substring (similar to how cvs lets you abbreviate
commands). So it understands things like "bts cl 85942".

It is also possible to include a comment in the mail sent to the BTS. If
your shell does not strip out the comment in a command like
"bts severity 30321 normal #inflated severity", then this program is smart
enough to figure out where the comment is, and include it in the email.
Note that most shells do strip out such comments before they get to the
program, unless the comment is quoted.

You can specify multiple commands by separating them with a single dot,
rather like B<update-rc.d>; a single comma may also be used; all the
commands will then be sent in a single mail. For example (quoting where
necessary so that B<bts> sees the comment):

 % bts severity 95672 normal , merge 95672 95673 \#they\'re the same!

Please use this program responsibly, and do take our users into
consideration.

=head1 OPTIONS

=over 4

=item -o, --offline

Make bts use cached bugs for the 'show' and 'bugs' commands, if a cache
is available for the requested data. See the cache command, below for
information on setting up a cache. Setting the BUGSOFFLINE environment
variable has the same effect.

=back

=cut

# For now, a very simple parser, instead of Getopt::Long since there are
# so few options.
my $offlinemode=(exists $ENV{'BUGSOFFLINE'});
foreach (@ARGV) {
    if (/^--(.*)/ || /^-(.*)/) {
	my $option=$1;
	shift @ARGV;
	if ($option eq 'offline' || $option eq 'o') {
	    $offlinemode=1;
	}
	elsif ($option eq 'help') { bts_help(); exit 0; }
	elsif ($option eq 'version') { bts_version(); exit 0; }
	else {
	    die "$progname: Unknown option, \"$option\"\nRun $progname --help for more information\n";
	}
    }
    else {
	last; # end of options
    }
}

# Command line parse.
if (@ARGV == 0) {
    bts_help();
    exit 0;
}
if ($ARGV[0] eq '--version') {
    bts_version();
    exit 0;
}
# Otherwise, parse the arguments
my @command;
my @args;
our @comment=('');
my $ncommand = 0;
my $iscommand = 1;
foreach (@ARGV) {
    if ($_ =~ /^[\.,]$/) {
	$ncommand++;
	$iscommand = 1;
	$comment[$ncommand] = '';
    }
    elsif ($iscommand) {
	push @command, $_;
	$iscommand = 0;
    }
    elsif ($comment[$ncommand] or /^\#/) {
	$comment[$ncommand] .= " $_";
    }
    else {
	push @{$args[$ncommand]}, $_;
    }
}
push @command, '' if $iscommand;

# Grub through the symbol table to find matching commands.
my $subject = '';
my $body = '';
our $index;
for $index (0 .. $ncommand) {
    my @matches=grep /^bts_\Q$command[$index]\E/, keys %::;
    if (@matches != 1) {
	die "$progname: Couldn't find a unique match for the command $command[$index]!\nRun $progname --help for a list of valid commands.\n";
    }
    no strict 'refs';
    $matches[0]->(@{$args[$index]});
}

# Send all cached commands.
mailbtsall($subject, $body) if length $body;

# Unnecessary, but we'll do this for clarity
exit 0;

=head1 COMMANDS

For full details about the commands, see the BTS documentation.

=over 4

=item show <bug>

Display a particular bug in a web browser using
L<sensible-browser(1)>.  If either the -o or --offline option is used,
or there is already an up-to-date copy in the local cache, the cached
version will be used.

Also, if caching has been enabled (that is, there exists a cache
directory ~/.devscripts_cache/bts/), then any page requested by "bts
show" will automatically be cached, and therefore available offline
thereafter.  Pages which are automatically cached in this way will be
deleted on subsequent "bts show|bugs|cache" invocations if they have
not been accessed in 30 days.

Any other B<bts> commands following this on the command line will be
executed after the browser has been exited.

The desired browser can be specified and configured by setting the
BROWSER environment variable.  The conventions follow those defined by
Eric Raymond at http://catb.org/~esr/BROWSER/; we here reproduce the
relevant part.

The value of BROWSER may consist of a colon-separated series of
browser command parts. These should be tried in order until one
succeeds. Each command part may optionally contain the string "%s"; if
it does, the URL to be viewed is substituted there. If a command part
does not contain %s, the browser is to be launched as if the URL had
been supplied as its first argument. The string %% must be substituted
as a single %.

Rationale: We need to be able to specify multiple browser commands so
programs obeying this convention can do the right thing in either X or
console environments, trying X first. Specifying multiple commands may
also be useful for people who share files like .profile across
multiple systems. We need %s because some popular browsers have
remote-invocation syntax that requires it. Unless %% reduces to %, it
won't be possible to have a literal %s in the string.

For example, on most Linux systems a good thing to do would be:

BROWSER='mozilla -raise -remote "openURL(%s,new-window)":links'

=cut
#'

sub bts_show {
    my $thing=shift or die "bts show: display what bug?\n";
    browse($thing);
}

=item bugs [<package> | src:<package> | <maintainer> | from:<submitter>]

=item bugs [tag:<tag> | <number> | : ]

Display the page listing the requested bugs in a web browser.  The
meanings of the possible arguments are as follows:

=over 8

=item (none)

If nothing is specified, bts bugs will display your bugs, assuming
that either DEBEMAIL or EMAIL (examined in that order) is set to the
appropriate email address.

=item <package>

Display the bugs for the package <package>.

=item src:<package>

Display the bugs for the source package <package>.

=item <maintainer>

Display the bugs for the maintainer email address <maintainer>.

=item from:<submitter>

Display the bugs for the submitter <submitter>.

=item tag:<tag>

Display the bugs which are tagged with <tag>.

=item <number>

Display bug number <number>.

=item :

Details of the bug tracking system itself, along with a bug-request
page with more options than this script, can be found on
http://bugs.debian.org/.  This page itself will be opened if the
command 'bts bugs :' is used.

=back

All of the other comments above about "bts show" apply equally to "bts
bugs".

=cut
#'

sub bts_bugs {
    my $url = shift;
    if (! $url) {
	if (defined $ENV{'DEBEMAIL'}) {
	    $url=$ENV{'DEBEMAIL'};
	} else {
	    if (defined $ENV{'EMAIL'}) {
		$url=$ENV{'EMAIL'};
	    } else {
		die "bts bugs: Please set DEBEMAIL or EMAIL to your Debian email address.\n";
	    }
	}
    }
    if ($url =~ /^.*\s+<(.*)>$/) { $url = $1; }
    $url =~ s/^:$//;
    browse($url);
}

=item clone <bug> [new IDs]

The clone control command allows you to duplicate a bug report. It is useful
in the case where a single report actually indicates that multiple distinct
bugs have occured. "New IDs" are negative numbers, separated by spaces,
which may be used in subsequent control commands to refer to the newly
duplicated bugs.  A new report is generated for each new ID.

=cut

sub bts_clone {
    my $bug=checkbug(shift) or die "bts clone: clone what bug?\n";
    @clonedbugs{@_} = (1) x @_;  # add these bug numbers to hash
    mailbts("cloning $bug", "clone $bug " . join(" ",@_));
}

# Don't include this in the manpage - it's deprecated
# 
# =item close <bug>
# 
# Close a bug. Remember that using this to close a bug is often bad manners,
# sending an informative mail to nnnnn-done@bugs.debian.org is much better.
# 
# =cut

sub bts_close {
    my $bug = checkbug(shift) || 'nnnnn';
    die "bts: The \"bts close\" command is deprecated!\nPlease email $bug-done\@bugs.debian.org with an informative mail instead.\n";
}

=item reopen <bug> [<submitter>]

Reopen a bug, with optional submitter.

=cut

sub bts_reopen {
    my $bug=checkbug(shift) or die "bts reopen: reopen what bug?\n";
    my $submitter=shift || ''; # optional
    mailbts("reopening $bug", "reopen $bug $submitter");
}

=item retitle <bug> <title>

Change the title of the bug.

=cut

sub bts_retitle {
    my $bug=checkbug(shift) or die "bts retitle: retitle what bug?\n";
    my $title=join(" ", @_);
    if (! length $title) {
	die "bts retitle: set title of $bug to what?\n";
    }
    mailbts("retitle $bug to $title", "retitle $bug $title");
}

=item submitter <bug> <submitter-email>

Change the submitter address of a bug, with `!' meaning
`use the address on the current email as the new submitter address'.

=cut
#'

sub bts_submitter {
    my $bug=checkbug(shift) or die "bts submitter: change submitter of what bug?\n";
    my $submitter=shift or die "bts submitter: change submitter to what?\n";
    mailbts("submitter $bug", "submitter $bug $submitter");
}

=item reassign <bug> <package>

Reassign a bug to a different package.

=cut

sub bts_reassign {
    my $bug=checkbug(shift) or die "bts reassign: reassign what bug?\n";
    my $package=shift or die "bts reassign: reassign \#$bug to what package?\n";
    mailbts("reassign $bug to $package", "reassign $bug $package");
}

=item merge <bug> <bug> [<bug> ...]

Merge a set of bugs together.

=cut

sub bts_merge {
    my @bugs;
    foreach (@_) {
	my $bug=checkbug($_) or die "bts merge: some bug number(s) not valid\n";
	push @bugs, $bug;
    }
    @bugs > 1 or
	die "bts merge: at least two bug numbers to be merged must be specified\n";
    mailbts("merging @bugs", "merge @bugs");
}

=item unmerge <bug>

Unmerge a bug.

=cut

sub bts_unmerge {
    my $bug=checkbug(shift) or die "bts unmerge: unmerge what bug?\n";
    mailbts("unmerging $bug", "unmerge $bug");
}

=item tag <bug> [+|-|=] tag [tag ..]

=item tags <bug> [+|-|=] tag [tag ..]

Set or unset a tag on a bug. The tag may either be the exact tag name
or it may be abbreviated to any unique tag substring. (So using
"fixed" will set the tag "fixed", not "fixed-upstream", for example,
but "fix" would not be acceptable.) Multiple tags may be specified as
well. The two commands (tag and tags) are identical. At least one tag
must be specified, unless the '=' flag is used, where the command

  bts tags <bug> =

will remove all tags from the specified bug.

=cut

sub bts_tags {
    my $bug=checkbug(shift) or die "bts tags: tag what bug?\n";
    if (! @_) {
	die "bts tags: set what tag?\n";
    }
    # Parse the rest of the command line.
    my $command="tags $bug";
    my $flag="";
    if ($_[0] =~ /^[-+=]$/) {
	$flag = $_[0];
	$command .= " $flag";
	shift;
    }
    if ($flag ne '=' && ! @_) {
	die "bts tags: set what tag?\n";
    }
    
    foreach my $tag (@_) {
	if (exists $valid_tags{$tag}) {
	    $command .= " $tag";
	} else {
	    # Try prefixes
	    my @matches = grep /^\Q$tag\E/, @valid_tags;
	    if (@matches != 1) {
		if ($tag =~ /^[-+=]/) {
		    die "bts tags: The +|-|= flag must not be joined to the tags.  Run bts help for usage info.\n";
		}
		die "bts tags: \"$tag\" is not a " . (@matches > 1 ? "unique" : "valid") . " tag prefix. Choose from: " . join(" ", @valid_tags) . "\n";
	    }
	    $command .= " $matches[0]";
	}
    }
    mailbts("tagging $bug", $command);
}

=item severity <bug> <severity>

Change the severity of a bug. The severity may be abbreviated to any unique
substring.

=cut

sub bts_severity {
    my $bug=checkbug(shift) or die "bts severity: change the severity of what bug?\n";
    my $severity=lc(shift) or die "bts severity: set \#$bug\'s severity to what?\n";
    my @matches = grep /^\Q$severity\E/i, @valid_severities;
    if (@matches != 1) {
	die "bts severity: \"$severity\" is not a valid severity.\nChoose from: @valid_severities\n";
    }
    mailbts("severity of $bug is $matches[0]", "severity $bug $matches[0]");
}

=item forwarded <bug> <email>

Mark the bug as forwarded to the given email address.

=cut

sub bts_forwarded {
    my $bug=checkbug(shift) or die "bts forwarded: mark what bug as forwarded?\n";
    my $email=join(' ', @_);
    if (! length $email) {
	die "bts forwarded: mark bug $bug as forwarded to what email address?\n";
    }
    mailbts("bug $bug is forwarded to $email", "forwarded $bug $email");
}

=item notforwarded <bug>

Mark a bug as not forwarded.

=cut

sub bts_notforwarded {
    my $bug=checkbug(shift) or die "bts notforwarded: what bug?\n";
    mailbts("bug $bug is not forwarded", "notforwarded $bug");
}

=item package [ <package> ... ]

The following commands will only apply to bugs against the listed
packages; this acts as a safety mechanism for the BTS.  If no packages
are listed, this check is turned off again.

=cut

sub bts_package {
    my $email=join(' ', @_);
    mailbts("setting package to $email", "package $email");
}

=item owner <bug> <owner-email>

Change the "owner" address of a bug, with `!' meaning
`use the address on the current email as the new owner address'.

The owner of a bug accepts the responsibility of dealing with it, and
will receive all of the email corresponding to the bug instead of the
usual maintainer.

=cut
#'

sub bts_owner {
    my $bug=checkbug(shift) or die "bts owner: change owner of what bug?\n";
    my $owner=shift or die "bts owner: change owner to what?\n";
    mailbts("owner $bug", "owner $bug $owner");
}

=item noowner <bug>

Mark a bug as having no "owner".

=cut

sub bts_noowner {
    my $bug=checkbug(shift) or die "bts noowner: what bug?\n";
    mailbts("bug $bug has no owner", "noowner $bug");
}

=item cache [<maint email> | <pkg> | src:<pkg> | from:<submitter>]

Generate or update a cache of bug reports for the given email address
or package. By default it downloads all bugs belonging to the email
address in the DEBEMAIL environment variable (or the EMAIL environment
variable if DEBEMAIL is unset). This command may be repeated to cache
bugs belonging to several people or packages. The cached bugs are
stored in ~/.devscripts_cache/bts/

Once you have set up a cache, you can ask for it to be used with the -o
switch. For example:

  bts -o bugs
  bts -o show 12345

The BUGSOFFLINE variable can also be set to do the same thing.

Also, once the cache is set up, bts will update the files in it in a
piecemeal fashion as it downloads information from the bts. You might
thus set up the cache, and update the whole thing once a week, while
letting the automatic cache updates update the bugs you frequently
refer to during the week.

A final benefit to using a cache is that it will speed download times
for bugs in the cache even when you're online, as it can just compare the
item in the cache with what's on the server, and not re-download it
every time.

=cut

sub bts_cache {
    prunecache();
    if (! have_lwp()) {
	die "Couldn't run bts cache: $lwp_broken\n";
    }

    if (! -d $cachedir) {
	if (! -d dirname($cachedir)) {
	    mkdir(dirname($cachedir))
		or die "bts: couldn't mkdir ".dirname($cachedir).": $!";
	}
	mkdir($cachedir)
	    or die "bts: couldn't mkdir $cachedir: $!";
    }
    
    my $tocache;
    if ($#_ != -1) { $tocache=shift; }
    else { $tocache=''; }
    
    if (! length $tocache) {
	$tocache=$ENV{'DEBEMAIL'} || $ENV{'EMAIL'};
	if ($tocache =~ /^.*\s+<(.*)>$/) { $tocache = $1; }
    }
    if (! length $tocache) {
	die "bts cache: cache what?\n";
    }

    my @oldbugs = bugs_from_thing($tocache);
    
    # download index
    download($tocache, 1);

    my %bugs = map { $_ => 1 } bugs_from_thing($tocache);

    # remove old bugs from cache
    if (@oldbugs) {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	    or die "bts: couldn't open DB file $timestampdb for writing: $!"
	    if ! tied %timestamp;
    }

    foreach my $bug (@oldbugs) {
	if (! $bugs{$bug}) {
	    deletecache($bug);
	}
    }

    untie %timestamp;
    
    # download bugs
    foreach my $bug (keys %bugs) {
	download($bug, 1);
    }
}

=item cleancache <package> | src:<package> | <maintainer>

=item cleancache from:<submitter> | tag:<tag> | <number> | ALL

Clean the cache for the specified package, maintainer, etc., as
described above for the "bugs" command, or clean the entire cache if
"ALL" is specified. This is useful if you are going to have permanent
network access or if the database has become corrupted for some
reason.  Note that for safety, this command does not default to the
value of DEBEMAIL or EMAIL.

=cut

sub bts_cleancache {
    prunecache();
    my $toclean=shift;
    if (! defined $toclean) {
	die "bts cleancache: clean what?\n";
    }
    if (! -d $cachedir) {
	return;
    }
    if ($toclean eq 'ALL') {
	if (system("/bin/rm", "-rf", $cachedir) >> 8 != 0) {
	    warn "Problems cleaning cache: $!\n";
	}
	return;
    }
    
    # clean index
    tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	 O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	or die "bts: couldn't open DB file $timestampdb for writing: $!"
	if ! tied %timestamp;

    if ($toclean =~ /^\d+$/) {
	# single bug only
	deletecache($toclean);
    } else {
	my @bugs_to_clean = bugs_from_thing($toclean);
	deletecache($toclean);
	
	# remove old bugs from cache
	foreach my $bug (@bugs_to_clean) {
	    deletecache($bug);
	}
    }

    untie %timestamp;
}

# Add any new commands here.

=item version

Display version and copyright information.

=cut

sub bts_version {
    print <<"EOF";
$progname version $version
Copyright (C) 2001-2003 by Joey Hess <joeyh\@debian.org>.
Modifications Copyright (C) 2002-2003 by Julian Gilbey <jdg\@debian.org>.
It is licensed under the terms of the GPL.
EOF
}

=item help

Display a short summary of commands, suspiciously similar to parts of this
man page.

=cut

# Other supporting subs

sub bts_help {
    my $insublist = 0;
    print "Usage: $progname [options] command [args] [#comment] [.|, command [args] [#comment]] ...\n";
    seek DATA, 0, 0;
    while (<DATA>) {
	$insublist = 1 if /^=over [^4]/;
	$insublist = 0 if /^=back/;
	print "\t$1\n" if /^=item\s(.*)/ and ! $insublist;
	last if defined $1 and $1 eq 'help';
    }
}

# Validate a bug number. Strips out extraneous leading junk, allowing
# for things like "#74041" and "Bug#94921"
sub checkbug {
    my $bug=$_[0] or return "";

    if ($bug eq 'it')
    {
      if (not defined $it)
      {
        die "You specified 'it', but no previous bug number referenced!\n";
      }
      else
      {
        return $it;
      }
    }
    
    $bug=~s/^[^-0-9]*//;
    if (! exists $clonedbugs{$bug} &&
	(! length $bug || $bug !~ /^[0-9]+$/)) {
	warn "\"$_[0]\" does not look like a bug number\n";
	return "";
    }

    # Valid, now set $it to this so that we can refer to it by 'it' later
    $it = $bug;

    return $bug;
}

# Stores up some extra information for a mail to the bts.
sub mailbts {
    if ($subject eq '') {
	$subject = $_[0];
    }
    elsif (length($subject) + length($_[0]) < 100) {
	$subject .= ", $_[0]";
    }
    else {
	$subject .= " ...";
    }
    $body .= "$comment[$index]\n" if $comment[$index];
    $body .= "$_[1]\n";
}

# Sends all cached mail to the bts (duh).
sub mailbtsall {
    my $subject=shift;
    my $body=shift;

    if ($ENV{'DEBEMAIL'} || $ENV{'EMAIL'}) {
	# We need to fake the From: line
	my ($email, $name);
	if (exists $ENV{'DEBFULLNAME'}) { $name = $ENV{'DEBFULLNAME'}; }
	if (exists $ENV{'DEBEMAIL'}) { $email = $ENV{'DEBEMAIL'}; }
	if (exists $ENV{'EMAIL'}) {
	    if ($ENV{'EMAIL'} =~ /^(.*)\s+<(.*)>$/) {
		$name ||= $1;
		$email ||= $2;
	    } else {
		$email ||= $ENV{'EMAIL'};
	    }
	}
	if (! $name) {
	    # Perhaps not ideal, but it will have to do
	    $name = (getpwuid($<))[6];
	    $name =~ s/,.*//;
	}
	my $from = $name ? "$name <$email>" : $email;
	my $date = `822-date`;
	chomp $date;

	my $pid = open(MAIL, "|-");
	if (! defined $pid) {
	    die "bts: Couldn't fork: $!";
	}
	if ($pid) {
	    # parent
	    print MAIL <<"EOM";
From: $from
To: $btsemail
Subject: $subject
Date: $date
X-BTS-Version: $version

# Automatically generated email from bts, devscripts version $version
$body
EOM
	    close MAIL or die "bts: sendmail error: $!";
	}
	else {
	    # child
	    if ($debug) {
		exec("/bin/cat")
		    or die "bts: error running cat: $!";
	    } else {
		exec("/usr/sbin/sendmail", "-t")
		    or die "bts: error running sendmail: $!";
	    }
	}
    }
    else {  # No DEBEMAIL
	unless (system("command -v mail >/dev/null 2>&1") == 0) {
	    die "bts: You need to either set DEBEMAIL or have the mailx package to do this!\n";
	}
	my $pid = open(MAIL, "|-");
	if ($pid) {
	    # parent
	    print MAIL $body;
	    close MAIL or die "bts: mail: $!";
	}
	else {
	    # child
	    exec("mail", "-s$subject", $btsemail)
		or die "bts: error running mail: $!";
	}
    }
}

##########  Browsing and caching subroutines

# Mirrors a given thing; if the online version is no newer than our
# cached version, then returns an empty string, otherwise returns the
# live thing as a (non-empty) string
sub download {
    my $thing=shift;
    my $manual=shift;  # true="bts cache", false="bts show/bug"
    my $timestamp;
    my $url;

    # What URL are we to download?
    $url = "$btsurl$thing";

    if (! -d $cachedir) {
	die "bts: download() called but no cachedir!";
    }

    chdir($cachedir) || die "bts: chdir $cachedir: $!";

    if (-f cachefile($thing)) {
	$timestamp = get_timestamp($thing) || 0;
	# And ensure we preserve any manual setting
	if (is_manual($timestamp)) { $manual = 1; }
    }

    print "Downloading $url ... ";
    IO::Handle::flush(\*STDOUT);
    my ($ret, $msg, $livepage) = bts_mirror($url, $timestamp);
    if ($ret == MIRROR_UP_TO_DATE) {
	# we have an up-to-date version already, nothing to do
	# and $timestamp is guaranteed to be well-defined
	if (is_automatic($timestamp) and $manual) {
	    set_timestamp($thing, make_manual($timestamp));
	}

	print "(cache already up-to-date)\n";
	return "";
    }
    elsif ($ret == MIRROR_DOWNLOADED) {
	# Note the current timestamp, but don't record it until
	# we've successfully stashed the data away
	$timestamp = time;

	die "bts: empty page downloaded" unless length $livepage;

	my $data = $livepage;  # work on a copy, not the original
	my $cachefile=cachefile($thing);
	open (OUT_CACHE, ">$cachefile") or die "bts: open $cachefile: $!";

	# Mangle downloaded file to work in the local cache, so
	# selectively modify the links

	# Undo unnecessary '+' encoding in URLs
	while ($data =~ s!(href=\"[^\"]*)\%2b!$1+!ig) { };
	my $time=localtime($timestamp);
	$data =~ s%(<BODY.*>)%$1<p><em>[Locally cached on $time]</em></p>%i;
	$data =~ s%<a href="[^\"]*(bugreport\.cgi(?:/[^\?]*)?\?bug=(\d+)&amp;msg=[^\"]*)">(.+?)</a>%$3 (<a href="http://bugs.debian.org/cgi-bin/$1">online</a>)%ig;
	$data =~ s%<a href="[^\"]*(bugreport\.cgi\?bug=(\d+)(?!\d|&amp;msg=)[^\"]*)">(.+?)</a>%<a href="$2.html">$3</a> (<a href="http://bugs.debian.org/cgi-bin/$1">online</a>)%ig;
	$data =~ s%<a href="[^\"]*(pkgreport\.cgi\?(?:pkg|maint)=([^\"&]+)[^\"]*)">(.+?)</a>%<a href="$2.html">$3</a> (<a href="http://bugs.debian.org/cgi-bin/$1">online</a>)%ig;
	$data =~ s%<a href="[^\"]*(pkgreport\.cgi\?src=([^\"&]+)[^\"]*)">(.+?)</a>%<a href="src_$2.html">$3</a> (<a href="http://bugs.debian.org/cgi-bin/$1">online</a>)%ig;
	$data =~ s%<a href="[^\"]*(pkgreport\.cgi\?submitter=([^\"\&]+)[^\"]*)">(.+?)</a>%<a href="from_$2.html">$3</a> (<a href="http://bugs.debian.org/cgi-bin/$1">online</a>)%ig;
	print OUT_CACHE $data;
	close OUT_CACHE or die "bts: problems writing to $cachefile: $!";

	set_timestamp($thing,
	    $manual ? make_manual($timestamp) : make_automatic($timestamp));

	print "(cached new version)\n";
	return $livepage;
    } else {
	die "bts: couldn't download $url:\n$msg\n";
    }
}

# Removes a specified thing from the cache
sub deletecache {
    my $thing=shift;

    if (! -d $cachedir) {
	die "bts: deletecache() called but no cachedir!";
    }

    delete_timestamp($thing);
    unlink cachefile($thing);
}

# Given a thing, returns the filename for it in the cache.
sub cachefile {
    my $thing=shift;
    if ($thing eq '') { die "bts: cachefile given empty argument"; }
    $thing =~ s/^src:/src_/;
    $thing =~ s/^from:/from_/;
    $thing =~ s/^tag:/tag_/;
    return $cachedir.$thing.".html";
}

# And the reverse: Given a filename in the cache, returns the corresponding
# "thing".
sub cachefile_to_thing {
    my $thing=basename(shift, '.html');
    $thing =~ s/^src_/src:/;
    $thing =~ s/^from_/from:/;
    $thing =~ s/^tag_/tag:/;
    return $thing;
}

# Given a thing, reads all links to bugs from the corresponding cache file
# if there is one, and returns a list of them.
sub bugs_from_thing {
    my $thing=shift;
    my $cachefile=cachefile($thing);

    if (-f $cachefile) {
	local $/;
	open (IN, $cachefile) || die "bts: open $cachefile: $!";
	my $data=<IN>;
	close IN;

	return $data =~ m!href="(\d+)\.html"!g;
    } else { return (); }
}

# Browses a given thing, with possible caching.
sub browse {
    prunecache();
    my $thing=shift;
    
    my $hascache=-d $cachedir;
    my $cachefile=cachefile($thing);

    # Check that if we're requesting a tag, that it's a valid tag
    if ($thing =~ /^tag:(.*)$/) {
	unless (exists $valid_tags{$1}) {
	    die "bts: invalid tag requested: $1\nRecognised tag names are: " . join(" ", @valid_tags) . "\n";
	}
    }

    if ($offlinemode) {
	if (! $hascache) {
	    die "bts: Sorry, you are in offline mode and have no cache. Run \"bts cache\" to create one.\n";
	}
	elsif (! -e $cachefile) {
	    die "bts: Sorry, you are in offline mode and that is not cached. Use \"bts cache\" to update the cache.\n";
	}
	runbrowser($cachefile);
    }
    # else we're in online mode
    elsif ($hascache && have_lwp() && $thing ne '') {
	my $live=download($thing);
	
	if (length($live)) {
	    my ($fh,$livefile) = tempfile("btsXXXXXX",
					  SUFFIX => ".html",
					  DIR => File::Spec->tmpdir,
					  UNLINK => 1);

	    # Use filehandle for security
	    open (OUT_LIVE, ">/dev/fd/" . fileno($fh))
		or die "bts: writing to temporary file: $!";
	    # Correct relative urls to point to the bts.
	    $live =~ s/(?!\/)(\w+\.cgi)/$btscgiurl$1/g;
	    print OUT_LIVE $live;
	    # Some browsers don't like unseekable filehandles, so use filename
	    runbrowser($livefile);
	} else {
	    runbrowser($cachefile);
	}
    }
    else {
	runbrowser($btsurl.$thing);
    }
}

# Removes all files from the cache which were downloaded automatically
# and have not been accessed for more than 30 days.  We also only run
# this at most once per day for efficiency.

sub prunecache {
    convertcache();
    return unless -d $cachedir;
    return if -f $prunestamp and -M _ < 1;

    chdir($cachedir) || die "bts: chdir $cachedir: $!";

    # remove the now-defunct live-download file
    unlink "live_download.html";

    opendir DIR, '.' or die "bts: opendir $cachedir: $!";
    my @cachefiles = grep { ! /^\.\.?$/ } readdir(DIR);
    closedir DIR;

    # Are there any unexpected files lying around?
    my @known_files = map { basename($_) } ($timestampdb, $timestampdb.".lock",
					    $prunestamp);

    my %weirdfiles = map { $_ => 1 } grep { ! /\.html$/ } @cachefiles;
    foreach (@known_files) {
	delete $weirdfiles{$_} if exists $weirdfiles{$_};
    }

    warn "bts: unexpected files in cache directory $cachedir:\n  " .
	join("\n  ", keys %weirdfiles) . "\n"
	if keys %weirdfiles;

    my @oldfiles;
    foreach (@cachefiles) {
	next unless /\.html$/;
	push @oldfiles, $_ if -A $_ > 30;
    }
    
    # We now remove the oldfiles if they're automatically downloaded
    tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	 O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	or die "bts: couldn't open DB file $timestampdb for writing: $!"
	if ! tied %timestamp;

    my @unrecognised;
    foreach my $oldfile (@oldfiles) {
	my $thing=cachefile_to_thing($oldfile);
	unless (exists $timestamp{$thing}) {
	    push @unrecognised, $oldfile;
	    next;
	}
	next if is_manual($timestamp{$thing});
	
	# Otherwise, it's automatic and we purge it
	deletecache($thing);
    }

    untie %timestamp;

    if (! -e $prunestamp) {
	open PRUNESTAMP, ">$prunestamp" || die "bts: prune timestamp: $!";
	close PRUNESTAMP;
    }
    utime time, time, $prunestamp;
}

# Determines which browser to use
sub runbrowser {
    my $URL = shift;
    
    if (system('sensible-browser', $URL) >> 8 != 0) {
	warn "Problem running sensible-browser: $!\n";
    }
}

# Timestamp handling
# 
# We store a +ve timestamp to represent an automatic download and
# a -ve one to represent a manual download.

sub get_timestamp {
    my $thing = shift;
    my $timestamp = undef;

    if (tied %timestamp) {
	$timestamp = abs($timestamp{$thing})
	    if exists $timestamp{$thing};
    } else {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDONLY(), 0600, $DB_HASH, "read")
	    or die "bts: couldn't open DB file $timestampdb for reading: $!";

	$timestamp = abs($timestamp{$thing})
	    if exists $timestamp{$thing};

	untie %timestamp;
    }

    return $timestamp;
}

sub set_timestamp {
    my $thing = shift;
    my $timestamp = shift;

    if (tied %timestamp) {
	$timestamp{$thing} = $timestamp;
    } else {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	    or die "bts: couldn't open DB file $timestampdb for writing: $!";

	$timestamp{$thing} = $timestamp;

	untie %timestamp;
    }
}

sub delete_timestamp {
    my $thing = shift;

    if (tied %timestamp) {
	delete $timestamp{$thing};
    } else {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	    or die "bts: couldn't open DB file $timestampdb for writing: $!";

	delete $timestamp{$thing};

	untie %timestamp;
    }
}

sub is_manual {
    return $_[0] < 0;
}

sub make_manual {
    return -abs($_[0]);
}

sub is_automatic {
    return $_[0] > 0;
}

sub make_automatic {
    return abs($_[0]);
}

# This converts the old caching scheme into the new one
# It can be dropped after sarge releases
sub convertcache {
    return unless -d $oldcachedir;

    my $msg_cachedir = $cachedir;
    $msg_cachedir =~ s%^$ENV{'HOME'}/%~/%;
    my $msg_oldcachedir = $oldcachedir;
    $msg_oldcachedir =~ s%^$ENV{'HOME'}/%~/%;
    my $msg_oldorigdir = $oldorigdir;
    $msg_oldorigdir =~ s%^$ENV{'HOME'}/%~/%;

    if (-d $cachedir) {
	warn <<"EOW";
The old-format cache directory:
  $msg_oldcachedir
is still present, even though the new-format one
  $msg_cachedir
has already been created.  So I\'m going to ignore the old cache.
(To prevent this message from appearing in future,
remove or rename the old cache directory.)
EOW
	if (-t STDIN) {
	    print STDERR "Hit <enter> to continue ";
	    IO::Handle::flush(\*STDERR);
	    my $answer = <STDIN>;
	}
	return;
    }
	
    if (! -d $oldorigdir) {
	warn <<"EOW";
The old-format cache directory:
  $msg_oldcachedir
is still present, but the old-format download directory
  $msg_oldorigdir
is not.  So I\'m going to ignore the old cache entirely.
(To prevent this message from appearing in future,
remove or rename the old cache directory.)
EOW
	if (-t STDIN) {
	    print STDERR "Hit <enter> to continue ";
	    IO::Handle::flush(\*STDERR);
	    my $answer = <STDIN>;
	}
	return;
    }

    # OK, so we've got an old cache which needs converting.  We
    # won't be as careful with this as we were when actually using
    # the old cache for real; if we can copy files across, great,
    # otherwise, don't do so.
    warn <<"EOW";
I see that you have an old-format cache directory:
  $msg_oldcachedir
The location and format of the bts cache changed in
devscripts version 2.7.93; the new cache directory is
  $msg_cachedir
so I\'m going to automatically convert your old cache
into the new format.
Converting....

EOW

    chdir $oldcachedir or die "bts: chdir $oldcachedir: $!";
    opendir DIR, $oldcachedir or die "bts: opendir $oldcachedir: $!";
    my @cachefiles = grep { -f $_ } readdir(DIR);
    closedir DIR;

    chdir $oldorigdir or die "bts: chdir $oldorigdir: $!";
    opendir DIR, $oldorigdir or die "bts: opendir $oldorigdir: $!";
    my @origfiles = grep { -f $_ } readdir(DIR);
    closedir DIR;
    my %manual = map { $_ => 1 } grep { s/\.manual$/.html/ } readdir (DIR);

    my %save_cache_stamps;
    foreach my $oldcache (@cachefiles) {
	my $thingbase = $oldcache;
	$thingbase =~ s/\.html$//;
	my $thingtype = '';
	if ($thingbase =~ /^\d+$/) { $thingtype = 'bug'; }
	elsif ($thingbase =~ s/^src_//) { $thingtype = 'src'; }
	elsif ($thingbase =~ s/^from_//) { $thingtype = 'submitter'; }
	elsif ($thingbase =~ /\@/) { $thingtype = 'maint'; }
	elsif ($thingbase =~ /^[a-z0-9+.-]{2,}$/) { $thingtype = 'pkg'; }
	# mangle the name for '+' in package names :-|
	$thingbase =~ s/\+/\%2b/g;

	foreach my $file (@origfiles) {
	    if ($file =~ /^\w+\.cgi\?$thingtype=$thingbase($|&)/) {
		my $timestamp = (stat("$oldcachedir$oldcache"))[9];
		next unless defined $timestamp;  # just skip errors
		if (exists $save_cache_stamps{$oldcache}) {
		    # Yuck - multiple files match; take the oldest timestamp
		    $save_cache_stamps{$oldcache} = $timestamp
			if $timestamp < $save_cache_stamps{$oldcache};
		} else {
		    $save_cache_stamps{$oldcache} = $timestamp;
		}
	    }
	}
    }

    # Now we have a list of files to save, we can copy them across
    # We assume that since the user had an old cache, they'll be happy
    # to have a new one ;-)
    if (! -d dirname($cachedir)) {
	mkdir(dirname($cachedir))
	    or die "bts: couldn't mkdir ".dirname($cachedir).": $!";
    }
    mkdir($cachedir)
	or die "bts: couldn't mkdir $cachedir: $!";

    tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	 O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	or die "bts: couldn't open DB file $timestampdb for writing: $!";

    foreach (keys %save_cache_stamps) {
	my $thing = $_;
	$thing =~ s/\.html$//;
	$thing =~ s/^src_/src:/;
	$thing =~ s/^from_/from:/;

	if (copy "$oldcachedir$_", "$cachedir$_") {
	    if (exists $manual{$_}) {
		set_timestamp($thing, make_manual($save_cache_stamps{$_}));
	    } else {
		set_timestamp($thing, make_automatic($save_cache_stamps{$_}));
	    }
	}
    }

    untie %timestamp;

    if (-t STDIN) {
	print STDERR <<"EOW";
Conversion successful.  Shall I remove your old cache directory
($msg_oldcachedir)?
(If you don\'t do so, you will get warnings in future.  You can say "no"
here and then rename the directory later if you wish.)
EOW
	print STDERR "Remove old cache? (y/n) ";
	IO::Handle::flush(\*STDERR);
	my $answer = <STDIN>;
	chomp($answer);
	if ($answer =~ /^y(es)?$/i) {
	    (system('/bin/rm', '-rf', $oldcachedir) == 0)
		or warn "Problems deleting $oldcachedir - please handle manually\n";
	} else {
	    print STDERR "OK, leaving old cache.  Please handle it manually.\n";
	}
    } else {
	print STDERR <<"EOW";
Conversion successful.  Please now remove or rename the old cache
directory ($msg_oldcachedir) or you will get warnings in future.
EOW
    }
}

# We would love to use LWP::Simple::mirror in this script.
# Unfortunately, bugs.debian.org does not respect the
# If-Modified-Since header.  For single bug reports, however,
# bugreport.cgi will return a Last-Modified header if sent a HEAD
# request.  So this is a hack, based on code from the LWP modules.  :-(
# Return value:
#  (return value, error string)
#  with return values:  MIRROR_ERROR        failed
#                       MIRROR_DOWNLOADED   downloaded new version
#                       MIRROR_UP_TO_DATE   up-to-date

my $ua;

sub bts_mirror {
    my ($url, $timestamp) = @_;

    init_agent() unless $ua;
    if ($url =~ m%/^\d+$%) {
	# Single bug, worth doing timestamp checks
	my $request = HTTP::Request->new('HEAD', $url);
	my $response = $ua->request($request);

	if ($response->is_success) {
	    my $lm = $response->last_modified;
	    if (defined $lm and $lm <= $timestamp) {
		return (MIRROR_UP_TO_DATE, $response->status_line);
	    }
	} else {
	    return (MIRROR_ERROR, $response->status_line);
	}
    }

    # So now we download the full thing regardless
    # We don't care if we scotch the contents of $file - it's only
    # a temporary file anyway
    my $request = HTTP::Request->new('GET', $url);
    my $response = $ua->request($request);

    if ($response->is_success) {
	# This check from LWP::UserAgent; I don't even know whether
	# the BTS sends a Content-Length header...
	my $nominal_content_length = $response->content_length || 0;
	my $true_content_length = defined $response->content ?
	    length($response->content) : 0;
	if ($true_content_length == 0) {
	    return (MIRROR_ERROR, $response->status_line);
	}
	if ($nominal_content_length > 0) {
	    if ($true_content_length < $nominal_content_length) {
		return (MIRROR_ERROR,
			"Transfer truncated: only $true_content_length out of $nominal_content_length bytes received");
	    }
	    if ($true_content_length > $nominal_content_length) {
		return (MIRROR_ERROR,
			"Content-length mismatch: expected $nominal_content_length bytes, got $true_content_length");
	    }
	    # else OK
	}
	return (MIRROR_DOWNLOADED, $response->status_line, $response->content);
    } else {
	return (MIRROR_ERROR, $response->status_line);
    }
}

sub init_agent {
    $ua = new LWP::UserAgent;  # we create a global UserAgent object
    $ua->agent("LWP::UserAgent/Devscripts/$version");
    $ua->env_proxy;
}

=back

=head1 ENVIRONMENT VARIABLES

=over 4

=item DEBEMAIL

If this is set, the From: line in the email will be set to use this email
address instead of your normal email address (as would be determined by
B<mail>).

=back

=over 4

=item DEBFULLNAME

If DEBEMAIL is set, DEBFULLNAME is examined to determine the full name
to use; if this is not set, B<bts> attempts to determine a name from
your passwd entry.

=back

=over 4

=item BROWSER

If set, it specifies the browser to use for the 'show' and 'bugs'
options.  See the description above.

=item BUGSOFFLINE

If set and if cached data exists, it will be used for the 'show' and 'bugs'
options. Equivilant to the -o switch.

=back

=head1 COPYRIGHT

This program is Copyright (C) 2001 by Joey Hess <joeyh@debian.org>.
It is licensed under the terms of the GPL.

=cut

# Please leave this alone unless you understand the seek above.
__DATA__
