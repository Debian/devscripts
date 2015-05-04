#!/usr/bin/perl -w
#
# tagpending: Parse a Debian changelog for a list of bugs closed
# and tag any that are not already pending as such.
#
# The original shell version of tagpending was written by Joshua Kwan
# and is Copyright 2004 Joshua Kwan <joshk@triplehelix.org>
# with changes copyright 2004-07 by their respective authors.
#
# This version is
#   Copyright 2008 Adam D. Barratt
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;
use Getopt::Long qw(:config gnu_getopt);
use File::Basename;
use Devscripts::Debbugs;

sub bugs_info;

my $progname = basename($0);

my ($opt_help, $opt_version, $opt_verbose, $opt_noact, $opt_silent);
my ($opt_online, $opt_confirm, $opt_to, $opt_wnpp, $opt_comments);
my $opt_interactive;

# Default options
$opt_silent = 0;
$opt_verbose = 0;
$opt_online = 1;
$opt_noact = 0;
$opt_confirm = 0;
$opt_wnpp = 0;
$opt_to = '';
$opt_comments = 1;
$opt_interactive = 0;

GetOptions("help|h" => \$opt_help,
	   "version" => \$opt_version,
	   "verbose|v!" => \$opt_verbose,
	   "noact|n" => \$opt_noact,
	   "comments!" => \$opt_comments,
	   "silent|s" => \$opt_silent,
	   "force|f" => sub { $opt_online = 0; },
	   "confirm|c" => \$opt_confirm,
	   "to|t=s" => \$opt_to,
	   "wnpp|w" => \$opt_wnpp,
	   "interactive|i" => \$opt_interactive,
           )
    or die "Usage: $progname [options]\nRun $progname --help for more details\n";

$opt_to = "-v$opt_to" if $opt_to;

if ($opt_help) {
    help(); exit 0;
} elsif ($opt_version) {
    version(); exit 0;
}

if ($opt_verbose and $opt_silent) {
    die "$progname error: --silent and --verbose contradict each other\n";
}

=head1 NAME

tagpending - tags bugs that are to be closed in the latest changelog as pending

=head1 SYNOPSIS

B<tagpending> [I<options>]

=head1 DESCRIPTION

B<tagpending> parses debian/changelog to determine
which bugs would be closed if the package were uploaded. Each bug is
then marked as pending, using B<bts>(1) if it is not already so.

=head1 OPTIONS

=over 4

=item B<-n>, B<--noact>

Check whether any bugs require tagging, but do not actually do so.

=item B<-s>, B<--silent>

Do not output any messages.

=item B<-v>, B<--verbose>

List each bug checked and tagged in turn.

=item B<-f>, B<--force>

Do not query the BTS, but (re)tag all bugs closed in the changelog.

=item B<--comments>

Include the changelog header line and the entries relating to the tagged
bugs as comments in the generated mail.  This is the default.

Note that when used in combination with B<--to>, the header line output
will always be that of the most recent version.

=item B<--no-comments>

Do not include changelog entries in the generated mail.

=item B<-c>, B<--confirm>

Tag bugs as both confirmed and pending.

=item B<-t>, B<--to> I<version>

Parse changelogs for all versions strictly greater than I<version>.

Equivalent to B<dpkg-parsechangelog>'s B<-v> option.

=item B<-i>, B<--interactive>

Display the message which would be sent to the BTS and, except when
B<--noact> was used, prompt for confirmation before sending it.

=item B<-w>, B<--wnpp>

For each bug that does not appear to belong to the current package,
check whether it is filed against wnpp. If so, tag it. This allows e.g.
ITAs and ITPs closed in an upload to be tagged.

=back

=head1 SEE ALSO

B<bts>(1) and B<dpkg-parsechangelog>(1)

=cut

my $source;
my @closes;
my $in_changes=0;
my $changes='';
my $header='';

foreach my $file ("debian/changelog") {
    if (! -f $file) {
	die "$progname error: $file does not exist!\n";
    }
}

open PARSED, "dpkg-parsechangelog $opt_to |";

while (<PARSED>) {
    if (/^Source: (.*)/) {
	$source = $1;
    } elsif (/^Closes: (.*)$/) {
	@closes = split ' ', $1;
    } elsif (/^Changes: /) {
	$in_changes = 1;
    } elsif ($in_changes) {
	if ($header) {
	    next unless /^ {3}[^[]/;
	    $changes .= "\n" if $changes;
	    $changes .= $_;
	} else {
	    $header = $_;
	}
    }
}

close PARSED;

# Add a fake entry to the end of the recorded changes
# This makes the parsing of the changes simpler
$changes .= "   *";

my $pending;
my $open;

if ($opt_online) {
    if (!Devscripts::Debbugs::have_soap()) {
	die "$progname: The libsoap-lite-perl package is required for online operation; aborting.\n";
    }

    eval {
	$pending = Devscripts::Debbugs::select( "src:$source", "status:open", "status:forwarded", "tag:pending" );
	$open = Devscripts::Debbugs::select( "src:$source", "status:open", "status:forwarded" );
    };

    if ($@) {
	die "$@\nUse --force to tag all bugs anyway.\n";
    }
}

my %bugs = map { $_ => 1} @closes;
if ($pending) {
    %bugs = ( %bugs, map { $_ => 1} @{$pending} );
}

my $bug;
my $message;
my @to_tag = ();
my @wnpp_to_tag = ();

foreach $bug (keys %bugs) {
    print "Checking bug #$bug: " if $opt_verbose;

    if (grep /^$bug$/, @{$pending}) {
	print "already marked pending\n" if $opt_verbose;
    } else {
	if (grep /^$bug$/, @{$open} or not $opt_online) {
	    print "needs tag\n" if $opt_verbose;
	    push (@to_tag, $bug);
	} else {
	    if ($opt_wnpp) {
		my $status = Devscripts::Debbugs::status($bug);
		if ($status->{$bug}->{package} eq 'wnpp') {
		    if ($status->{$bug}->{tags} !~ /pending/) {
			print "wnpp needs tag\n" if $opt_verbose;
			push (@wnpp_to_tag, $bug);
		    } else {
			print "wnpp already marked pending\n" if $opt_verbose;
		    }
		} else {
		    $message = "is closed or does not belong to this package (check bug # or force)\n";

		    print "Warning: #$bug " if not $opt_verbose;
		    print "$message";
		}
	    } else {
		$message = "is closed or does not belong to this package (check bug # or force)\n";

		print "Warning: #$bug " if not $opt_verbose;
		print "$message";
	    }
	}
    }
}

if (!@to_tag and !@wnpp_to_tag) {
    print "$progname info: Nothing to do, exiting.\n"
	if $opt_verbose or !$opt_silent;
    exit 0;
}

my @sourcepkgs = ();
my @thiscloses = ();
my $thischange = '';
my $comments = '';

if (@to_tag or @wnpp_to_tag) {
    if ($opt_comments) {
	foreach my $change (split /\n/, $changes) {
            if ($change =~ /^ {3}\*(.*)/) {
		# Adapted from dpkg-parsechangelog / Changelog.pm
		while ($thischange && ($thischange =~
		  /closes:\s*(?:bug)?\#?\s?\d+(?:,\s*(?:bug)?\#?\s?\d+)*/sig)) {
		    push(@thiscloses, $& =~ /\#?\s?(\d+)/g);
		}

		foreach my $bug (@thiscloses) {
		    if ($bug and grep /^$bug$/, @to_tag or grep /^$bug$/, @wnpp_to_tag) {
			$comments .= $thischange;
			last;
		    }
		}

		@thiscloses = ();
		$thischange = $change;
	    } else {
		$thischange .= $change . "\n";
	    }
	}

	$comments = $header . "\n \n" . $comments . "\n \n"
	    if $comments;
    }
}

my @bts_args = ("bts", "--toolname", $progname);

if ($opt_noact and not $opt_interactive) {
    bugs_info;
    bugs_info "wnpp" if $opt_wnpp;
} else {
    if (!$opt_silent) {
	bugs_info;
	bugs_info "wnpp" if $opt_wnpp;
    }

    if ($opt_interactive) {
	if ($opt_noact) {
	    push(@bts_args, "-n");
	    print "\nWould send this BTS mail:\n\n";
	} else {
	    push(@bts_args, "-i");
	}
    }

    if (@to_tag) {
	push(@bts_args, "limit", "source:$source");

	if ($comments) {
	    $comments =~ s/\n\n/\n/sg;
	    $comments =~ s/\n\n/\n/m;
	    $comments =~ s/^ /#/mg;
	    push(@bts_args, $comments);
	    # We don't want to add comments twice if there are
            # both package and wnpp bugs
	    $comments = '';
	}

	foreach my $bug (@to_tag) {
	    push(@bts_args, ".", "tag", $bug, "+", "pending");
	    push(@bts_args, "confirmed") if $opt_confirm;
	}
    }
    if (@wnpp_to_tag) {
	push(@bts_args, ".") if scalar @bts_args > 1;
	push(@bts_args, "package", "wnpp");

	if ($comments) {
	    $comments =~ s/\n\n/\n/sg;
	    $comments =~ s/^ /#/mg;
	    push(@bts_args, $comments);
	}

	foreach my $wnpp_bug (@wnpp_to_tag) {
	    push(@bts_args, ".", "tag", $wnpp_bug, "+", "pending");
	}
    }

    system @bts_args;
}

sub bugs_info {
    my $type = shift || '';
    my @bugs;

    if ($type eq "wnpp") {
	if (@wnpp_to_tag) {
	    @bugs = @wnpp_to_tag;
	} else {
	    return;
	}
    } else {
	@bugs = @to_tag;
    }

    print "$progname info: ";

    if ($opt_noact) {
	print "would tag";
    } else {
	print "tagging";
    }

    print " these";
    print " wnpp" if $type eq "wnpp";
    print " bugs pending";
    print " and confirmed" if $opt_confirm and $type ne "wnpp";
    print ":";

    foreach my $bug (@bugs) {
	print " $bug";
    }

    print "\n";
}

sub help {
   print <<"EOF";
Usage: $progname [options]

Valid options are:
   --help, -h           Display this message
   --version            Display version and copyright info
    -n, --noact         Only simulate what would happen during this run;
			do not tag any bugs.
    -s, --silent        Silent mode
    -v, --verbose       Verbose mode: List bugs checked/tagged.
                        NOTE: Verbose and silent mode can't be used together.
    -f, --force         Do not query the BTS; (re-)tag all bug reports.
        --comments	Add the changelog header line and entries relating
                        to the bugs to be tagged to the generated mail.
                        (Default)
        --no-comments   Do not add changelog entries to the mail
    -c, --confirm       Tag bugs as confirmed as well as pending
    -t, --to <version>  Use changelog information from all versions strictly
			later than <version> (mimics dpkg-parsechangelog's
			-v option.)
    -i, --interactive   Display the message which would be sent to the BTS
			and, except if --noact was used, prompt for
			confirmation before sending it.
    -w, --wnpp          For each potentially not owned bug, check whether
			it is filed against wnpp and, if so, tag it. This
			allows e.g. ITA or ITPs to be tagged.

EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
Copyright 2008 by Adam D. Barratt <adam\@adam-barratt.org.uk>; based
on the shell script by Joshua Kwan <joshk\@triplehelix.org>.

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2, or (at your option) any
later version.
EOF
}

=head1 COPYRIGHT

This program is Copyright 2008 by Adam D. Barratt
<adam@adam-barratt.org.uk>.

The shell script tagpending, on which this program is based, is
Copyright 2004 by Joshua Kwan <joshk@triplehelix.org> with changes
copyright 2004-7 by their respective authors.

This program is licensed under the terms of the GPL, either version 2 of
the License, or (at your option) any later version.

=cut
