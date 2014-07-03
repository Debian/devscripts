#!/usr/bin/perl -w

# bts: This program provides a convenient interface to the Debian
# Bug Tracking System.
#
# Written by Joey Hess <joeyh@debian.org>
# Modifications by Julian Gilbey <jdg@debian.org>
# Modifications by Josh Triplett <josh@freedesktop.org>
# Copyright 2001-2003 Joey Hess <joeyh@debian.org>
# Modifications Copyright 2001-2003 Julian Gilbey <jdg@debian.org>
# Modifications Copyright 2007 Josh Triplett <josh@freedesktop.org>
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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# Use our own subclass of Pod::Text to
# a) Strip the POD markup before displaying it via "bts help"
# b) Automatically display the text which is supposed to be replaced by the
#    user between <>, as per convention.
package Pod::BTS;
use strict;

use base qw(Pod::Text);

sub cmd_i { return '<' . $_[2] . '>' }

package main;

=head1 NAME

bts - developers' command line interface to the BTS

=cut

use 5.006_000;
use strict;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;
use File::Temp qw/tempfile/;
use Net::SMTP;
use Cwd;
use IO::File;
use IO::Handle;
BEGIN { push @INC, '/usr/share/devscripts'; }
use Devscripts::DB_File_Lock;
use Devscripts::Debbugs;
use Fcntl qw(O_RDWR O_RDONLY O_CREAT F_SETFD);
use Getopt::Long;
use Encode;

use Scalar::Util qw(looks_like_number);
use POSIX qw(locale_h strftime);

setlocale(LC_TIME, "C"); # so that strftime is locale independent

# Funny UTF-8 warning messages from HTML::Parse should be ignorable (#292671)
$SIG{'__WARN__'} = sub { warn $_[0] unless $_[0] =~ /^Parsing of undecoded UTF-8 will give garbage when decoding entities/; };

my $it = undef;
my $last_user = '';
my $lwp_broken = undef;
my $smtp_ssl_broken = undef;
my $authen_sasl_broken;
my $ua;

sub have_lwp() {
    return ($lwp_broken ? 0 : 1) if defined $lwp_broken;
    eval {
	require LWP;
	require LWP::UserAgent;
	require HTTP::Status;
	require HTTP::Date;
    };

    if ($@) {
	if ($@ =~ m%^Can\'t locate LWP%) {
	    $lwp_broken="the libwww-perl package is not installed";
	} else {
	    $lwp_broken="couldn't load LWP::UserAgent: $@";
	}
    }
    else { $lwp_broken=''; }
    return $lwp_broken ? 0 : 1;
}

sub have_smtp_ssl() {
    return ($smtp_ssl_broken ? 0 : 1) if defined $smtp_ssl_broken;
    eval {
	require Net::SMTP::SSL;
    };

    if ($@) {
	if ($@ =~ m%^Can\'t locate Net/SMTP/SSL%) {
	    $smtp_ssl_broken="the libnet-smtp-ssl-perl package is not installed";
	} else {
	    $smtp_ssl_broken="couldn't load Net::SMTP::SSL: $@";
	}
    }
    else { $smtp_ssl_broken=''; }
    return $smtp_ssl_broken ? 0 : 1;
}

sub have_authen_sasl() {
    return ($authen_sasl_broken ? 0 : 1) if defined $authen_sasl_broken;
    eval {
	require Authen::SASL;
    };

    if ($@) {
	if ($@ =~ m%^Can't locate Authen/SASL%) {
	    $authen_sasl_broken='the libauthen-sasl-perl package is not installed';
	} else {
	    $authen_sasl_broken="couldn't load Authen::SASL: $@";
	}
    }
    else { $authen_sasl_broken=''; }
    return $authen_sasl_broken ? 0 : 1;
}

# Constants
sub MIRROR_ERROR      { 0; }
sub MIRROR_DOWNLOADED { 1; }
sub MIRROR_UP_TO_DATE { 2; }
my $NONPRINT = "\\x00-\\x1F\\x7F-\\xFF"; # we need this later for MIME stuff

my $progname = basename($0);
my $modified_conf_msg;
my $debug = (exists $ENV{'DEBUG'} and $ENV{'DEBUG'}) ? 1 : 0;

# Program version handling
# The BTS changed its format :/  Pages downloaded using old versions
# of bts won't look very good, so we force updating if the last cached
# version was downloaded by a devscripts version less than
# $new_cache_format_version
my $version = '###VERSION###';
$version = '2.9.6' if $version =~ /\#/;  # for testing unconfigured version
my $new_cache_format_version = '2.9.6';

# The official list is mirrored
# bugs-mirror.debian.org:/org/bugs.debian.org/etc/config
# in the variable @gTags; we copy it verbatim here.
our (@gTags, @valid_tags, %valid_tags);
@gTags = ( "patch", "wontfix", "moreinfo", "unreproducible", "fixed",
           "potato", "woody", "sid", "help", "security", "upstream",
           "pending", "sarge", "sarge-ignore", "experimental", "d-i",
           "confirmed", "ipv6", "lfs", "fixed-in-experimental",
           "fixed-upstream", "l10n", "etch", "etch-ignore",
           "lenny", "lenny-ignore", "squeeze", "squeeze-ignore",
           "wheezy", "wheezy-ignore", "jessie", "jessie-ignore",
         );

*valid_tags = \@gTags;
%valid_tags = map { $_ => 1 } @valid_tags;
my @valid_severities=qw(wishlist minor normal important
			serious grave critical);

my $browser;  # Will set if necessary

my $cachedir=$ENV{'HOME'}."/.devscripts_cache/bts/";
my $timestampdb=$cachedir."bts_timestamps.db";
my $prunestamp=$cachedir."bts_prune.timestamp";

my %timestamp;
END {
    # This works even if we haven't tied it
    untie %timestamp;
}

my %clonedbugs = ();
my %ccpackages = ();
my %ccsubmitters = ();

=head1 SYNOPSIS

B<bts> [I<options>] I<command> [I<args>] [B<#>I<comment>] [B<.>|B<,> I<command> [I<args>] [B<#>I<comment>]] ...

=head1 DESCRIPTION

This is a command line interface to the Debian Bug Tracking System
(BTS), intended mainly
for use by developers. It lets the BTS be manipulated using simple commands
that can be run at the prompt or in a script, does various sanity checks on
the input, and constructs and sends a mail to the BTS control address for
you. A local cache of web pages and e-mails from the BTS may also be
created and updated.

In general, the command line interface is the same as what you would write
in a mail to control@bugs.debian.org, just prefixed with "bts". For
example:

 % bts severity 69042 normal
 % bts merge 69042 43233
 % bts retitle 69042 blah blah

A few additional commands have been added for your convenience, and this
program is less strict about what constitutes a valid bug number. For example,
"severity Bug#85942 normal" is understood, as is "severity #85942 normal".
(Of course, your shell may regard "#" as a comment character though, so you
may need to quote it!)

Also, for your convenience, this program allows you to abbreviate commands
to the shortest unique substring (similar to how cvs lets you abbreviate
commands). So it understands things like "bts cl 85942".

It is also possible to include a comment in the mail sent to the BTS. If
your shell does not strip out the comment in a command like
"bts severity 30321 normal #inflated severity", then this program is smart
enough to figure out where the comment is, and include it in the email.
Note that most shells do strip out such comments before they get to the
program, unless the comment is quoted.  (Something like "bts
severity #85942 normal" will not be treated as a comment!)

You can specify multiple commands by separating them with a single dot,
rather like B<update-rc.d>; a single comma may also be used; all the
commands will then be sent in a single mail. It is important the dot/comma is
surrounded by whitespace so it is not mistaken for part of a command.  For
example (quoting where necessary so that B<bts> sees the comment):

 % bts severity 95672 normal , merge 95672 95673 \#they are the same!

The abbreviation "it" may be used to refer to the last mentioned bug
number, so you could write:

 % bts severity 95672 wishlist , retitle it "bts: please add a --foo option"

Please use this program responsibly, and do take our users into
consideration.

=head1 OPTIONS

B<bts> examines the B<devscripts> configuration files as described
below.  Command line options override the configuration file settings,
though.

=over 4

=item B<-o>, B<--offline>

Make B<bts> use cached bugs for the B<show> and B<bugs> commands, if a cache
is available for the requested data. See the B<cache> command, below for
information on setting up a cache.

=item B<--online>, B<--no-offline>

Opposite of B<--offline>; overrides any configuration file directive to work
offline.

=item B<-n>, B<--no-action>

Do not send emails but print them to standard output.

=item B<--cache>, B<--no-cache>

Should we attempt to cache new versions of BTS pages when
performing B<show>/B<bugs> commands?  Default is to cache.

=item B<--cache-mode=>{B<min>|B<mbox>|B<full>}

When running a B<bts cache> command, should we only mirror the basic
bug (B<min>), or should we also mirror the mbox version (B<mbox>), or should
we mirror the whole thing, including the mbox and the boring
attachments to the BTS bug pages and the acknowledgement emails (B<full>)?
Default is B<min>.

=item B<--cache-delay=>I<seconds>

Time in seconds to delay between each download, to avoid hammering the BTS
web server. Default is 5 seconds.

=item B<--mbox>

Open a mail reader to read the mbox corresponding to a given bug number
for B<show> and B<bugs> commands.

=item B<--mailreader=>I<READER>

Specify the command to read the mbox.  Must contain a "B<%s>" string
(unquoted!), which will be replaced by the name of the mbox file.  The
command will be split on white space and will not be passed to a
shell.  Default is 'B<mutt -f %s>'.  (Also, B<%%> will be substituted by a
single B<%> if this is needed.)

=item B<--cc-addr=>I<CC_EMAIL_ADDRESS>

Send carbon copies to a list of users. I<CC_EMAIL_ADDRESS> should be a
comma-separated list of email addresses.

=item B<--use-default-cc>

Add the addresses specified in the configuration file option
B<BTS_DEFAULT_CC> to the list specified using B<--cc-addr>.  This is the
default.

=item B<--no-use-default-cc>

Do not add addresses specified in B<BTS_DEFAULT_CC> to the carbon copy
list.

=item B<--sendmail=>I<SENDMAILCMD>

Specify the B<sendmail> command.  The command will be split on white
space and will not be passed to a shell.  Default is
F</usr/sbin/sendmail>.  The B<-t> option will be automatically added if
the command is F</usr/sbin/sendmail> or F</usr/sbin/exim*>.  For other
mailers, if they require a B<-t> option, this must be included in the
I<SENDMAILCMD>, for example: B<--sendmail="/usr/sbin/mymailer -t">.

=item B<--mutt>

Use B<mutt> for sending of mails. Default is not to use B<mutt>, except for some
commands.

Note that one of B<$DEBEMAIL> or B<$EMAIL> must be set in the environment in order
to use B<mutt> to send emails.

=item B<--no-mutt>

Don't use B<mutt> for sending of mails.

=item B<--smtp-host=>I<SMTPHOST>

Specify an SMTP host.  If given, B<bts> will send mail by talking directly to
this SMTP host rather than by invoking a B<sendmail> command.

The host name may be followed by a colon (":") and a port number in
order to use a port other than the default.  It may also begin with
"ssmtp://" or "smtps://" to indicate that SMTPS should be used.

Note that one of B<$DEBEMAIL> or B<$EMAIL> must be set in the environment in order
to use direct SMTP connections to send emails.

Note that when sending directly via an SMTP host, specifying addresses in
B<--cc-addr> or B<BTS_DEFAULT_CC> that the SMTP host will not relay will cause the
SMTP host to reject the entire mail.

Note also that the use of the B<reassign> command may, when either B<--interactive>
or B<--force-interactive> mode is enabled, lead to the automatic addition of a Cc
to I<$newpackage>@packages.debian.org.  In these cases, the note above regarding
relaying applies.  The submission interface (port 587) on reportbug.debian.org
does not support relaying and, as such, should not be used as an SMTP server
for B<bts> under the circumstances described in this paragraph.

=item B<--smtp-username=>I<USERNAME>, B<--smtp-password=>I<PASSWORD>

Specify the credentials to use when connecting to the SMTP server
specified by B<--smtp-host>.  If the server does not require authentication
then these options should not be used.

If a username is specified but not a password, B<bts> will prompt for
the password before sending the mail.

=item B<--smtp-helo=>I<HELO>

Specify the name to use in the I<HELO> command when connecting to the SMTP
server; defaults to the contents of the file F</etc/mailname>, if it
exists.

Note that some SMTP servers may reject the use of a I<HELO> which either
does not resolve or does not appear to belong to the host using it.

=item B<--bts-server>

Use a debbugs server other than bugs.debian.org.

=item B<-f>, B<--force-refresh>

Download a bug report again, even if it does not appear to have
changed since the last B<cache> command.  Useful if a B<--cache-mode=full> is
requested for the first time (otherwise unchanged bug reports will not
be downloaded again, even if the boring bits have not been
downloaded).

=item B<--no-force-refresh>

Suppress any configuration file B<--force-refresh> option.

=item B<--only-new>

Download only new bugs when caching. Do not check for updates in
bugs we already have.

=item B<--include-resolved>

When caching bug reports, include those that are marked as resolved.  This
is the default behaviour.

=item B<--no-include-resolved>

Reverse the behaviour of the previous option.  That is, do not cache bugs
that are marked as resolved.

=item B<--no-ack>

Suppress acknowledgment mails from the BTS.  Note that this will only
affect the copies of messages CCed to bugs, not those sent to the
control bot.

=item B<--ack>

Do not suppress acknowledgement mails.  This is the default behaviour.

=item B<-i>, B<--interactive>

Before sending an e-mail to the control bot, display the content and
allow it to be edited, or the sending cancelled.

=item B<--force-interactive>

Similar to B<--interactive>, with the exception that an editor is spawned
before prompting for confirmation of the message to be sent.

=item B<--no-interactive>

Send control e-mails without confirmation.  This is the default behaviour.

=item B<-q>, B<--quiet>

When running B<bts cache>, only display information about newly cached
pages, not messages saying already cached.  If this option is
specified twice, only output error messages (to stderr).

=item B<--no-conf>, B<--noconf>

Do not read any configuration files.  This can only be used as the
first option given on the command-line.

=back

=cut

# Start by setting default values

my $offlinemode=0;
my $caching=1;
my $cachemode='min';
my $refreshmode=0;
my $updatemode=0;
my $mailreader='mutt -f %s';
my $muttcmd='mutt -H %s';
my $sendmailcmd='/usr/sbin/sendmail';
my $smtphost='';
my $smtpuser='';
my $smtppass='';
my $smtphelo='';
my $noaction=0;
# regexp for mailers which require a -t option
my $sendmail_t='^/usr/sbin/sendmail$|^/usr/sbin/exim';
my $includeresolved=1;
my $requestack=1;
my $interactive=0;
my $forceinteractive=0;
my $ccemail="";
my $toolname="";
my $btsserver='bugs.debian.org';
my $use_mutt = 0;

# Next, read read configuration files and then command line
# The next stuff is boilerplate

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'BTS_OFFLINE' => 'no',
		       'BTS_CACHE' => 'yes',
		       'BTS_CACHE_MODE' => 'min',
		       'BTS_FORCE_REFRESH' => 'no',
		       'BTS_ONLY_NEW' => 'no',
		       'BTS_MAIL_READER' => 'mutt -f %s',
		       'BTS_SENDMAIL_COMMAND' => '/usr/sbin/sendmail',
		       'BTS_INCLUDE_RESOLVED' => 'yes',
		       'BTS_SMTP_HOST' => '',
		       'BTS_SMTP_AUTH_USERNAME' => '',
		       'BTS_SMTP_AUTH_PASSWORD' => '',
		       'BTS_SMTP_HELO' => '',
		       'BTS_SUPPRESS_ACKS' => 'no',
		       'BTS_INTERACTIVE' => 'no',
		       'BTS_DEFAULT_CC' => '',
		       'BTS_SERVER' => 'bugs.debian.org',
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
    $config_vars{'BTS_OFFLINE'} =~ /^(yes|no)$/
	or $config_vars{'BTS_OFFLINE'}='no';
    $config_vars{'BTS_CACHE'} =~ /^(yes|no)$/
	or $config_vars{'BTS_CACHE'}='yes';
    $config_vars{'BTS_CACHE_MODE'} =~ /^(min|mbox|full)$/
	or $config_vars{'BTS_CACHE_MODE'}='min';
    $config_vars{'BTS_FORCE_REFRESH'} =~ /^(yes|no)$/
	or $config_vars{'BTS_FORCE_REFRESH'}='no';
    $config_vars{'BTS_ONLY_NEW'} =~ /^(yes|no)$/
	or $config_vars{'BTS_ONLY_NEW'}='no';
    $config_vars{'BTS_MAIL_READER'} =~ /\%s/
	or $config_vars{'BTS_MAIL_READER'}='mutt -f %s';
    $config_vars{'BTS_SENDMAIL_COMMAND'} =~ /./
	or $config_vars{'BTS_SENDMAIL_COMMAND'}='/usr/sbin/sendmail';
    $config_vars{'BTS_INCLUDE_RESOLVED'} =~ /^(yes|no)$/
	or $config_vars{'BTS_INCLUDE_RESOLVED'} = 'yes';
    $config_vars{'BTS_SUPPRESS_ACKS'} =~ /^(yes|no)$/
	or $config_vars{'BTS_SUPPRESS_ACKS'} = 'no';
    $config_vars{'BTS_INTERACTIVE'} =~ /^(yes|no|force)$/
	or $config_vars{'BTS_INTERACTIVE'} = 'no';

    if (!length $config_vars{'BTS_SMTP_HOST'}
        and $config_vars{'BTS_SENDMAIL_COMMAND'} ne '/usr/sbin/sendmail') {
	my $cmd = (split ' ', $config_vars{'BTS_SENDMAIL_COMMAND'})[0];
	unless ($cmd =~ /^~?[A-Za-z0-9_\-\+\.\/]*$/) {
	    warn "BTS_SENDMAIL_COMMAND contained funny characters: $cmd\nReverting to default value /usr/sbin/sendmail\n";
	    $config_vars{'BTS_SENDMAIL_COMMAND'}='/usr/sbin/sendmail';
	} elsif (system("command -v $cmd >/dev/null 2>&1") != 0) {
	    warn "BTS_SENDMAIL_COMMAND $cmd could not be executed.\nReverting to default value /usr/sbin/sendmail\n";
	    $config_vars{'BTS_SENDMAIL_COMMAND'}='/usr/sbin/sendmail';
	}
    }

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $offlinemode = $config_vars{'BTS_OFFLINE'} eq 'yes' ? 1 : 0;
    $caching = $config_vars{'BTS_CACHE'} eq 'no' ? 0 : 1;
    $cachemode = $config_vars{'BTS_CACHE_MODE'};
    $refreshmode = $config_vars{'BTS_FORCE_REFRESH'} eq 'yes' ? 1 : 0;
    $updatemode = $config_vars{'BTS_ONLY_NEW'} eq 'yes' ? 1 : 0;
    $mailreader = $config_vars{'BTS_MAIL_READER'};
    $sendmailcmd = $config_vars{'BTS_SENDMAIL_COMMAND'};
    $smtphost = $config_vars{'BTS_SMTP_HOST'};
    $smtpuser = $config_vars{'BTS_SMTP_AUTH_USERNAME'};
    $smtppass = $config_vars{'BTS_SMTP_AUTH_PASSWORD'};
    $smtphelo = $config_vars{'BTS_SMTP_HELO'};
    $includeresolved = $config_vars{'BTS_INCLUDE_RESOLVED'} eq 'yes' ? 1 : 0;
    $requestack = $config_vars{'BTS_SUPPRESS_ACKS'} eq 'no' ? 1 : 0;
    $interactive = $config_vars{'BTS_INTERACTIVE'} eq 'no' ? 0 : 1;
    $forceinteractive = $config_vars{'BTS_INTERACTIVE'} eq 'force' ? 1 : 0;
    $ccemail = $config_vars{'BTS_DEFAULT_CC'};
    $btsserver = $config_vars{'BTS_SERVER'};
}

if (exists $ENV{'BUGSOFFLINE'}) {
    warn "BUGSOFFLINE environment variable deprecated: please use ~/.devscripts\nor --offline/-o option instead!  (See bts(1) for details.)\n";
}

my ($opt_help, $opt_version, $opt_noconf);
my ($opt_cachemode, $opt_mailreader, $opt_sendmail, $opt_smtphost);
my ($opt_smtpuser, $opt_smtppass, $opt_smtphelo);
my $opt_cachedelay=5;
my $opt_mutt;
my $mboxmode = 0;
my $quiet=0;
my $opt_ccemail = "";
my $use_default_cc = 1;
my $ccsecurity="";

Getopt::Long::Configure(qw(gnu_compat bundling require_order));
GetOptions("help|h" => \$opt_help,
	   "version" => \$opt_version,
	   "o" => \$offlinemode,
	   "offline!" => \$offlinemode,
	   "online" => sub { $offlinemode = 0; },
	   "cache!" => \$caching,
	   "cache-mode|cachemode=s" => \$opt_cachemode,
	   "cache-delay=i" => \$opt_cachedelay,
	   "m|mbox" => \$mboxmode,
	   "mailreader|mail-reader=s" => \$opt_mailreader,
	   "cc-addr=s" => \$opt_ccemail,
	   "sendmail=s" => \$opt_sendmail,
	   "smtp-host|smtphost=s" => \$opt_smtphost,
	   "smtp-user|smtp-username=s" => \$opt_smtpuser,
	   "smtp-pass|smtp-password=s" => \$opt_smtppass,
	   "smtp-helo=s" => \$opt_smtphelo,
	   "f" => \$refreshmode,
	   "force-refresh!" => \$refreshmode,
	   "only-new!" => \$updatemode,
	   "n|no-action" => \$noaction,
	   "q|quiet+" => \$quiet,
	   "noconf|no-conf" => \$opt_noconf,
	   "include-resolved!" => \$includeresolved,
	   "ack!" => \$requestack,
	   "i|interactive" => \$interactive,
	   "no-interactive" => sub { $interactive = 0; $forceinteractive = 0; },
	   "force-interactive" => sub { $interactive = 1; $forceinteractive = 1; },
	   "use-default-cc!" => \$use_default_cc,
	   "toolname=s" => \$toolname,
	   "bts-server=s" => \$btsserver,
	   "mutt!" => \$opt_mutt,
	   )
    or die "Usage: $progname [options]\nRun $progname --help for more details\n";

if ($opt_noconf) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}
if ($opt_help) { bts_help(); exit 0; }
if ($opt_version) { bts_version(); exit 0; }

if (!$use_default_cc) {
    $ccemail = "";
}

if ($opt_ccemail) {
    $ccemail .= ", " if $ccemail;
    $ccemail .= $opt_ccemail;
}

if ($opt_mailreader) {
    if ($opt_mailreader =~ /\%s/) {
	$mailreader=$opt_mailreader;
    } else {
	warn "$progname: ignoring invalid --mailreader option: invalid mail command following it.\n";
    }
}

if ($opt_mutt) {
    $use_mutt = 1;
}

if ($opt_sendmail and $opt_smtphost) {
    die "$progname: --sendmail and --smtp-host mutually exclusive\n";
} elsif ($opt_mutt and $opt_sendmail) {
    die "$progname: --sendmail and --mutt mutually exclusive\n";
} elsif ($opt_mutt and $opt_smtphost) {
    die "$progname: --smtp-host and --mutt mutually exclusive\n";
}

$smtphost = $opt_smtphost if $opt_smtphost;
$smtpuser = $opt_smtpuser if $opt_smtpuser;
$smtppass = $opt_smtppass if $opt_smtppass;
$smtphelo = $opt_smtphelo if $opt_smtphelo;

if ($opt_sendmail) {
    if ($opt_sendmail ne '/usr/sbin/sendmail'
	and $opt_sendmail ne $sendmailcmd) {
	my $cmd = (split ' ', $opt_sendmail)[0];
	unless ($cmd =~ /^~?[A-Za-z0-9_\-\+\.\/]*$/) {
	    warn "--sendmail command contained funny characters: $cmd\nReverting to default value $sendmailcmd\n";
	    undef $opt_sendmail;
	} elsif (system("command -v $cmd >/dev/null 2>&1") != 0) {
	    warn "--sendmail command $cmd could not be executed.\nReverting to default value $sendmailcmd\n";
	    undef $opt_sendmail;
	}
    }
}

if ($opt_sendmail) {
    $sendmailcmd = $opt_sendmail;
    $smtphost = '';
} else {
    if (length $smtphost and ! length $smtphelo) {
	if (-e "/etc/mailname") {
	    if (open MAILNAME, '<', "/etc/mailname") {
		$smtphelo = <MAILNAME>;
		chomp $smtphelo;
		close MAILNAME;
	    } else {
		warn "Unable to open /etc/mailname: $!\nUsing default HELO for SMTP\n";
	    }
	}
    }
}

if ($opt_cachemode) {
    if ($opt_cachemode =~ /^(min|mbox|full)$/) {
	$cachemode=$opt_cachemode;
    } else {
	warn "$progname: ignoring invalid --cache-mode; must be one of min, mbox, full.\n";
    }
}

if ($toolname) {
    $toolname =" (using $toolname)";
}

my $btsurl;
if ($btsserver =~ m%^https?://(.*)/?$%) {
    $btsurl = $btsserver . '/';
    $btsserver=$1;
} else {
    $btsurl = "http://$btsserver/";
}
$btsurl =~ s%//$%/%;
my $btscgiurl=$btsurl . 'cgi-bin/';
my $btscgipkgurl=$btscgiurl . 'pkgreport.cgi';
my $btscgibugurl=$btscgiurl . 'bugreport.cgi';
my $btscgispamurl=$btscgiurl . 'bugspam.cgi';
my $btsemail='control@' . $btsserver;
my $packagesserver='';
if ($btsserver =~ /^bugs(-[\w-]+)?\.debian\.org/i) {
    $packagesserver = 'packages.debian.org';
    $btscgispamurl =~ s|$btsurl|http://bugs-master.debian.org/|;
}
no warnings 'once';
$Devscripts::Debbugs::btsurl=$btsurl;
use warnings 'once';

if (@ARGV == 0) {
    bts_help();
    exit 0;
}


# Otherwise, parse the arguments
my @command;
my @args;
our @comment=('');
my $ncommand = 0;
my $iscommand = 1;
while (@ARGV) {
    $_ = shift @ARGV;
    if ($_ =~ /^[\.,]$/) {
	next if $iscommand;  # ". ." in command line - oops!
	$ncommand++;
	$iscommand = 1;
	$comment[$ncommand] = '';
    }
    elsif ($iscommand) {
	push @command, $_;
	$iscommand = 0;
    }
    elsif ($comment[$ncommand]) {
	$comment[$ncommand] .= " $_";
    }
    elsif (/^\#/ and not /^\#\d+$/) {
	$comment[$ncommand] = $_;
    } else {
	push @{$args[$ncommand]}, $_;
    }
}
$ncommand-- if $iscommand;

# Grub through the symbol table to find matching commands.
my $subject = '';
my $body = '';
our $index;
for $index (0 .. $ncommand) {
    no strict 'refs';
    if (exists $::{"bts_$command[$index]"}) {
	"bts_$command[$index]"->(@{$args[$index]});
    } elsif ($command[$index] =~ /^#/) {
	mailbts('', $command[$index]);
    } else {
	my @matches=grep /^bts_\Q$command[$index]\E/, keys %::;
	if (@matches != 1) {
	    die "$progname: Couldn't find a unique match for the command $command[$index]!\nRun $progname --help for a list of valid commands.\n";
	}

	# Replace the abbreviated command with its expanded equivalent
	$command[$index] = $matches[0];
	$command[$index] =~ s/^bts_//;

	$matches[0]->(@{$args[$index]});
    }
}

# Send all cached commands.
mailbtsall($subject, $body) if length $body;

# Unnecessary, but we'll do this for clarity
exit 0;

=head1 COMMANDS

For full details about the commands, see the BTS documentation.
L<http://www.debian.org/Bugs/server-control>

=over 4

=item B<show> [I<options>] [I<bug number> | I<package> | I<maintainer> | B<:> ] [I<opt>B<=>I<val> ...]

=item B<show> [I<options>] [B<src:>I<package> | B<from:>I<submitter>] [I<opt>B<=>I<val> ...]

=item B<show> [I<options>] [B<tag:>I<tag> | B<usertag:>I<tag> ] [I<opt>B<=>I<val> ...]

=item B<show> [B<release-critical> | B<release-critical/>... | B<RC>]

This is a synonym for B<bts bugs>.

=cut

sub bts_show {
    goto &bts_bugs;
}

=item B<bugs> [I<options>] [I<bug_number> | I<package> | I<maintainer> | B<:> ] [I<opt>B<=>I<val> ...]

=item B<bugs> [I<options>] [B<src:>I<package> | B<from:>I<submitter>] [I<opt>B<=>I<val> ...]

=item B<bugs> [I<options>] [B<tag:>I<tag> | B<usertag:>I<tag> ] [I<opt>B<=>I<val> ...]

=item B<bugs> [B<release-critical> | B<release-critical/>... | B<RC>]

Display the page listing the requested bugs in a web browser using
sensible-browser(1).

Options may be specified after the B<bugs> command in addition to or
instead of options at the start of the command line: recognised
options at this point are: B<-o>/B<--offline>/B<--online>, B<-m>/B<--mbox>, B<--mailreader>
and B<-->[B<no->]B<cache>.  These are described earlier in this manpage.  If
either the B<-o> or B<--offline> option is used, or there is already an
up-to-date copy in the local cache, the cached version will be used.

The meanings of the possible arguments are as follows:

=over 8

=item (none)

If nothing is specified, B<bts bugs> will display your bugs, assuming
that either B<DEBEMAIL> or B<EMAIL> (examined in that order) is set to the
appropriate email address.

=item I<bug_number>

Display bug number I<bug_number>.

=item I<package>

Display the bugs for the package I<package>.

=item B<src:>I<package>

Display the bugs for the source package I<package>.

=item I<maintainer>

Display the bugs for the maintainer email address I<maintainer>.

=item B<from:>I<submitter>

Display the bugs for the submitter email address I<submitter>.

=item B<tag:>I<tag>

Display the bugs which are tagged with I<tag>.

=item B<usertag:>I<tag>

Display the bugs which are tagged with usertag I<tag>.  See the BTS
documentation for more information on usertags.  This will require the
use of a B<users=>I<email> option.

=item B<:>

Details of the bug tracking system itself, along with a bug-request
page with more options than this script, can be found on
http://bugs.debian.org/.  This page itself will be opened if the
command 'bts bugs :' is used.

=item B<release-critical>, B<RC>

Display the front page of the release-critical pages on the BTS.  This
is a synonym for http://bugs.debian.org/release-critical/index.html.
It is also possible to say release-critical/debian/main.html and the like.
RC is a synonym for release-critical/other/all.html.

=back

After the argument specifying what to display, you can optionally
specify options to use to format the page or change what it displayed.
These are passed to the BTS in the URL downloaded. For example, pass
dist=stable to see bugs affecting the stable version of a package,
version=1.0 to see bugs affecting that version of a package, or reverse=yes
to display newest messages first in a bug log.

If caching has been enabled (that is, B<--no-cache> has not been used,
and B<BTS_CACHE> has not been set to B<no>), then any page requested by
B<bts show> will automatically be cached, and be available offline
thereafter.  Pages which are automatically cached in this way will be
deleted on subsequent "B<bts show>|B<bugs>|B<cache>" invocations if they have
not been accessed in 30 days.  Warning: on a filesystem mounted with
the "noatime" option, running "B<bts show>|B<bugs>" does not update the cache
files' access times; a cached bug will then be subject to auto-cleaning
30 days after its initial download, even if it has been accessed in the
meantime.

Any other B<bts> commands following this on the command line will be
executed after the browser has been exited.

The desired browser can be specified and configured by setting the
B<BROWSER> environment variable.  The conventions follow those defined by
Eric Raymond at http://www.catb.org/~esr/BROWSER/; we here reproduce the
relevant part.

The value of B<BROWSER> may consist of a colon-separated series of
browser command parts. These should be tried in order until one
succeeds. Each command part may optionally contain the string B<%s>; if
it does, the URL to be viewed is substituted there. If a command part
does not contain B<%s>, the browser is to be launched as if the URL had
been supplied as its first argument. The string B<%%> must be substituted
as a single %.

Rationale: We need to be able to specify multiple browser commands so
programs obeying this convention can do the right thing in either X or
console environments, trying X first. Specifying multiple commands may
also be useful for people who share files like F<.profile> across
multiple systems. We need B<%s> because some popular browsers have
remote-invocation syntax that requires it. Unless B<%%> reduces to %, it
won't be possible to have a literal B<%s> in the string.

For example, on most Linux systems a good thing to do would be:

BROWSER='mozilla -raise -remote "openURL(%s,new-window)":links'

=cut

sub bts_bugs {
    @ARGV = @_; # needed for GetOptions
    my ($sub_offlinemode, $sub_caching, $sub_mboxmode, $sub_mailreader);
    GetOptions("o" => \$sub_offlinemode,
	       "offline!" => \$sub_offlinemode,
	       "online" => sub { $sub_offlinemode = 0; },
	       "cache!" => \$sub_caching,
	       "m|mbox" => \$sub_mboxmode,
	       "mailreader|mail-reader=s" => \$sub_mailreader,
	       )
    or die "$progname: unknown options for bugs command\n";
    @_ = @ARGV; # whatever's left

    if (defined $sub_offlinemode) {
	($offlinemode, $sub_offlinemode) = ($sub_offlinemode, $offlinemode);
    }
    if (defined $sub_caching) {
	($caching, $sub_caching) = ($sub_caching, $caching);
    }
    if (defined $sub_mboxmode) {
	($mboxmode, $sub_mboxmode) = ($sub_mboxmode, $mboxmode);
    }
    if (defined $sub_mailreader) {
	if ($sub_mailreader =~ /\%s/) {
	    ($mailreader, $sub_mailreader) = ($sub_mailreader, $mailreader);
	} else {
	    warn "$progname: ignoring invalid --mailreader $sub_mailreader option:\ninvalid mail command following it.\n";
	    $sub_mailreader = undef;
	}
    }

    my $url = sanitizething(shift);
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
    if ($url =~ /^.*\s<(.*)>\s*$/) { $url = $1; }
    $url =~ s/^:$//;

    # Are there any options?
    my $urlopts = '';
    if (@_) {
	$urlopts = join(";", '', @_); # so it'll be ";opt1=val1;opt2=val2"
	$urlopts =~ s/:/=/g;
	$urlopts =~ s/;tag=/;include=/;
    }

    browse($url, $urlopts);

    # revert options
    if (defined $sub_offlinemode) {
	$offlinemode = $sub_offlinemode;
    }
    if (defined $sub_caching) {
	$caching = $sub_caching;
    }
    if (defined $sub_mboxmode) {
	$mboxmode = $sub_mboxmode;
    }
    if (defined $sub_mailreader) {
	$mailreader = $sub_mailreader;
    }
}

=item B<select> [I<key>B<:>I<value> ...]

Uses the SOAP interface to output a list of bugs which match the given
selection requirements.

The following keys are allowed, and may be given multiple times.

=over 8

=item B<package>

Binary package name.

=item B<source>

Source package name.

=item B<maintainer>

E-mail address of the maintainer.

=item B<submitter>

E-mail address of the submitter.

=item B<severity>

Bug severity.

=item B<status>

Status of the bug.  One of B<open>, B<done>, or B<forwarded>.

=item B<tag>

Tags applied to the bug. If B<users> is specified, may include
usertags in addition to the standard tags.

=item B<owner>

Bug's owner.

=item B<correspondent>

Address of someone who sent mail to the log.

=item B<affects>

Bugs which affect this package.

=item B<bugs>

List of bugs to search within.

=item B<users>

Users to use when looking up usertags.

=item B<archive>

Whether to search archived bugs or normal bugs; defaults to B<0>
(i.e. only search normal bugs). As a special case, if archive is
B<both>, both archived and unarchived bugs are returned.

=back

For example, to select the set of bugs submitted by
jrandomdeveloper@example.com and tagged B<wontfix>, one would use

bts select submitter:jrandomdeveloper@example.com tag:wontfix

If a key is used multiple times then the set of bugs selected includes
those matching any of the supplied values; for example

bts select package:foo severity:wishlist severity:minor

returns all bugs of package foo with either wishlist or minor severity.

=cut

sub bts_select {
    my @args = @_;
    my $bugs = Devscripts::Debbugs::select(@args);
    if (not defined $bugs) {
	die "Error while retrieving bugs from SOAP server";
    }
    print map {qq($_\n)} @{$bugs};
}

=item B<status> [I<bug> | B<file:>I<file> | B<fields:>I<field>[B<,>I<field> ...] | B<verbose>] ...

Uses the SOAP interface to output status information for the given bugs
(or as read from the listed files -- use B<-> to indicate STDIN).

By default, all populated fields for a bug are displayed.

If B<verbose> is given, empty fields will also be displayed.

If B<fields> is given, only those fields will be displayed.  No validity
checking is performed on any specified fields.

=cut

sub bts_status {
    my @args = @_;

    my @bugs;
    my $showempty = 0;
    my %field;
    for my $bug (@args) {
	if (looks_like_number($bug)) {
	    push @bugs,$bug;
	}
	elsif ($bug =~ m{^file:(.+)}) {
	    my $file = $1;
	    my $fh;
	    if ($file eq '-') {
		$fh = \*STDIN;
	    }
	    else {
		$fh = IO::File->new($file,'r') or
		die "Unable to open $file for reading: $!";
	    }
	    while (<$fh>) {
		chomp;
		next if /^\s*\#/;
		s/\s//g;
		next unless looks_like_number($_);
		push @bugs,$_;
	    }
	}
	elsif ($bug =~ m{^fields:(.+)}) {
	    my $fields = $1;
	    for my $field (split /,/, $fields) {
		$field{lc $field} = 1;
	    }
	    $showempty = 1;
	}
	elsif ($bug =~ m{^verbose$}) {
	    $showempty = 1;
	}
    }
    my $bugs = Devscripts::Debbugs::status( map {[bug => $_, indicatesource => 1]} @bugs );
    return if ($bugs eq "");

    my $first = 1;
    for my $bug (keys %{$bugs}) {
	print "\n" if not $first;
	$first = 0;
	my @keys = grep {$_ ne 'bug_num'}
	keys %{$bugs->{$bug}};
	for my $key ('bug_num',@keys) {
	    if (%field) {
		next unless exists $field{$key};
	    }
	    my $out;
	    if (ref($bugs->{$bug}{$key}) eq 'ARRAY') {
		$out .= join(',',@{$bugs->{$bug}{$key}});
	    }
	    elsif (ref($bugs->{$bug}{$key}) eq 'HASH') {
		$out .= join(',',
		    map { $_ .' => '. ($bugs->{$bug}{$key}{$_}||'') }
		    keys %{$bugs->{$bug}{$key}}
		);
	    }
	    else {
		$out .= $bugs->{$bug}{$key}||'';
	    }
	    if ($out || $showempty) {
		print "$key\t$out\n";
	    }
	}
    }
}

=item B<clone> I<bug> I<new_ID> [I<new_ID> ...]

The B<clone> control command allows you to duplicate a I<bug> report. It is useful
in the case where a single report actually indicates that multiple distinct
bugs have occurred. "New IDs" are negative numbers, separated by spaces,
which may be used in subsequent control commands to refer to the newly
duplicated bugs.  A new report is generated for each new ID.

=cut

sub bts_clone {
    my $bug=checkbug(shift) or die "bts clone: clone what bug?\n";
    @_ or die "bts clone: must specify at least one new ID\n";
    foreach (@_) {
	$_ =~ /^-\d+$/ or die "bts clone: new IDs must be negative numbers\n";
	$clonedbugs{$_} = 1;
    }
    mailbts("cloning $bug", "clone $bug " . join(" ",@_));
}

sub common_close {
    my $bug=checkbug(shift) or die "bts $command[$index]: close what bug?\n";
    my $version=shift;
    $version="" unless defined $version;
    opts_done(@_);
    mailbts("closing $bug", "close $bug $version");
    return $bug;
}

# Do not include this in the manpage - it's deprecated
#
# =item B<close> I<bug> I<version>
#
# Close a I<bug>. Remember that using this to close a bug is often bad manners,
# sending an informative mail to nnnnn-done@bugs.debian.org is much better.
# You should specify which I<version> of the package closed the I<bug>, if
# possible.
#
# =cut

sub bts_close {
    my ($bug) = common_close(@_);
    warn <<"EOT";
$progname: Closing $bug as you requested.
Please note that the "$progname close" command is deprecated!
It is usually better to email nnnnnn-done\@$btsserver with
an informative mail.
Please remember to email $bug-submitter\@$btsserver with
an explanation of why you have closed this bug.  Thank you!
EOT
}

=item B<done> I<bug> [I<version>]

Mark a I<bug> as Done. This forces interactive mode since done messages should
include an explanation why the bug is being closed.  You should specify which
I<version> of the package closed the bug, if possible.

=cut

sub bts_done {
    my ($bug) = common_close(@_);
    # Force interactive mode since done mails shouldn't be sent without an
    # explanation
    if (not $use_mutt) {
	$forceinteractive = 1;
    }

    # Include the submitter in the email, so we act like a mail to -done
    $ccsubmitters{"$bug-submitter"} = 1;
}

=item B<reopen> I<bug> [I<submitter>]

Reopen a I<bug>, with optional I<submitter>.

=cut

sub bts_reopen {
    my $bug=checkbug(shift) or die "bts reopen: reopen what bug?\n";
    my $submitter=shift || ''; # optional
    opts_done(@_);
    mailbts("reopening $bug", "reopen $bug $submitter");
}

=item B<archive> I<bug>

Archive a I<bug> that has previously been archived but is currently not.
The I<bug> must fulfil all of the requirements for archiving with the
exception of those that are time-based.

=cut

sub bts_archive {
    my $bug=checkbug(shift) or die "bts archive: archive what bug?\n";
    opts_done(@_);
    mailbts("archiving $bug", "archive $bug");
}

=item B<unarchive> I<bug>

Unarchive a I<bug> that is currently archived.

=cut

sub bts_unarchive {
    my $bug=checkbug(shift) or die "bts unarchive: unarchive what bug?\n";
    opts_done(@_);
    mailbts("unarchiving $bug", "unarchive $bug");
}

=item B<retitle> I<bug> I<title>

Change the I<title> of the I<bug>.

=cut

sub bts_retitle {
    my $bug=checkbug(shift) or die "bts retitle: retitle what bug?\n";
    my $title=join(" ", @_);
    if (! length $title) {
	die "bts retitle: set title of $bug to what?\n";
    }
    mailbts("retitle $bug to $title", "retitle $bug $title");
}

=item B<summary> I<bug> [I<messagenum>]

Select a message number that should be used as
the summary of a I<bug>.

If no message number is given, the summary is cleared.

=cut

sub bts_summary {
    my $bug=checkbug(shift) or die "bts summary: change summary of what bug?\n";
    my $msg=shift || '';
    mailbts("summary $bug $msg", "summary $bug $msg");
}

=item B<submitter> I<bug> [I<bug> ...] I<submitter-email>

Change the submitter address of a I<bug> or a number of bugs, with B<!> meaning
`use the address on the current email as the new submitter address'.

=cut

sub bts_submitter {
    @_ or die "bts submitter: change submitter of what bug?\n";
    my $submitter=checkemail(pop, 1);
    if (!defined $submitter) {
	die "bts submitter: change submitter to what?\n";
    }
    foreach (@_) {
	my $bug=checkbug($_) or die "bts submitter: $_ is not a bug number\n";
	mailbts("submitter $bug", "submitter $bug $submitter");
    }
}

=item B<reassign> I<bug> [I<bug> ...] I<package> [I<version>]

Reassign a I<bug> or a number of bugs to a different I<package>.
The I<version> field is optional; see the explanation at
L<http://www.debian.org/Bugs/server-control>.

=cut

sub bts_reassign {
    my ($bug, @bugs);
    while ($_ = shift) {
	$bug=checkbug($_, 1) or last;
	push @bugs, $bug;
    }
    @bugs or die "bts reassign: reassign what bug(s)?\n";
    my $package=$_ or die "bts reassign: reassign bug(s) to what package?\n";
    my $version=shift;
    $version="" unless defined $version;
    if (length $version and $version !~ /\d/) {
	die "bts reassign: version number $version contains no digits!\n";
    }
    opts_done(@_);

    foreach $bug (@bugs) {
	mailbts("reassign $bug to $package", "reassign $bug $package $version");
    }

    foreach my $packagename (split /,/, $package) {
	$packagename =~ s/^src://;
	$ccpackages{$packagename} = 1;
    }
}

=item B<found> I<bug> [I<version>]

Indicate that a I<bug> was found to exist in a particular package version.
Without I<version>, the list of fixed versions is cleared and the bug is
reopened.

=cut

sub bts_found {
    my $bug=checkbug(shift) or die "bts found: found what bug?\n";
    my $version=shift;
    if (! defined $version) {
	warn "$progname: found has no version number, but sending to the BTS anyway\n";
	$version="";
    }
    opts_done(@_);
    mailbts("found $bug in $version", "found $bug $version");
}

=item B<notfound> I<bug> I<version>

Remove the record that I<bug> was encountered in the given version of the
package to which it is assigned.

=cut

sub bts_notfound {
    my $bug=checkbug(shift) or die "bts notfound: what bug?\n";
    my $version=shift or die "bts notfound: remove record \#$bug from which version?\n";
    opts_done(@_);
    mailbts("notfound $bug in $version", "notfound $bug $version");
}

=item B<fixed> I<bug> I<version>

Indicate that a I<bug> was fixed in a particular package version, without
affecting the I<bug>'s open/closed status.

=cut

sub bts_fixed {
    my $bug=checkbug(shift) or die "bts fixed: what bug?\n";
    my $version=shift or die "bts fixed: \#$bug fixed in which version?\n";
    opts_done(@_);
    mailbts("fixed $bug in $version", "fixed $bug $version");
}

=item B<notfixed> I<bug> I<version>

Remove the record that a I<bug> was fixed in the given version of the
package to which it is assigned.

This is equivalent to the sequence of commands "B<found> I<bug> I<version>",
"B<notfound> I<bug> I<version>".

=cut

sub bts_notfixed {
    my $bug=checkbug(shift) or die "bts notfixed: what bug?\n";
    my $version=shift or die "bts notfixed: remove record \#$bug from which version?\n";
    opts_done(@_);
    mailbts("notfixed $bug in $version", "notfixed $bug $version");
}

=item B<block> I<bug> B<by>|B<with> I<bug> [I<bug> ...]

Note that a I<bug> is blocked from being fixed by a set of other bugs.

=cut

sub bts_block {
    my $bug=checkbug(shift) or die "bts block: what bug is blocked?\n";
    my $word=shift;
    if (defined $word && $word ne 'by' && $word ne 'with') {
	    unshift @_, $word;
    }
    @_ or die "bts block: need to specify at least two bug numbers\n";
    my @blockers;
    foreach (@_) {
	my $blocker=checkbug($_) or die "bts block: some blocking bug number(s) not valid\n";
	push @blockers, $blocker;
    }
    mailbts("block $bug with @blockers", "block $bug with @blockers");
}

=item B<unblock> I<bug> B<by>|B<with> I<bug> [I<bug> ...]

Note that a I<bug> is no longer blocked from being fixed by a set of other bugs.

=cut

sub bts_unblock {
    my $bug=checkbug(shift) or die "bts unblock: what bug is blocked?\n";
    my $word=shift;
    if (defined $word && $word ne 'by' && $word ne 'with') {
	    unshift @_, $word;
    }
    @_ or die "bts unblock: need to specify at least two bug numbers\n";
    my @blockers;
    foreach (@_) {
	my $blocker=checkbug($_) or die "bts unblock: some blocking bug number(s) not valid\n";
	push @blockers, $blocker;
    }
    mailbts("unblock $bug with @blockers", "unblock $bug with @blockers");
}

=item B<merge> I<bug> I<bug> [I<bug> ...]

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

=item B<forcemerge> I<bug> I<bug> [I<bug> ...]

Forcibly merge a set of bugs together. The first I<bug> listed is the master bug,
and its settings (those which must be equal in a normal B<merge>) are assigned to
the bugs listed next.

=cut

sub bts_forcemerge {
    my @bugs;
    foreach (@_) {
	my $bug=checkbug($_) or die "bts forcemerge: some bug number(s) not valid\n";
	push @bugs, $bug;
    }
    @bugs > 1 or
	die "bts forcemerge: at least two bug numbers to be merged must be specified\n";
    mailbts("forcibly merging @bugs", "forcemerge @bugs");
}


=item B<unmerge> I<bug>

Unmerge a I<bug>.

=cut

sub bts_unmerge {
    my $bug=checkbug(shift) or die "bts unmerge: unmerge what bug?\n";
    opts_done(@_);
    mailbts("unmerging $bug", "unmerge $bug");
}

=item B<tag> I<bug> [B<+>|B<->|B<=>] I<tag> [I<tag> ...]

=item B<tags> I<bug> [B<+>|B<->|B<=>] I<tag> [I<tag> ...]

Set or unset a I<tag> on a I<bug>. The tag may either be the exact tag name
or it may be abbreviated to any unique tag substring. (So using
B<fixed> will set the tag B<fixed>, not B<fixed-upstream>, for example,
but B<fix> would not be acceptable.) Multiple tags may be specified as
well. The two commands (tag and tags) are identical. At least one tag
must be specified, unless the B<=> flag is used, where the command

  bts tags <bug> =

will remove all tags from the specified I<bug>.

As a special case, the unofficial B<gift> tag name is supported in
addition to official tag names. B<gift> is used as a shorthand for the
B<gift> usertag; see L<https://wiki.debian.org/qa.debian.org/GiftTag>.
Adding/removing the B<gift> tag will add/remove the B<gift> usertag,
belonging to the "debian-qa@lists.debian.org" user.

Adding/removing the B<security> tag will add "team\@security.debian.org"
to the Cc list of the control email.

=cut

sub bts_tags {
    my $bug=checkbug(shift) or die "bts tags: tag what bug?\n";
    if (! @_) {
	die "bts tags: set what tag?\n";
    }
    # Parse the rest of the command line.
    my $base_command="tags $bug";
    my $commands = [];

    my $curop;
    foreach my $tag (@_) {
	if ($tag =~ s/^([-+=])//) {
	    my $op = $1;
	    if ($op eq '=') {
		$curop = '=';
		$commands = [];
		$ccsecurity = '';
	    }
	    elsif (!$curop || $curop ne $op) {
		$curop = $op;
	    }
	    next unless $tag;
	}
	if (!$curop) {
	    $curop = '+';
	}
	if ($tag eq 'gift') {
	    my $gift_flag = $curop;
	    if ($gift_flag eq '=') {
		$gift_flag = '+';
	    }
	    mailbts("gifting $bug",
		"user debian-qa\@lists.debian.org\nusertag $bug $gift_flag gift");
	    next;
	}
	if (!exists $valid_tags{$tag}) {
	    # Try prefixes
	    my @matches = grep /^\Q$tag\E/, @valid_tags;
	    if (@matches != 1) {
		die "bts tags: \"$tag\" is not a " . (@matches > 1 ? "unique" : "valid") . " tag prefix. Choose from: " . join(" ", @valid_tags) . "\n";
	    }
	    $tag = $matches[0];
	}
	if (!@$commands || $curop ne $commands->[-1]{op}) {
	    push(@$commands, { op => $curop, tags => [] });
	}
	push(@{$commands->[-1]{tags}}, $tag);
	if ($tag eq "security") {
	    $ccsecurity = "team\@security.debian.org";
	}
    }

    my $command = '';
    foreach my $cmd (@$commands) {
	if ($cmd->{op} ne '=' && !@{$cmd->{tags}}) {
	    die "bts tags: set what tag?\n";
	}
	$command .= " $cmd->{op} " . join(' ', @{$cmd->{tags}});
    }
    if (!$command && $curop eq '=') {
        $command = " $curop";
    }

    if ($command) {
	mailbts("tagging $bug", $base_command . $command);
    }
}

=item B<affects> I<bug> [B<+>|B<->|B<=>] I<package> [I<package> ...]

Indicates that a I<bug> affects a I<package> other than that against which it is filed, causing
the I<bug> to be listed by default in the I<package> list of the other I<package>.  This should
generally be used where the I<bug> is severe enough to cause multiple reports from users to be
assigned to the wrong package.  At least one I<package> must be specified, unless
the B<=> flag is used, where the command

  bts affects <bug> =

will remove all indications that I<bug> affects other packages.

=cut

sub bts_affects {
    my $bug=checkbug(shift) or die "bts affects: mark what bug as affecting another package?\n";

    if (! @_) {
	die "bts affects: mark which package as affected?\n";
    }
    # Parse the rest of the command line.
    my $command="affects $bug";
    my $flag="";
    if ($_[0] =~ /^[-+=]$/) {
	$flag = $_[0];
	$command .= " $flag";
	shift;
    } elsif ($_[0] =~ s/^([-+=])//) {
	$flag = $1;
	$command .= " $flag";
    }

    if ($flag ne '=' && ! @_) {
	die "bts affects: mark which package as affected?\n";
    }

    foreach my $package (@_) {
	$command .= " $package";
    }

    mailbts("affects $bug", $command);
}

=item B<user> I<email>

Specify a user I<email> address before using the B<usertags> command.

=cut

sub bts_user {
    my $email=checkemail(shift) or die "bts user: set user to what email address?\n";
    if (! length $email) {
	die "bts user: set user to what email address?\n";
    }
    opts_done(@_);
    if ($email ne $last_user) {
	mailbts("user $email", "user $email");
    }
    $last_user = $email;
}

=item B<usertag> I<bug> [B<+>|B<->|B<=>] I<tag> [I<tag> ...]

=item B<usertags> I<bug> [B<+>|B<->|B<=>] I<tag> [I<tag> ...]

Set or unset a user tag on a I<bug>. The I<tag> must be the exact tag name wanted;
there are no defaults or checking of tag names.  Multiple tags may be
specified as well. The two commands (B<usertag> and B<usertags>) are identical.
At least one I<tag> must be specified, unless the B<=> flag is used, where the
command

  bts usertags <bug> =

will remove all user tags from the specified I<bug>.

=cut

sub bts_usertags {
    my $bug=checkbug(shift) or die "bts usertags: tag what bug?\n";
    if (! @_) {
	die "bts usertags: set what user tag?\n";
    }
    # Parse the rest of the command line.
    my $command="usertags $bug";
    my $flag="";
    if ($_[0] =~ /^[-+=]$/) {
	$flag = $_[0];
	$command .= " $flag";
	shift;
    } elsif ($_[0] =~ s/^([-+=])//) {
	$flag = $1;
	$command .= " $flag";
    }

    if ($flag ne '=' && ! @_) {
	die "bts usertags: set what user tag?\n";
    }

    $command .= sprintf(' %s', join(' ', @_));

    mailbts("usertagging $bug", $command);
}

=item B<claim> I<bug> [I<claim>]

Record that you have claimed a I<bug> (e.g. for a bug squashing party).
I<claim> should be a unique token allowing the bugs you have claimed
to be identified; an e-mail address is often used.

If no I<claim> is specified, the environment variable B<DEBEMAIL>
or B<EMAIL> (checked in that order) is used.

=cut

sub bts_claim {
    my $bug=checkbug(shift) or die "bts claim: claim what bug?\n";
    my $claim=checkemail(shift) || $ENV{'DEBEMAIL'} || $ENV{'EMAIL'} || "";
    if (! length $claim) {
	die "bts claim: use what claim token?\n";
    }
    $claim=extractemail($claim);
    bts_user("bugsquash\@qa.debian.org");
    bts_usertags("$bug" , "+$claim");
}

=item B<unclaim> I<bug> [I<claim>]

Remove the record that you have claimed a bug.

If no I<claim> is specified, the environment variable B<DEBEMAIL>
or B<EMAIL> (checked in that order) is used.

=cut

sub bts_unclaim {
    my $bug=checkbug(shift) or die "bts unclaim: unclaim what bug?\n";
    my $claim=checkemail(shift) || $ENV{'DEBEMAIL'} || $ENV{'EMAIL'} || "";
    if (! length $claim) {
	die "bts unclaim: use what claim token?\n";
    }
    $claim=extractemail($claim);
    bts_user("bugsquash\@qa.debian.org");
    bts_usertags("$bug" , "-$claim");
}

=item B<severity> I<bug> I<severity>

Change the I<severity> of a I<bug>. Available severities are: B<wishlist>, B<minor>, B<normal>,
B<important>, B<serious>, B<grave>, B<critical>. The severity may be abbreviated to any
unique substring.

=cut

sub bts_severity {
    my $bug=checkbug(shift) or die "bts severity: change the severity of what bug?\n";
    my $severity=lc(shift) or die "bts severity: set \#$bug\'s severity to what?\n";
    my @matches = grep /^\Q$severity\E/i, @valid_severities;
    if (@matches != 1) {
	die "bts severity: \"$severity\" is not a valid severity.\nChoose from: @valid_severities\n";
    }
    opts_done(@_);
    mailbts("severity of $bug is $matches[0]", "severity $bug $matches[0]");
}

=item B<forwarded> I<bug> I<address>

Mark the I<bug> as forwarded to the given I<address> (usually an email address or
a URL for an upstream bug tracker).

=cut

sub bts_forwarded {
    my $bug=checkbug(shift) or die "bts forwarded: mark what bug as forwarded?\n";
    my $email=join(' ', @_);
    if ($email =~ /$btsserver/) {
	die "bts forwarded: We don't forward bugs within $btsserver, use bts reassign instead\n";
    }
    if (! length $email) {
	die "bts forwarded: mark bug $bug as forwarded to what email address?\n";
    }
    mailbts("bug $bug is forwarded to $email", "forwarded $bug $email");
}

=item B<notforwarded> I<bug>

Mark a I<bug> as not forwarded.

=cut

sub bts_notforwarded {
    my $bug=checkbug(shift) or die "bts notforwarded: what bug?\n";
    opts_done(@_);
    mailbts("bug $bug is not forwarded", "notforwarded $bug");
}

=item B<package> [I<package> ...]

The following commands will only apply to bugs against the listed
I<package>s; this acts as a safety mechanism for the BTS.  If no packages
are listed, this check is turned off again.

=cut

sub bts_package {
    if (@_) {
        bts_limit(map { "package:$_" } @_);
    } else {
        bts_limit('package');
    }
}

=item B<limit> [I<key>[B<:>I<value>]] ...

The following commands will only apply to bugs which meet the specified
criterion; this acts as a safety mechanism for the BTS.  If no I<value>s are
listed, the limits for that I<key> are turned off again.  If no I<key>s are
specified, all limits are reset.

=over 8

=item B<submitter>

E-mail address of the submitter.

=item B<date>

Date the bug was submitted.

=item B<subject>

Subject of the bug.

=item B<msgid>

Message-id of the initial bug report.

=item B<package>

Binary package name.

=item B<source>

Source package name.

=item B<tag>

Tags applied to the bug.

=item B<severity>

Bug severity.

=item B<owner>

Bug's owner.

=item B<affects>

Bugs affecting this package.

=item B<archive>

Whether to search archived bugs or normal bugs; defaults to B<0>
(i.e. only search normal bugs). As a special case, if archive is
B<both>, both archived and unarchived bugs are returned.

=back

For example, to limit the set of bugs affected by the subsequent control
commands to those submitted by jrandomdeveloper@example.com and tagged
B<wontfix>, one would use

bts limit submitter:jrandomdeveloper@example.com tag:wontfix

If a key is used multiple times then the set of bugs selected includes
those matching any of the supplied values; for example

bts limit package:foo severity:wishlist severity:minor

only applies the subsequent control commands to bugs of package foo with
either B<wishlist> or B<minor> severity.

=cut

sub bts_limit {
    my @args=@_;
    my %limits;
    # Ensure we're using the limit fields that debbugs expects.  These are the
    # keys from Debbugs::Status::fields
    my %valid_keys = (submitter => 'originator',
                      date => 'date',
                      subject => 'subject',
                      msgid => 'msgid',
                      package => 'package',
                      source => 'source',
                      src => 'source',
                      tag => 'keywords',
                      severity => 'severity',
                      owner => 'owner',
                      affects => 'affects',
                      archive => 'unarchived',
    );
    for my $arg (@args) {
	my ($key,$value) = split /:/, $arg, 2;
	next unless $key;
	if (!defined $value) {
	    die "bts limit: No value given for '$key'\n";
	}
	if (exists $valid_keys{$key}) {
	    # Support "$key:" by making it look like "$key", i.e. no $value
	    # defined
	    undef $value unless length($value);
	    if ($key eq "archive") {
		if (defined $value) {
		    # limit looks for unarchived, not archive.  Verify we have
		    # a valid value and then switch the boolean value to match
		    # archive => unarchive
		    if ($value =~ /^yes|1|true|on$/i) {
			$value = 0;
		    } elsif ($value =~ /^no|0|false|off$/i) {
			$value = 1;
		    }
		    elsif ($value ne 'both') {
			die "bts limit: Invalid value ($value) for archive\n";
		    }
		}
	    }
	    $key = $valid_keys{$key};
	    if (defined $value and $value) {
		push(@{$limits{$key}},$value);
	    } else {
		$limits{$key} = ();
	    }
	} elsif ($key eq 'clear') {
	    %limits = ();
	    $limits{$key} = 1;
	} else {
	    die "bts limit: Unrecognized key: $key\n";
	}
    }
    for my $key (keys %limits) {
	if ($key eq 'clear') {
	    mailbts('clear all limit(s)', 'limit clear');
	    next;
	}
	if (defined $limits{$key}) {
	    my $value = join ' ', @{$limits{$key}};
	    mailbts("limit $key to $value", "limit $key $value");
	} else {
	    mailbts("clear $key limit", "limit $key");
	}
    }
}

=item B<owner> I<bug> I<owner-email>

Change the "owner" address of a I<bug>, with B<!> meaning
`use the address on the current email as the new owner address'.

The owner of a bug accepts responsibility for dealing with it.

=cut

sub bts_owner {
    my $bug=checkbug(shift) or die "bts owner: change owner of what bug?\n";
    my $owner=checkemail(shift, 1) or die "bts owner: change owner to what?\n";
    opts_done(@_);
    mailbts("owner $bug", "owner $bug $owner");
}

=item B<noowner> I<bug>

Mark a bug as having no "owner".

=cut

sub bts_noowner {
    my $bug=checkbug(shift) or die "bts noowner: what bug?\n";
    opts_done(@_);
    mailbts("bug $bug has no owner", "noowner $bug");
}

=item B<subscribe> I<bug> [I<email>]

Subscribe the given I<email> address to the specified I<bug> report.  If no email
address is specified, the environment variable B<DEBEMAIL> or B<EMAIL> (in that
order) is used.  If those are not set, or B<!> is given as email address,
your default address will be used.

After executing this command, you will be sent a subscription confirmation to
which you have to reply.  When subscribed to a bug report, you receive all
relevant emails and notifications.  Use the unsubscribe command to unsubscribe.

=cut

sub bts_subscribe {
    my $bug=checkbug(shift) or die "bts subscribe: subscribe to what bug?\n";
    my $email=checkemail(shift, 1);
    $email=lc($email) if defined $email;
    if (defined $email and $email eq '!') { $email = undef; }
    else {
	$email ||= $ENV{'DEBEMAIL'};
	$email ||= $ENV{'EMAIL'};
	$email = extractemail($email) if defined $email;
    }
    opts_done(@_);
    mailto('subscription request for bug #' . $bug, '',
	   $bug . '-subscribe@' . $btsserver, $email);
}

=item B<unsubscribe> I<bug> [I<email>]

Unsubscribe the given email address from the specified bug report.  As with
subscribe above, if no email address is specified, the environment variables
B<DEBEMAIL> or B<EMAIL> (in that order) is used.  If those are not set, or B<!> is
given as email address, your default address will be used.

After executing this command, you will be sent an unsubscription confirmation
to which you have to reply. Use the B<subscribe> command to, well, subscribe.

=cut

sub bts_unsubscribe {
    my $bug=checkbug(shift) or die "bts unsubscribe: unsubscribe from what bug?\n";
    my $email=checkemail(shift, 1);
    $email = lc($email) if defined $email;
    if (defined $email and $email eq '!') { $email = undef; }
    else {
	$email ||= $ENV{'DEBEMAIL'};
	$email ||= $ENV{'EMAIL'};
	$email = extractemail($email) if defined $email;
    }
    opts_done(@_);
    mailto('unsubscription request for bug #' . $bug, '',
	   $bug . '-unsubscribe@' . $btsserver, $email);
}

=item B<reportspam> I<bug> ...

The B<reportspam> command allows you to report a I<bug> report as containing spam.
It saves one from having to go to the bug web page to do so.

=cut

sub bts_reportspam {
    my @bugs;

    if (! have_lwp()) {
	die "$progname: Couldn't run bts reportspam: $lwp_broken\n";
    }

    foreach (@_) {
	my $bug=checkbug($_) or die "bts reportspam: some bug number(s) not valid\n";
	push @bugs, $bug;
    }
    @bugs >= 1 or
	die "bts reportspam: at least one bug number must be specified\n";

    init_agent() unless $ua;
    foreach my $bug (@bugs) {
	my $url = "$btscgispamurl?bug=$bug;ok=ok";
	if ($noaction) {
	    print "bts reportspam: would report $bug as containing spam (URL: " .
		$url . ")\n";
	} else {
	    my $request = HTTP::Request->new('GET', $url);
	    my $response = $ua->request($request);
	    if (! $response->is_success) {
		warn "$progname: failed to report $bug as containing spam: " .
		    $response->status_line . "\n";
	    }
	}
    }
}

=item B<spamreport> I<bug> ...

B<spamreport> is a synonym for B<reportspam>.

=cut

sub bts_spamreport {
    goto &bts_reportspam;
}

=item B<cache> [I<options>] [I<maint_email> | I<pkg> | B<src:>I<pkg> | B<from:>I<submitter>]

=item B<cache> [I<options>] [B<release-critical> | B<release-critical/>... | B<RC>]

Generate or update a cache of bug reports for the given email address
or package. By default it downloads all bugs belonging to the email
address in the B<DEBEMAIL> environment variable (or the B<EMAIL> environment
variable if B<DEBEMAIL> is unset). This command may be repeated to cache
bugs belonging to several people or packages. If multiple packages or
addresses are supplied, bugs belonging to any of the arguments will be
cached; those belonging to more than one of the arguments will only be
downloaded once. The cached bugs are stored in F<~/.devscripts_cache/bts/>.

You can use the cached bugs with the B<-o> switch. For example:

  bts -o bugs
  bts -o show 12345

Also, B<bts> will update the files in it in a piecemeal fashion as it
downloads information from the BTS using the B<show> command. You might
thus set up the cache, and update the whole thing once a week, while
letting the automatic cache updates update the bugs you frequently
refer to during the week.

Some options affect the behaviour of the B<cache> command.  The first is
the setting of B<--cache-mode>, which controls how much B<bts> downloads
of the referenced links from the bug page, including boring bits such
as the acknowledgement emails, emails to the control bot, and the mbox
version of the bug report.  It can take three values: B<min> (the
minimum), B<mbox> (download the minimum plus the mbox version of the bug
report) or B<full> (the whole works).  The second is B<--force-refresh> or
B<-f>, which forces the download, even if the cached bug report is
up-to-date.  The B<--include-resolved> option indicates whether bug
reports marked as resolved should be downloaded during caching.

Each of these is configurable from the configuration
file, as described below.  They may also be specified after the
B<cache> command as well as at the start of the command line.

Finally, B<-q> or B<--quiet> will suppress messages about caches being
up-to-date, and giving the option twice will suppress all cache
messages (except for error messages).

Beware of caching RC, though: it will take a LONG time!  (With 1000+
RC bugs and a delay of 5 seconds between bugs, you're looking at a
minimum of 1.5 hours, and probably significantly more than that.)

=cut

sub bts_cache {
    @ARGV = @_;
    my ($sub_cachemode, $sub_refreshmode, $sub_updatemode);
    my $sub_quiet = $quiet;
    my $sub_includeresolved = $includeresolved;
    GetOptions("cache-mode|cachemode=s" => \$sub_cachemode,
	       "f" => \$sub_refreshmode,
	       "force-refresh!" => \$sub_refreshmode,
	       "only-new!" => \$sub_updatemode,
	       "q|quiet+" => \$sub_quiet,
	       "include-resolved!" => \$sub_includeresolved,
	       )
    or die "$progname: unknown options for cache command\n";
    @_ = @ARGV; # whatever's left

    if (defined $sub_refreshmode) {
	($refreshmode, $sub_refreshmode) = ($sub_refreshmode, $refreshmode);
    }
    if (defined $sub_updatemode) {
	($updatemode, $sub_updatemode) = ($sub_updatemode, $updatemode);
    }
    if (defined $sub_cachemode) {
	if ($sub_cachemode =~ /^(min|mbox|full)$/) {
	    ($cachemode, $sub_cachemode) = ($sub_cachemode, $cachemode);
	} else {
	    warn "$progname: ignoring invalid --cache-mode $sub_cachemode;\nmust be one of min, mbox, full.\n";
	}
    }
    # This may be a no-op, we don't mind
    ($quiet, $sub_quiet) = ($sub_quiet, $quiet);
    ($includeresolved, $sub_includeresolved) = ($sub_includeresolved, $includeresolved);

    prunecache();
    if (! have_lwp()) {
	die "$progname: Couldn't run bts cache: $lwp_broken\n";
    }

    if (! -d $cachedir) {
	if (! -d dirname($cachedir)) {
	    mkdir(dirname($cachedir))
		or die "$progname: couldn't mkdir ".dirname($cachedir).": $!\n";
	}
	mkdir($cachedir)
	    or die "$progname: couldn't mkdir $cachedir: $!\n";
    }

    download("css/bugs.css");

    my $tocache;
    if (@_ > 0) { $tocache=sanitizething(shift); }
    else { $tocache=''; }

    if (! length $tocache) {
	$tocache=$ENV{'DEBEMAIL'} || $ENV{'EMAIL'} || '';
	if ($tocache =~ /^.*\s<(.*)>\s*$/) { $tocache = $1; }
    }
    if (! length $tocache) {
	die "bts cache: cache what?\n";
    }

    my $sub_thgopts = '';
    $sub_thgopts = ';pend-exc=done'
	if (! $includeresolved && $tocache !~ /^release-critical/);

    my %bugs = ();
    my %oldbugs = ();

    do {
	%oldbugs = (%oldbugs, map { $_ => 1 } bugs_from_thing($tocache, $sub_thgopts));

	# download index
	download($tocache, $sub_thgopts, 1);

	%bugs = (%bugs, map { $_ => 1 } bugs_from_thing($tocache, $sub_thgopts));

	$tocache = sanitizething(shift);
    } while (defined $tocache);

    # remove old bugs from cache
    if (keys %oldbugs) {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	    or die "$progname: couldn't open DB file $timestampdb for writing: $!\n"
	    if ! tied %timestamp;
    }

    foreach my $bug (keys %oldbugs) {
	if (! $bugs{$bug}) {
	    deletecache($bug);
	}
    }

    untie %timestamp;

    # download bugs
    my $bugcount = 1;
    my $bugtotal = scalar keys %bugs;
    foreach my $bug (keys %bugs) {
	if (-f cachefile($bug, '') and $updatemode) {
	    print "Skipping $bug as requested ... $bugcount/$bugtotal\n"
		if !$quiet;
	    $bugcount++;
	    next;
	}
	download($bug, '', 1, 0, $bugcount, $bugtotal);
	sleep $opt_cachedelay;
	$bugcount++;
    }

    # revert options
    if (defined $sub_refreshmode) {
	$refreshmode = $sub_refreshmode;
    }
    if (defined $sub_updatemode) {
	$updatemode = $sub_updatemode;
    }
    if (defined $sub_cachemode) {
	$cachemode = $sub_cachemode;
    }
    $quiet = $sub_quiet;
    $includeresolved = $sub_includeresolved;
}

=item B<cleancache> I<package> | B<src:>I<package> | I<maintainer>

=item B<cleancache from:>I<submitter> | B<tag:>I<tag> | B<usertag:>I<tag> | I<number> | B<ALL>

Clean the cache for the specified I<package>, I<maintainer>, etc., as
described above for the B<bugs> command, or clean the entire cache if
B<ALL> is specified. This is useful if you are going to have permanent
network access or if the database has become corrupted for some
reason.  Note that for safety, this command does not default to the
value of B<DEBEMAIL> or B<EMAIL>.

=cut

sub bts_cleancache {
    prunecache();
    my $toclean=sanitizething(shift);
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
	or die "$progname: couldn't open DB file $timestampdb for writing: $!\n"
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

=item B<version>

Display version and copyright information.

=cut

sub bts_version {
    print <<"EOF";
$progname version $version
Copyright (C) 2001-2003 by Joey Hess <joeyh\@debian.org>.
Modifications Copyright (C) 2002-2004 by Julian Gilbey <jdg\@debian.org>.
Modifications Copyright (C) 2007 by Josh Triplett <josh\@freedesktop.org>.
It is licensed under the terms of the GPL, either version 2 of the
License, or (at your option) any later version.
EOF
}

=item B<help>

Display a short summary of commands, suspiciously similar to parts of this
man page.

=cut

# Other supporting subs

# This must be the last bts_* sub
sub bts_help {
    my $inlist = 0;
    my $insublist = 0;
    print <<"EOF";
Usage: $progname [options] command [args] [\#comment] [.|, command ... ]
Valid options are:
   -o, --offline          Do not attempt to connect to BTS for show/bug
                          commands: use cached copy
   --online, --no-offline Attempt to connect (default)
   -n, --no-action        Do not send emails but print them to standard output.
   --no-cache             Do not attempt to cache new versions of BTS
                          pages when performing show/bug commands
   --cache                Do attempt to cache new versions of BTS
                          pages when performing show/bug commands (default)
   --cache-mode={min|mbox|full}
                          How much to cache when we are caching: the sensible
                          bare minimum (default), the mbox as well, or
                          everything?
   --cache-delay=seconds  Time to sleep between each download when caching.
   -m, --mbox             With show or bugs, open a mailreader to read the mbox
                          version instead
   --mailreader=CMD       Run CMD to read an mbox; default is 'mutt -f %s'
                          (must contain %s, which is replaced by mbox name)
   --cc-addr=CC_EMAIL_ADDRESS
                          Send carbon copies to a list of users.
                          CC_EMAIL_ADDRESS should be a comma-separated list of
                          e-mail addresses.
   --use-default-cc       Send carbon copies to any addresses specified in the
                          configuration file BTS_DEFAULT_CC (default)
   --no-use-default-cc    Do not do so
   --sendmail=cmd         Sendmail command to use (default /usr/sbin/sendmail)
   --mutt                 Use mutt for sending of mails.
   --no-mutt              Do not do so (default)
   --smtp-host=host       SMTP host to use
   --smtp-username=user   } Credentials to use when connecting to an SMTP
   --smtp-password=pass   } server which requires authentication
   --smtp-helo=helo       HELO to use when connecting to the SMTP server;
                            (defaults to the content of /etc/mailname)
   --bts-server           The name of the debbugs server to use
                            (default bugs.debian.org)
   -f, --force-refresh    Reload all bug reports being cached, even unchanged
                          ones
   --no-force-refresh     Do not do so (default)
   --only-new             Download only new bugs when caching.  Do not check
                          for updates in bugs we already have.
   --include-resolved     Cache bugs marked as resolved (default)
   --no-include-resolved  Do not cache bugs marked as resolved
   --no-ack               Suppress BTS acknowledgment mails
   --ack                  Do not do so (default)
   -i, --interactive      Prompt for confirmation before sending e-mail
   --force-interactive    Same as --interactive, with the exception that an
                          editor is spawned before confirmation is requested
   --no-interactive       Do not do so (default)
   -q, --quiet            Only display information about newly cached pages.
                          If given twice, only display error messages.
   --no-conf, --noconf    Do not read devscripts config files;
                          must be the first option given
   -h, --help             Display this message
   -v, --version          Display version and copyright info

Default settings modified by devscripts configuration files:
$modified_conf_msg

Valid commands are:
EOF
    seek DATA, 0, 0;
    while (<DATA>) {
	$inlist = 1 if /^=over 4/;
	next unless $inlist;
	$insublist = 1 if /^=over [^4]/;
	$insublist = 0 if /^=back/;
	if (/^=item\sB<([^->].*)>/ and ! $insublist) {
	    if ($1 eq 'help') {
		last;
	    }
	    # Strip POD markup before displaying and ensure we don't wrap
	    # longer lines
	    my $parser = Pod::BTS->new(width => 100);
	    $parser->no_whining(1);
	    $parser->output_fh(\*STDOUT);
	    $parser->parse_string_document($_);
	}
    }
}

# Strips any leading # or Bug# and trailing : from a thing if what's left is
# a pure positive number;
# also RC is a synonym for release-critical/other/all.html
sub sanitizething {
    my $bug = $_[0];
    defined $bug or return undef;

    return 'release-critical/other/all.html' if $bug eq 'RC';
    return 'release-critical/index.html' if $bug eq 'release-critical';
    $bug =~ s/^(?:(?:Bug)?\#)?(\d+):?$/$1/;
    return $bug;
}

# Perform basic validation of an argument which should be an email address,
# handling ! if allowed
sub checkemail {
    my $email=$_[0] or return;
    my $allowbang=$_[1];

    if ($email !~ /\@/ && (!$allowbang || $email ne '!')) {
	return;
    }

    return $email;
}

# Validate a bug number. Strips out extraneous leading junk, allowing
# for things like "#74041" and "Bug#94921"
sub checkbug {
    my $bug=$_[0] or return "";
    my $quiet=$_[1] || 0;  # used when we don't want warnings from checkbug

    if ($bug eq 'it') {
	if (not defined $it) {
	    die "$progname: You specified 'it', but no previous bug number referenced!\n";
	}
    } else {
	$bug=~s/^(?:(?:bug)?\#)?(-?\d+):?$/$1/i;
	if (! exists $clonedbugs{$bug} &&
	   (! length $bug || $bug !~ /^[0-9]+$/)) {
	    warn "\"$_[0]\" does not look like a bug number\n" unless $quiet;
	    return "";
	}

	# Valid, now set $it to this so that we can refer to it by 'it' later
	$it = $bug;
    }

    return $it;
}

# Stores up some extra information for a mail to the bts.
sub mailbts {
    if ($subject eq '') {
	$subject = $_[0];
    }
    elsif (length($subject) + length($_[0]) < 100) {
	$subject .= ", $_[0]" if length($_[0]);
    }
    elsif ($subject !~ / ...$/) {
	$subject .= " ...";
    }
    $body .= "$comment[$index]\n" if $comment[$index];
    $body .= "$_[1]\n";
}

# Extract an array of email addresses from a string
sub extract_addresses {
    my $s = shift;
    my @addresses;

    # Original regular expression from git-send-email, slightly modified
    while ($s =~ /([^,<>"\s\@]+\@[^.,<>"\s@]+(?:\.[^.,<>"\s\@]+)+)(.*)/) {
	push @addresses, $1;
	$s = $2;
    }
    return @addresses;
}

# Send one full mail message using the smtphost or sendmail.
sub send_mail {
    my ($from, $to, $cc, $subject, $body) = @_;

    my @fromaddresses = extract_addresses($from);
    my $fromaddress = $fromaddresses[0];
    # Message-ID algorithm from git-send-email
    my $msgid = sprintf("%s-%s", time(), int(rand(4200)))."-bts-$fromaddress";
    my $date = strftime "%a, %d %b %Y %T %z", localtime;

    my $message = fold_from_header("From: $from") . "\n";
    $message   .= "To: $to\n" if length $to;
    $message   .= "Cc: $cc\n" if length $cc;
    $message   .= "X-Debbugs-No-Ack: Yes\n" if $requestack==0;
    $message   .= "Subject: $subject\n"
               .  "Date: $date\n"
               .  "User-Agent: devscripts bts/$version$toolname\n"
               .  "Message-ID: <$msgid>\n"
               .  "\n";

    $body = addfooter($body);
    ($message, $body) = confirmmail($message, $body);

    return if not defined $body;

    $message .= "$body\n";
    if ($noaction) {
	print "$message\n";
    }
    elsif ($use_mutt) {
	my ($fh,$filename) = tempfile("btsXXXXXX",
				       SUFFIX => ".mail",
				       DIR => File::Spec->tmpdir,
				       UNLINK => 1);
	open (MAILOUT, ">&", $fh)
	    or die "$progname: writing to temporary file: $!\n";

	print MAILOUT $message;

	my $mailcmd = $muttcmd;
	$mailcmd =~ s/\%([%s])/$1 eq '%' ? '%' : $filename/eg;

	exec($mailcmd) or die "$progname: unable to start mailclient: $!";
    }
    elsif (length $smtphost) {
	my $smtp;

	if ($smtphost =~ m%^(?:(?:ssmtp|smtps)://)(.*)$%) {
	    my ($host, $port) = split(/:/, $1);
	    $port ||= '465';

	    if (have_smtp_ssl) {
		$smtp = Net::SMTP::SSL->new($host, Port => $port,
		    Hello => $smtphelo) or die "$progname: failed to open SMTPS connection to $smtphost\n($@)\n";
	    } else {
		die "$progname: Unable to establish SMTPS connection: $smtp_ssl_broken\n";
	    }
	} else {
	    my ($host, $port) = split(/:/, $smtphost);
	    $port ||= '25';

	    $smtp = Net::SMTP->new($host, Port => $port, Hello => $smtphelo)
		or die "$progname: failed to open SMTP connection to $smtphost\n($@)\n";
	}
	if ($smtpuser) {
	    if (have_authen_sasl) {
		$smtppass = getpass() if not $smtppass;
		$smtp->auth($smtpuser, $smtppass)
		    or die "$progname: failed to authenticate to $smtphost\n($@)\n";
	    } else {
		die "$progname: failed to authenticate to $smtphost: $authen_sasl_broken\n";
	    }
	}
	$smtp->mail($fromaddress)
	    or die "$progname: failed to set SMTP from address $fromaddress\n($@)\n";
	my @addresses = extract_addresses($to);
	push @addresses, extract_addresses($cc);
	foreach my $address (@addresses) {
	    $smtp->recipient($address)
	        or die "$progname: failed to set SMTP recipient $address\n($@)\n";
	}
	$smtp->data($message)
	    or die "$progname: failed to send message as SMTP DATA\n($@)\n";
	$smtp->quit
	    or die "$progname: failed to quit SMTP connection\n($@)\n";
    }
    else {
	my $pid = open(MAIL, "|-");
	if (! defined $pid) {
	    die "$progname: Couldn't fork: $!\n";
	}
	$SIG{'PIPE'} = sub { die "$progname: pipe for $sendmailcmd broke\n"; };
	if ($pid) {
	    # parent
	    print MAIL $message;
	    close MAIL or die "$progname: $sendmailcmd error: $!\n";
	}
	else {
	    # child
	    if ($debug) {
		exec("/bin/cat")
		    or die "$progname: error running cat: $!\n";
	    } else {
		my @mailcmd = split ' ', $sendmailcmd;
		push @mailcmd, "-t" if $sendmailcmd =~ /$sendmail_t/;
		exec @mailcmd
		    or die "$progname: error running $sendmailcmd: $!\n";
	    }
	}
    }
}

sub generate_packages_cc {
    my @ccs;
    if (keys %ccpackages && $packagesserver) {
	push @ccs, map { "$_\@$packagesserver" } sort keys %ccpackages;
    }
    if (keys %ccsubmitters && $btsserver) {
	push @ccs, map { "$_\@$btsserver" } sort keys %ccsubmitters;
    }
    return join(', ', @ccs);
}

# Sends all cached mail to the bts (duh).
sub mailbtsall {
    my $subject=shift;
    my $body=shift;

    my $charset = `locale charmap`;
    chomp $charset;
    $charset =~ s/^ANSI_X3\.4-19(68|86)$/US-ASCII/;
    $subject = MIME_encode_mimewords($subject, 'Charset' => $charset);

    if ($forceinteractive) {
	$ccemail .= ", " if length $ccemail;
	$ccemail .= generate_packages_cc();
    }
    if ($ccsecurity) {
	my $comma = "";
	if ($ccemail) {
	    $comma = ", ";
	}
	$ccemail = "$ccemail$comma$ccsecurity";
    }
    if ($ENV{'DEBEMAIL'} || $ENV{'EMAIL'}) {
	# We need to fake the From: line
	my ($email, $name);
	if (exists $ENV{'DEBFULLNAME'}) { $name = $ENV{'DEBFULLNAME'}; }
	if (exists $ENV{'DEBEMAIL'}) {
	    $email = $ENV{'DEBEMAIL'};
	    if ($email =~ /^(.*?)\s+<(.*)>\s*$/) {
		$name ||= $1;
		$email = $2;
	    }
	}
	if (exists $ENV{'EMAIL'}) {
	    if ($ENV{'EMAIL'} =~ /^(.*?)\s+<(.*)>\s*$/) {
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
	$from = MIME_encode_mimewords($from, 'Charset' => $charset);

	send_mail($from, $btsemail, $ccemail, $subject, $body);
    }
    else {  # No DEBEMAIL
	my $header = "";

	$header    = "To: $btsemail\n";
	$header   .= "Cc: $ccemail\n" if length $ccemail;
	$header   .= "X-Debbugs-No-Ack: Yes\n" if $requestack==0;
	$header   .= "Subject: $subject\n"
		  .  "User-Agent: devscripts bts/$version$toolname\n"
		  .  "\n";

	$body = addfooter($body);
	($header, $body) = confirmmail($header, $body);

	return if not defined $body;

	if ($noaction) {
	    print "$header$body\n";
	    return;
	}

	my $pid = open(MAIL, "|-");
	if (! defined $pid) {
	    die "$progname: Couldn't fork: $!\n";
	}
	$SIG{'PIPE'} = sub { die "$progname: pipe for $sendmailcmd broke\n"; };
	if ($pid) {
	    # parent
	    print MAIL $header;
	    print MAIL $body;
	    close MAIL or die "$progname: $sendmailcmd: $!\n";
	}
	else {
	    # child
	    if ($debug) {
		exec("/bin/cat")
		    or die "$progname: error running cat: $!\n";
	    } else {
		my @mailcmd = split ' ', $sendmailcmd;
		push @mailcmd, "-t" if $sendmailcmd =~ /$sendmail_t/;
		exec @mailcmd
		    or die "$progname: error running $sendmailcmd: $!\n";
	    }
	}
    }
}

sub confirmmail {
    my ($header, $body) = @_;

    return ($header, $body) if $noaction;

    $body = edit($body) if $forceinteractive;
    my $setHeader = 0;
    if ($interactive) {
	while(1) {
	    print "\n", $header, "\n", $body, "\n---\n";
	    print "OK to send? [Y/n/e] ";
	    $_ = <STDIN>;
	    if (/^n/i) {
		$body = undef;
		last;
	    } elsif (/^(y|$)/i) {
		last;
	    } elsif (/^e/i) {
		# Since the user has chosen to edit the message, we go ahead
		# and add the $ccpackages Ccs (if they haven't already been
		# added due to $forceinteractive).
		if (!$forceinteractive && !$setHeader) {
		    $setHeader = 1;
		    my $ccs = generate_packages_cc();
		    if ($header =~ m/^Cc: (.*?)$/m) {
			$ccs = "$1, $ccs";
			$header =~ s/^Cc: .*?$/Cc: $ccs/m;
		    }
		    else {
			$header =~ s/^(To: .*?)$/$1\nCc: $ccs/m;
		    }
		}
		$body = edit($body);
	    }
	}
    }

    return ($header, $body);
}

sub addfooter() {
    my $body = shift;

    $body .= "thanks\n";
    if ($forceinteractive) {
	if (-r $ENV{'HOME'} . "/.signature") {
	    if (open SIG, "<", $ENV{'HOME'} . "/.signature") {
		$body .= "-- \n";
		while(<SIG>) {
		    $body .= $_;
		}
		close SIG;
	    }
	}
    }

    return $body;
}

sub getpass() {
    system "stty -echo cbreak </dev/tty";
    die "$progname: error disabling stty echo\n" if $?;
    print "\a${smtpuser}";
    print "\@$smtphost" if $smtpuser !~ /\@/;
    print "'s SMTP password: ";
    $_ = <STDIN>;
    chomp;
    print "\n";
    system "stty echo -cbreak </dev/tty";
    die "$progname: error enabling stty echo\n" if $?;
    return $_;
}

sub extractemail() {
    my $thing=shift or die "$progname: extract e-mail from what?\n";

    if ($thing =~ /^(.*?)\s+<(.*)>\s*$/) {
	$thing = $2;
    }

    return $thing;
}

# A simplified version of mailbtsall which sends one message only to
# a specified address using the specified email From: header
sub mailto {
    my ($subject, $body, $to, $from) = @_;

    if (defined($from) || $noaction) {
	send_mail($from, $to, '', $subject, $body);
    }
    else {  # No $from
	unless (system("command -v mailx >/dev/null 2>&1") == 0) {
	    die "$progname: You need to either specify an email address (say using DEBEMAIL)\nor have the bsd-mailx package (or another package providing mailx) installed\nto send mail!\n";
	}
	my $pid = open(MAIL, "|-");
	if (! defined $pid) {
	    die "$progname: Couldn't fork: $!\n";
	}
	$SIG{'PIPE'} = sub { die "$progname: pipe for mailx broke\n"; };
	if ($pid) {
	    # parent
	    print MAIL $body;
	    close MAIL or die "$progname: mailx: $!\n";
	}
	else {
	    # child
	    if ($debug) {
		exec("/bin/cat")
		    or die "$progname: error running cat: $!\n";
	    } else {
		exec("mailx", "-s", $subject, $to)
		    or die "$progname: error running mailx: $!\n";
	    }
	}
    }
}

# The following routines are taken from a patched version of MIME::Words
# posted at http://mail.nl.linux.org/linux-utf8/2002-01/msg00242.html
# by Richard =?utf-8?B?xIxlcGFz?= (Chepas) <rch@richard.eu.org>

sub MIME_encode_B {
    my $str = shift;
    require MIME::Base64;
    MIME::Base64::encode_base64($str, '');
}

sub MIME_encode_Q {
    my $str = shift;
    $str =~ s{([_\?\=\015\012\t $NONPRINT])}{$1 eq ' ' ? '_' : sprintf("=%02X", ord($1))}eog;  # RFC-2047, Q rule 3
    $str;
}

sub MIME_encode_mimeword {
    my $word = shift;
    my $encoding = uc(shift || 'Q');
    my $charset  = uc(shift || 'ISO-8859-1');
    my $encfunc  = (($encoding eq 'Q') ? \&MIME_encode_Q : \&MIME_encode_B);
    "=?$charset?$encoding?" . &$encfunc($word) . "?=";
}

sub MIME_encode_mimewords {
    my ($rawstr, %params) = @_;
    # check if we have something to encode
    $rawstr !~ /[$NONPRINT]/o and $rawstr !~ /\=\?/o and return $rawstr;
    my $charset  = $params{Charset} || 'ISO-8859-1';
    # if there is 1/3 unsafe bytes, the Q encoded string will be 1.66 times
    # longer and B encoded string will be 1.33 times longer than original one
    my $encoding = lc($params{Encoding} ||
       (length($rawstr) > 3*($rawstr =~ tr/[\x00-\x1F\x7F-\xFF]//) ? 'q':'b'));

    # Encode any "words" with unsafe bytes.
    my ($last_token, $last_word_encoded, $token) = ('', 0);
    $rawstr =~ s{([^\015\012\t ]+|[\015\012\t ]+)}{     # get next "word"
	$token = $1;
	if ($token =~ /[\015\012\t ]+/) {  # white-space
	    $last_token = $token;
	} else {
	    if ($token !~ /[$NONPRINT]/o and $token !~ /\=\?/o) {
		# no unsafe bytes, leave as it is
		$last_word_encoded = 0;
		$last_token = $token;
	    } else {
		# has unsafe bytes, encode to one or more encoded words
		# white-space between two encoded words is skipped on
		# decoding, so we should encode space in that case
		$_ = $last_token =~ /[\015\012\t ]+/ && $last_word_encoded ? $last_token.$token : $token;
		# We limit such words to about 18 bytes, to guarantee that the
		# worst-case encoding give us no more than 54 + ~10 < 75 bytes
		s{(.{1,15}[\x80-\xBF]{0,4})}{
		    # don't split multibyte characters - this regexp should
		    # work for UTF-8 characters
		    MIME_encode_mimeword($1, $encoding, $charset).' ';
		}sxeg;
		$_ = substr($_, 0, -1); # remove trailing space
		$last_word_encoded = 1;
		$last_token = $token;
		$_;
	    }
	}
    }sxeg;
    $rawstr;
}

# This is a stripped-down version of Mail::Header::_fold_line, but is
# not as general-purpose as the original, so take care if using it elsewhere!
# The heuristics are changed to prevent splitting in the middle of an
# encoded word; we should not have any commas or semicolons!
sub fold_from_header {
    my $header = shift;
    chomp $header;  # We assume there wasn't a newline anyhow

    my $maxlen = 76;
    my $max = int($maxlen - 5);         # 4 for leading spcs + 1 for [\,\;]

    if(length($header) > $maxlen) {
	# Split the line up:
	# first split at a whitespace,
	# else we are looking at a single word and we won't try to split
	# it, even though we really ought to
	# But this could only happen if someone deliberately uses a really
	# long name with no spaces in it.
	my @x;

	push @x, $1
	    while($header =~ s/^\s*
		  ([^\"]{1,$max}\s
		   |[^\s\"]*(?:\"[^\"]*\"[ \t]?[^\s\"]*)+\s
		   |[^\s\"]+\s
		   )
		  //x);
	push @x, $header;
	map { s/\s*$// } @x;
	if (@x > 1 and length($x[-1]) + length($x[-2]) < $max) {
	    $x[-2] .= " $x[-1]";
	    pop @x;
	}
	$x[0] =~ s/^\s*//;
	$header = join("\n  ", @x);
    }

    $header =~ s/^(\S+)\n\s*(?=\S)/$1 /so;
    return $header;
}

##########  Browsing and caching subroutines

# Mirrors a given thing; if the online version is no newer than our
# cached version, then returns an empty string, otherwise returns the
# live thing as a (non-empty) string
sub download {
    my $thing=shift;
    my $thgopts=shift ||'';
    my $manual=shift;  # true="bts cache", false="bts show/bug"
    my $mboxing=shift;  # true="bts --mbox show/bugs", and only if $manual=0
    my $bug_current=shift;  # current bug being downloaded if caching
    my $bug_total=shift;    # total things to download if caching
    my $timestamp = 0;
    my $versionstamp = '';
    my $url;

    my $oldcwd = getcwd;

    # What URL are we to download?
    if ($thgopts ne '') {
	# have to be intelligent here :/
	$url = thing_to_url($thing) . $thgopts;
    } else {
	# let the BTS be intelligent
	$url = "$btsurl$thing";
    }

    if (! -d $cachedir) {
	die "$progname: download() called but no cachedir!\n";
    }

    chdir($cachedir) || die "$progname: chdir $cachedir: $!\n";

    if (-f cachefile($thing, $thgopts)) {
	($timestamp, $versionstamp) = get_timestamp($thing, $thgopts);
	$timestamp ||= 0;
	$versionstamp ||= 0;
	# And ensure we preserve any manual setting
	if (is_manual($timestamp)) { $manual = 1; }
    }

    # do we actually have to do more than we might have thought?
    # yes, if we've caching with --cache-mode=mbox or full and the bug had
    # previously been cached in a less thorough format
    my $forcedownload = 0;
    if ($thing =~ /^\d+$/ and ! $refreshmode) {
	if (old_cache_format_version($versionstamp)) {
	    $forcedownload = 1;
	} elsif ($cachemode ne 'min' or $mboxing) {
	    if (! -r mboxfile($thing)) {
		$forcedownload = 1;
	    } elsif ($cachemode eq 'full' and -d $thing) {
		opendir DIR, $thing or die "$progname: opendir $cachedir/$thing: $!\n";
		my @htmlfiles = grep { /^\d+\.html$/ } readdir(DIR);
		closedir DIR;
		$forcedownload = 1 unless @htmlfiles;
	    }
	}
    }

    print "Downloading $url ... "
	if ! $quiet and $manual and $thing ne "css/bugs.css";
    IO::Handle::flush(\*STDOUT);
    my ($ret, $msg, $livepage, $contenttype) = bts_mirror($url, $timestamp, $forcedownload);
    my $charset = $contenttype || '';
    if ($charset =~ m/charset=(.*?)(;|\Z)/) {
	$charset = $1;
    } else {
	$charset = "";
    }
    if ($ret == MIRROR_UP_TO_DATE) {
	# we have an up-to-date version already, nothing to do
	# and $timestamp is guaranteed to be well-defined
	if (is_automatic($timestamp) and $manual) {
	    set_timestamp($thing, $thgopts, make_manual($timestamp), $versionstamp);
	}

	if (! $quiet and $manual and $thing ne "css/bugs.css") {
	    print "(cache already up-to-date) ";
	    print "$bug_current/$bug_total" if $bug_total;
	    print "\n";
	}
	chdir $oldcwd or die "$progname: chdir $oldcwd failed: $!\n";
	return "";
    }
    elsif ($ret == MIRROR_DOWNLOADED) {
	# Note the current timestamp, but don't record it until
	# we've successfully stashed the data away
	$timestamp = time;

	die "$progname: empty page downloaded\n" unless length $livepage;

	my $bug2filename = { };

	if ($thing =~ /^\d+$/) {
	    # we've downloaded an individual bug, and it's been updated,
	    # so we need to also download all the attachments
	    $bug2filename =
		download_attachments($thing, $livepage, $timestamp);
	}

	my $data = $livepage;  # work on a copy, not the original
	my $cachefile=cachefile($thing,$thgopts);
	open (OUT_CACHE, ">$cachefile") or die "$progname: open $cachefile: $!\n";

	$data = mangle_cache_file($data, $thing, $bug2filename, $timestamp, $charset ? $contenttype : '');
	print OUT_CACHE $data;
	close OUT_CACHE or die "$progname: problems writing to $cachefile: $!\n";

	set_timestamp($thing, $thgopts,
	    $manual ? make_manual($timestamp) : make_automatic($timestamp),
	    $version);

	if (! $quiet and $manual and $thing ne "css/bugs.css") {
	    print "(cached new version) ";
	    print "$bug_current/$bug_total" if $bug_total;
	    print "\n";
	} elsif ($quiet == 1 and $manual and $thing ne "css/bugs.css") {
	    print "Downloading $url ... (cached new version)\n";
	} elsif ($quiet > 1) {
	    # do nothing
	}

	# Add a <base> tag to the live page content, so that relative urls
	# in it work when it's passed to the web browser.
	my $base=$url;
	$base=~s%/[^/]*$%%;
	$livepage=~s%<head>%<head><base href="$base">%i;

	chdir $oldcwd or die "$progname: chdir $oldcwd failed: $!\n";
	return $livepage;
    } else {
	die "$progname: couldn't download $url:\n$msg\n";
    }
}

sub download_attachments {
    my ($thing, $toppage, $timestamp) = @_;
    my %bug2filename;

    # We search for appropriate strings in the top page, and save the
    # attachments in files with names as follows:
    # - if the attachment specifies a filename, save as bug#/msg#-att#/filename
    # - if not, save as bug#/msg#-att# with suffix .txt if plain/text and
    #   .html if plain/html, no suffix otherwise (too much like hard work!)
    # Since messages are never modified retrospectively, we don't download
    # attachments which have already been downloaded

    # Yuck, yuck, yuck.  This regex splits the $data string at every
    # occurrence of either "[<a " or plain "<a ", preserving any "[".
    my @data = split /(?:(?=\[<[Aa]\s)|(?<!\[)(?=<[Aa]\s))/, $toppage;
    foreach (@data) {
	next unless m%<a(?: class=\".*?\")? href="(?:/cgi-bin/)?((bugreport\.cgi[^\"]+)">|(version\.cgi[^\"]+)"><img[^>]* src="(?:/cgi-bin/)?([^\"]+)">|(version\.cgi[^\"]+)">)%i;

	my $ref = $5;
	$ref = $4 if not defined $ref;
	$ref = $2 if not defined $ref;

	my ($msg, $filename) = href_to_filename($_);

	next unless defined $msg;

	if ($msg =~ /^\d+-\d+$/) {
	    # it's an attachment, must download

	    if (-f dirname($filename)) {
		warn "$progname: found file where directory expected; using existing file (" . dirname($filename) . ")\n";
		$bug2filename{$msg} = dirname($filename);
	    } else {
	        $bug2filename{$msg} = $filename;
	    }

	    # already downloaded?
	    next if -f $bug2filename{$msg} and not $refreshmode;
	}
	elsif ($cachemode eq 'full' and $msg =~ /^\d+$/) {
	    $bug2filename{$msg} = $filename;
	    # already downloaded?
	    next if -f $bug2filename{$msg} and not $refreshmode;
	}
	elsif ($cachemode eq 'full' and $msg =~ /^\d+-mbox$/) {
	    $bug2filename{$msg} = $filename;
	    # already downloaded?
	    next if -f $bug2filename{$msg} and not $refreshmode;
	}
	elsif (($cachemode eq 'full' or $cachemode eq 'mbox' or $mboxmode) and
	       $msg eq 'mbox') {
	    $bug2filename{$msg} = $filename;
	    # This always needs refreshing, as it does change as the bug
	    # changes
	}
	elsif ($cachemode eq 'full' and $msg =~ /^(status|raw)mbox$/) {
	    $bug2filename{$msg} = $filename;
	    # Always need refreshing, as they could change each time the
	    # bug does
	}
	elsif ($cachemode eq 'full' and $msg eq 'versions') {
	    $bug2filename{$msg} = $filename;
	    # Ensure we always download the full size images for
	    # version graphs, without the informational links
	    $ref =~ s%;info=1%;info=0%;
	    $ref =~ s%(;|\?)(height|width)=\d+%$1%g;
	    # already downloaded?
	    next if -f $bug2filename{$msg} and not $refreshmode;
	}

	next unless exists $bug2filename{$msg};

	warn "bts debug: downloading $btscgiurl$ref\n" if $debug;
	init_agent() unless $ua;  # shouldn't be necessary, but do just in case
	my $request = HTTP::Request->new('GET', $btscgiurl . $ref);
	my $response = $ua->request($request);
	if ($response->is_success) {
	    my $content_length = defined $response->content ?
		length($response->content) : 0;
	    if ($content_length == 0) {
		warn "$progname: failed to download $ref, skipping\n";
		next;
	    }

	    my $data = $response->content;

	    if ($msg =~ /^\d+$/) {
		# we're dealing with a boring message, and so we must be
		# in 'full' mode
		$data =~ s%<HEAD>%<HEAD><BASE href="../">%;
		$data = mangle_cache_file($data, $thing, 'full', $timestamp);
	    }
	    mkpath(dirname $bug2filename{$msg});
	    open OUT_CACHE, ">$bug2filename{$msg}"
	        or die "$progname: open cache $bug2filename{$msg}\n";
	    print OUT_CACHE $data;
	    close OUT_CACHE;
	} else {
	    warn "$progname: failed to download $ref, skipping\n";
	    next;
	}
    }

    return \%bug2filename;
}


# Download the mailbox for a given bug, return mbox ($fh, filename) on success,
# die on failure
sub download_mbox {
    my $thing = shift;
    my $temp = shift;  # do we wish to store it in cache or in a temp file?
    my $mboxfile = mboxfile($thing);

    die "$progname: trying to download mbox for illegal bug number $thing.\n"
	unless $mboxfile;

    if (! have_lwp()) {
	die "$progname: couldn't run bts --mbox: $lwp_broken\n";
    }
    init_agent() unless $ua;

    my $request = HTTP::Request->new('GET', $btscgiurl . "bugreport.cgi?bug=$thing;mboxmaint=yes");
    my $response = $ua->request($request);
    if ($response->is_success) {
	my $content_length = defined $response->content ?
	    length($response->content) : 0;
	if ($content_length == 0) {
	    die "$progname: failed to download mbox.\n";
	}

	my ($fh, $filename);
	if ($temp) {
	    ($fh,$filename) = tempfile("btsXXXXXX",
				       SUFFIX => ".mbox",
				       DIR => File::Spec->tmpdir,
				       UNLINK => 1);
	    # Use filehandle for security
	    open (OUT_MBOX, ">&", $fh)
		or die "$progname: writing to temporary file: $!\n";
	} else {
	    $filename = $mboxfile;
	    open (OUT_MBOX, ">$mboxfile")
		or die "$progname: writing to mbox file $mboxfile: $!\n";
	}
	print OUT_MBOX $response->content;
	close OUT_MBOX;

	return ($fh, $filename);
    } else {
	die "$progname: failed to download mbox.\n";
    }
}


# Mangle downloaded file to work in the local cache, so
# selectively modify the links
sub mangle_cache_file {
    my ($data, $thing, $bug2filename, $timestamp, $ctype) = @_;
    my $fullmode = ! ref $bug2filename;

    # Undo unnecessary '+' encoding in URLs
    while ($data =~ s!(href=\"[^\"]*)\%2b!$1+!ig) { };
    my $time=localtime(abs($timestamp));
    $data =~ s%(<BODY.*>)%$1<p><em>[Locally cached on $time by devscripts version $version]</em></p>%i;
    $data =~ s%href="/css/bugs.css"%href="bugs.css"%;
    if ($ctype) {
	$data =~ s%(<HEAD.*>)%$1<META HTTP-EQUIV="Content-Type" CONTENT="$ctype">%i;
    }

    my @data;
    # We have to distinguish between release-critical pages and normal BTS
    # pages as they have a different structure
    if ($thing =~ /^release-critical/) {
	@data = split /(?=<[Aa])/, $data;
	foreach (@data) {
	    s%<a href="(http://$btsserver/cgi-bin/bugreport\.cgi.*bug=(\d+)[^\"]*)">(.+?)</a>%<a href="$2.html">$3</a> (<a href="$1">online</a>)%i;
	    s%<a href="(http://$btsserver/cgi-bin/pkgreport\.cgi.*pkg=([^\"&;]+)[^\"]*)">(.+?)</a>%<a href="$2.html">$3</a> (<a href="$1">online</a>)%i;
	    # References to other bug lists on bugs.d.o/release-critical
	    if (m%<a href="((?:debian|other)[-a-z/]+\.html)"%i) {
		my $ref = 'release-critical/'.$1;
		$ref =~ s%/%_%g;
		s%<a href="((?:debian|other)[-a-z/]+\.html)">(.+?)</a>%<a href="$ref">$2</a> (<a href="${btsurl}release-critical/$1">online</a>)%i;
	    }
	    # Maintainer email address - YUCK!!
	    s%<a href="(http://$btsserver/([^\"?]*\@[^\"?]*))">(.+?)</a>&gt;%<a href="$2.html">$3</a>&gt; (<a href="$1">online</a>)%i;
	    # Graph - we don't download
	    s%<img src="graph.png" alt="Graph of RC bugs">%<img src="${btsurl}release-critical/graph.png" alt="Graph of RC bugs (online)">%
	}
    } else {
	# Yuck, yuck, yuck.  This regex splits the $data string at every
	# occurrence of either "[<a " or plain "<a ", preserving any "[".
	@data = split /(?:(?=\[<[Aa]\s)|(?<!\[)(?=<[Aa]\s))/, $data;
	foreach (@data) {
	    if (m%<a(?: class=\".*?\")? href=\"(?:/cgi-bin/)?bugreport\.cgi[^\?]*\?.*?;?bug=(\d+)%i) {
		my $bug = $1;
		my ($msg, $filename) = href_to_filename($_);
		if ($bug eq $thing and defined $msg) {
		    if ($fullmode or
			(! $fullmode and exists $$bug2filename{$msg})) {
			s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(bugreport\.cgi[^\"]*)">(.+?)</a>%<a$1 href="$filename">$3</a> (<a$1 href="$btscgiurl$2">online</a>)%i;
		    } else {
			s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(bugreport\.cgi[^\"]*)">(.+?)</a>%$3 (<a$1 href="$btscgiurl$2">online</a>)%i;
		    }
		} else {
		    s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(bugreport\.cgi[^\?]*\?.*?bug=(\d+))"(.*?)>(.+?)</a>%<a$1 href="$3.html"$4>$5</a> (<a$1 href="$btscgiurl$2">online</a>)%i;
		}
	    } else {
		s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(pkgreport\.cgi\?(?:pkg|maint)=([^\"&;]+)[^\"]*)">(.+?)</a>%<a$1 href="$3.html">$4</a> (<a$1 href="$btscgiurl$2">online</a>)%gi;
		s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(pkgreport\.cgi\?src=([^\"&;]+)[^\"]*)">(.+?)</a>%<a$1 href="src_$3.html">$4</a> (<a$1 href="$btscgiurl$2">online</a>)%i;
		s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(pkgreport\.cgi\?submitter=([^\"&;]+)[^\"]*)">(.+?)</a>%<a$1 href="from_$3.html">$4</a> (<a$1 href="$btscgiurl$2">online</a>)%i;
		s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(pkgreport\.cgi\?.*?;?archive=([^\"&;]+);submitter=([^\"&;]+)[^\"]*)">(.+?)</a>%<a$1 href="from_$4_3Barchive_3D$3.html">$5</a> (<a$1 href="$btscgiurl$2">online</a>)%i;
		s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(pkgreport\.cgi\?.*?;?package=([^\"&;]+)[^\"]*)">(.+?)</a>%<a$1 href="$3.html">$4</a> (<a$1 href="$btscgiurl$2">online</a>)%gi;
		s%<a((?: class=\".*?\")?) href="(?:/cgi-bin/)?(bugspam\.cgi[^\"]+)">%<a$1 href="$btscgiurl$2">%i;
		s%<a((?: class=\".*?\")?) href="/([0-9]+?)">(.+?)</a>%<a$1 href="$2.html">$3</a> (<a$1 href="$btsurl$2">online</a>)%i;

		# Version graphs
		# - remove 'package=' and move the package to the front
		s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?)([^\"]+)package=([^;\"]+)([^\"]+\"|\")>%$1$3;$2$4>%gi;
		# - replace 'found=' with '.f.' and 'fixed=' with '.fx.'
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?)(.*?;)found=([^\"]+)\">%$1$2.f.$3">%i;
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?)(.*?;)fixed=([^\"]+)\">%$1$2.fx.$3">%i;
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?found=)([^\"]+)\">%$1.f.$2">%i;
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?fixed=)([^\"]+)\">%$1.fx.$2">%i;
		# - replace '%2F' or '%2C' (a URL-encoded / or ,) with '.'
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?[^\%]*)\%2[FC]([^\"]+)\">%$1.$2">%gi;
		# - display collapsed graph images at 25%
		s%(<img[^>]* src=\"[^\"]+);collapse=1([^\"]+)\">%$1$2.co" width="25\%" height="25\%">%gi;
		#   - and link to the collapsed graph
		s%(<a[^>]* href=\"[^\"]+);collapse=1([^\"]+)\">%$1$2.co">%gi;
		# - remove any other parameters
		1 while s%((?:<img[^>]* src|<a[^>]* href)=\"(?:/cgi-bin/)?version\.cgi\?[^\"]+);(?:\w+=\d+)([^>]+)\>%$1$2>%gi;
		# - remove any +s (encoded spaces)
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?[^\+]*)\+([^\"]+)\">%$1$2">%gi;
		# - remove trailing ";" and ";." from previous substitutions
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?[^\"]+);\.(.*?)>%$1.$2>%gi;
		1 while s%((?:<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?[^\"]+);\">%$1">%gi;
		# - final reference should be $package.$versions[.co].png
		s%(<img[^>]* src=\"|<a[^>]* href=\")(?:/cgi-bin/)?version\.cgi\?([^\"]+)(\"[^>]*)>%$1$2.png$3>%gi;
	    }
	}
    }

    return join("", @data);
}


# Removes a specified thing from the cache
sub deletecache {
    my $thing=shift;
    my $thgopts=shift || '';

    if (! -d $cachedir) {
	die "$progname: deletecache() called but no cachedir!\n";
    }

    delete_timestamp($thing,$thgopts);
    unlink cachefile($thing,$thgopts);
    if ($thing =~ /^\d+$/) {
	rmtree("$cachedir/$thing", 0, 1) if -d "$cachedir/$thing";
	unlink("$cachedir/$thing.mbox") if -f "$cachedir/$thing.mbox";
	unlink("$cachedir/$thing.status.mbox") if -f "$cachedir/$thing.status.mbox";
	unlink("$cachedir/$thing.raw.mbox") if -f "$cachedir/$thing.raw.mbox";
    }
}

# Given a thing, returns the filename for it in the cache.
sub cachefile {
    my $thing=shift;
    my $thgopts=shift || '';
    if ($thing eq '') { die "$progname: cachefile given empty argument\n"; }
    if ($thing =~ /bugs.css$/) { return $cachedir."bugs.css" }
    $thing =~ s/^src:/src_/;
    $thing =~ s/^from:/from_/;
    $thing =~ s/^tag:/tag_/;
    $thing =~ s/^usertag:/usertag_/;
    $thing =~ s%^release-critical/index\.html$%release-critical.html%;
    $thing =~ s%/%_%g;
    $thgopts =~ s/;/_3B/g;
    $thgopts =~ s/=/_3D/g;
    return $cachedir.$thing.$thgopts.($thing =~ /\.html$/ ? "" : ".html");
}

# Given a thing, returns the filename for its mbox in the cache.
sub mboxfile {
    my $thing=shift;
    return $thing =~ /^\d+$/ ? $cachedir.$thing.".mbox" : undef;
}

# Given a bug number, returns the dirname for it in the cache.
sub cachebugdir {
    my $thing=shift;
    if ($thing !~ /^\d+$/) { die "$progname: cachebugdir given faulty argument: $thing\n"; }
    return $cachedir.$thing;
}

# And the reverse: Given a filename in the cache, returns the corresponding
# "thing".
sub cachefile_to_thing {
    my $thing=basename(shift, '.html');
    my $thgopts='';
    $thing =~ s/^src_/src:/;
    $thing =~ s/^from_/from:/;
    $thing =~ s/^tag_/tag:/;
    $thing =~ s/^usertag_/usertag:/;
    $thing =~ s%^release-critical\.html$%release-critical/index\.html%;
    $thing =~ s%_%/%g;
    $thing =~ s/_3B/;/g;
    $thing =~ s/_3D/=/g;
    $thing =~ /^(.*?)((?:;.*)?)$/;
    ($thing, $thgopts) = ($1, $2);
    return ($thing, $thgopts);
}

# Given a thing, gives the official BTS cgi page for it
sub thing_to_url {
    my $thing = shift;
    my $thingurl;

    # have to be intelligent here :/
    if ($thing =~ /^\d+$/) {
	$thingurl = $btscgibugurl."?bug=".$thing;
    } elsif ($thing =~ /^from:/) {
	($thingurl = $thing) =~ s/^from:/submitter=/;
	$thingurl = $btscgipkgurl.'?'.$thingurl;
    } elsif ($thing =~ /^src:/) {
	($thingurl = $thing) =~ s/^src:/src=/;
	$thingurl = $btscgipkgurl.'?'.$thingurl;
    } elsif ($thing =~ /^tag:/) {
	($thingurl = $thing) =~ s/^tag:/tag=/;
	$thingurl = $btscgipkgurl.'?'.$thingurl;
    } elsif ($thing =~ /^usertag:/) {
	($thingurl = $thing) =~ s/^usertag:/tag=/;
	$thingurl = $btscgipkgurl.'?'.$thingurl;
    } elsif ($thing =~ m%^release-critical(\.html|/(index\.html)?)?$%) {
	$thingurl = $btsurl . 'release-critical/index.html';
    } elsif ($thing =~ m%^release-critical/%) {
	$thingurl = $btsurl . $thing;
    } elsif ($thing =~ /\@/) { # so presume it's a maint request
	$thingurl = $btscgipkgurl.'?maint='.$thing;
    } else { # it's a package, or had better be...
	$thingurl = $btscgipkgurl.'?pkg='.$thing;
    }

    return $thingurl;
}

# Given a thing, reads all links to bugs from the corresponding cache file
# if there is one, and returns a list of them.
sub bugs_from_thing {
    my $thing=shift;
    my $thgopts=shift || '';
    my $cachefile=cachefile($thing,$thgopts);

    if (-f $cachefile) {
	local $/;
	open (IN, $cachefile) || die "$progname: open $cachefile: $!\n";
	my $data=<IN>;
	close IN;

	return $data =~ m!href="(\d+)\.html"!g;
    } else {
	return ();
    }
}

# Given an <a href="bugreport.cgi?...>...</a> string, return a
# msg id and corresponding filename
sub href_to_filename {
    my $href = $_[0];
    my ($msg, $filename);

    if ($href =~ m%\[<a(?: class=\".*?\")? href="(?:/cgi-bin/)?bugreport\.cgi([^\?]*)\?([^\"]*);bug=(\d+)">.*?\(([^,]*), .*?\)\]%) {
	# this looks like an attachment; $4 should give the MIME-type
	my $urlfilename = $1;
	my $ref = $2;
	my $bug = $3;
	my $mimetype = $4;
	$ref =~ s/&(?:amp;)?/;/g;  # normalise all hrefs

	return undef unless $ref =~ /msg=(\d+);(filename=[^;]*;)?att=(\d+)/;
	$msg = "$1-$3";
	$urlfilename ||= "$2" if defined $2;
	$urlfilename ||= "";

	my $fileext = '';
	if ($urlfilename =~ m%^/%) {
	    $filename = basename($urlfilename);
	} elsif ($urlfilename =~ m%^filename=([^;]*?);%) {
	    $urlfilename = $1;
	    $filename = basename($urlfilename);
	} else {
	    $filename = '';
	    if ($mimetype eq 'text/plain') { $fileext = '.txt'; }
	    if ($mimetype eq 'text/html') { $fileext = '.html'; }
	}
	if (length ($filename)) {
	    $filename = "$bug/$msg/$filename";
	} else {
	    $filename = "$bug/$msg$fileext";
	}
    }
    elsif ($href =~ m%<a(?: class=\".*?\")? href="(?:/cgi-bin/)?bugreport\.cgi([^\?]*)\?([^"]*);?bug=(\d+)(.*?)".*?>%) {
	my $urlfilename = $1;
	my $ref = $2;
	my $bug = $3;
	$ref .= $4 if defined $4;
	$ref =~ s/&(?:amp;)?/;/g;  # normalise all hrefs
	$ref =~ s/;archive=(yes|no)\b//;
	$ref =~ s/%3D/=/g;

	if ($ref =~ /msg=(\d+);$/) {
	    $msg = $1;
	    $filename = "$bug/$1.html";
	}
	elsif ($ref =~ /msg=(\d+);mbox=yes;$/) {
	    $msg = "$1-mbox";
	    $filename = "$bug/$1.mbox";
	}
	elsif ($ref =~ /^mbox=yes;$/) {
	    $msg = 'rawmbox';
	    $filename = "$bug.raw.mbox";
	}
	elsif ($ref =~ /mboxstat(us)?=yes/) {
	    $msg = 'statusmbox';
	    $filename = "$bug.status.mbox";
	}
	elsif ($ref =~ /mboxmaint=yes/) {
	    $msg = 'mbox';
	    $filename = "$bug.mbox";
	}
	elsif ($ref eq '') {
	    return undef;
	}
	else {
	    $href =~ s/>.*/>/s;
	    warn "$progname: in href_to_filename: unrecognised BTS URL type: $href\n";
	    return undef;
	}
    }
    elsif ($href =~ m%<a[^>]* href=\"(?:/cgi-bin/)?version\.cgi([^>]+><img[^>]* src=\"(?:/cgi-bin/)?version\.cgi)?\?([^\"]+)\">%i) {
	my $refs = $2;
	$refs = $1 if not defined $refs;

	# Remove package= and make sure the package name is at the
	# start of the filename
	$refs =~ s/(.*?)package=(.*?)(;.*?|)$/$2;$1$3/;
	# Package versions
	$refs =~ s/;found=/.f./g;
	$refs =~ s/;fixed=/.fx./g;
	# Replace encoded "/" and "," characters with "."
	$refs =~ s/%2[FC]/./g;
	# Remove encoded spaces
	$refs =~ s/\+//g;
	# Is this a "collapsed" graph?
	$refs =~ s/;collapse=1(.*)/$1.co/;
	# Remove any other parameters
	$refs =~ s/(^|;)(\w+)=\d+//g;
	# and tidy up any remaining separators
	$refs =~ s/;//g;

	$msg = 'versions';
	$filename = "$refs.png";
    }
    else {
	return undef;
    }

    return ($msg, $filename);
}

# Browses a given thing, with preprocessed list of URL options such as
# ";opt1=val1;opt2=val2" with possible caching if there are no options
sub browse {
    prunecache();
    my $thing=shift;
    my $thgopts=shift || '';

    if ($thing eq '') {
	if ($thgopts ne '') {
	    die "$progname: you can only give options for a BTS page if you specify a bug/maint/... .\n";
	}
	runbrowser($btsurl);
	return;
    }

    my $hascache=-d $cachedir;
    my $cachefile=cachefile($thing,$thgopts);
    my $mboxfile=mboxfile($thing);
    if ($mboxmode and ! $mboxfile) {
	die "$progname: you can only request a mailbox for a single bug report.\n";
    }

    # Check that if we're requesting a tag, that it's a valid tag
    if (($thing.$thgopts) =~ /(?:^|;)(?:tag|include|exclude)[:=]([^;]*)/) {
	unless (exists $valid_tags{$1}) {
	    die "$progname: invalid tag requested: $1\nRecognised tag names are: " . join(" ", @valid_tags) . "\n";
	}
    }

    my $livedownload = 1;
    if ($offlinemode) {
	$livedownload = 0;
	if (! $hascache) {
	    die "$progname: Sorry, you are in offline mode and have no cache.\nRun \"bts cache\" or \"bts show\" to create one.\n";
	}
	elsif ((! $mboxmode and ! -r $cachefile) or
	       ($mboxmode and ! -r $mboxfile)) {
	    die "$progname: Sorry, you are in offline mode and that is not cached.\nUse \"bts [--cache-mode=...] cache\" to update the cache.\n";
	}
	if ($mboxmode) {
	    runmailreader($mboxfile);
	} else {
	    runbrowser("file://$cachefile");
	}
    }
    # else we're in online mode
    elsif ($caching && have_lwp() && $thing ne '') {
	if (! $hascache) {
	    if (! -d dirname($cachedir)) {
		unless (mkdir(dirname($cachedir))) {
		    warn "$progname: couldn't mkdir ".dirname($cachedir).": $!\n";
		    goto LIVE;
		}
	    }
	    unless (mkdir($cachedir)) {
		warn "$progname: couldn't mkdir $cachedir: $!\n";
		goto LIVE;
	    }
	}

	$livedownload = 0;
	my $live=download($thing, $thgopts, 0, $mboxmode);

	if ($mboxmode) {
	    runmailreader($mboxfile);
	} else {
	    if (length($live)) {
		my ($fh,$livefile) = tempfile("btsXXXXXX",
					      SUFFIX => ".html",
					      DIR => File::Spec->tmpdir,
					      UNLINK => 1);

		# Use filehandle for security
		open (OUT_LIVE, ">&", $fh)
		    or die "$progname: writing to temporary file: $!\n";
		# Correct relative urls to point to the bts.
		$live =~ s%\shref="(?:/cgi-bin/)?(\w+\.cgi)% href="$btscgiurl$1%g;
		print OUT_LIVE $live;
		# Some browsers don't like unseekable filehandles,
		# so use filename
		runbrowser("file://$livefile");
	    } else {
		runbrowser("file://$cachefile");
	    }
	}
    }

 LIVE: # we are not caching; just show it live
    if ($livedownload) {
	if ($mboxmode) {
	    # we appear not to be caching; OK, we'll download to a
	    # temporary file
	    warn "bts debug: downloading ${btscgiurl}bugreport.cgi?bug=$thing;mbox=yes\n" if $debug;
	    my ($fh, $fn) = download_mbox($thing, 1);
	    runmailreader($fn);
	} else {
	    if ($thgopts ne '') {
		my $thingurl = thing_to_url($thing);
		runbrowser($thingurl.$thgopts);
	    } else {
		# let the BTS be intelligent
		runbrowser($btsurl.$thing);
	    }
	}
    }
}

# Removes all files from the cache which were downloaded automatically
# and have not been accessed for more than 30 days.  We also only run
# this at most once per day for efficiency.

sub prunecache {
    return unless -d $cachedir;
    return if -f $prunestamp and -M _ < 1;

    my $oldcwd = getcwd;

    chdir($cachedir) || die "$progname: chdir $cachedir: $!\n";

    # remove the now-defunct live-download file
    unlink "live_download.html";

    opendir DIR, '.' or die "$progname: opendir $cachedir: $!\n";
    my @cachefiles = grep { ! /^\.\.?$/ } readdir(DIR);
    closedir DIR;

    # Are there any unexpected files lying around?
    my @known_files = map { basename($_) } ($timestampdb, $timestampdb.".lock",
					    $prunestamp);

    my %weirdfiles = map { $_ => 1 } grep { ! /\.(html|css|png)$/ } @cachefiles;
    foreach (@known_files) {
	delete $weirdfiles{$_} if exists $weirdfiles{$_};
    }
    # and bug directories
    foreach (@cachefiles) {
	if (/^(\d+)\.html$/) {
	    delete $weirdfiles{$1} if exists $weirdfiles{$1} and -d $1;
	    delete $weirdfiles{"$1.mbox"}
	        if exists $weirdfiles{"$1.mbox"} and -f "$1.mbox";
	    delete $weirdfiles{"$1.raw.mbox"}
	        if exists $weirdfiles{"$1.raw.mbox"} and -f "$1.raw.mbox";
	    delete $weirdfiles{"$1.status.mbox"}
	        if exists $weirdfiles{"$1.status.mbox"} and -f "$1.status.mbox";
	}
    }

    warn "$progname: unexpected files/dirs in cache directory $cachedir:\n  " .
	join("\n  ", keys %weirdfiles) . "\n"
	if keys %weirdfiles;

    my @oldfiles;
    foreach (@cachefiles) {
	next unless /\.(html|css)$/;
	push @oldfiles, $_ if -A $_ > 30;
    }

    # We now remove the oldfiles if they're automatically downloaded
    tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	 O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	or die "$progname: couldn't open DB file $timestampdb for writing: $!\n"
	if ! tied %timestamp;

    my @unrecognised;
    foreach my $oldfile (@oldfiles) {
	my ($thing, $thgopts) = cachefile_to_thing($oldfile);
	unless (defined get_timestamp($thing, $thgopts)) {
	    push @unrecognised, $oldfile;
	    next;
	}
	next if is_manual(get_timestamp($thing, $thgopts));

	# Otherwise, it's automatic and we purge it
	deletecache($thing, $thgopts);
    }

    untie %timestamp;

    if (! -e $prunestamp) {
	open PRUNESTAMP, ">$prunestamp" || die "$progname: prune timestamp: $!\n";
	close PRUNESTAMP;
    }
    chdir $oldcwd || die "$progname: chdir $oldcwd: $!\n";
    utime time, time, $prunestamp;
}

# Determines which browser to use
sub runbrowser {
    my $URL = shift;

    if (system('sensible-browser', $URL) >> 8 != 0) {
	warn "Problem running sensible-browser: $!\n";
    }
}

# Determines which mailreader to use
sub runmailreader {
    my $file = shift;
    my $quotedfile;
    die "$progname: could not read mbox file!\n" unless -r $file;

    if ($file !~ /\'/) { $quotedfile = qq['$file']; }
    elsif ($file !~ /[\"\\\$\'\!]/) { $quotedfile = qq["$file"]; }
    else { die "$progname: could not figure out how to quote the mbox filename \"$file\"\n"; }

    my $reader = $mailreader;
    $reader =~ s/\%([%s])/$1 eq '%' ? '%' : $quotedfile/eg;

    if (system($reader) >> 8 != 0) {
	warn "Problem running mail reader: $!\n";
    }
}

# Timestamp handling
#
# We store a +ve timestamp to represent an automatic download and
# a -ve one to represent a manual download.

sub get_timestamp {
    my $thing = shift;
    my $thgopts = shift || '';
    my $timestamp = undef;
    my $versionstamp = undef;

    if (tied %timestamp) {
	($timestamp, $versionstamp) = split /;/, $timestamp{$thing.$thgopts}
	    if exists $timestamp{$thing.$thgopts};
    } else {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDONLY(), 0600, $DB_HASH, "read")
	    or die "$progname: couldn't open DB file $timestampdb for reading: $!\n";

	($timestamp, $versionstamp) = split /;/, $timestamp{$thing.$thgopts}
	    if exists $timestamp{$thing.$thgopts};

	untie %timestamp;
    }

    return wantarray ? ($timestamp, $versionstamp) : $timestamp;
}

sub set_timestamp {
    my $thing = shift;
    my $thgopts = shift || '';
    my $timestamp = shift;
    my $versionstamp = shift || $version;

    if (tied %timestamp) {
	$timestamp{$thing.$thgopts} = "$timestamp;$versionstamp";
    } else {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	    or die "$progname: couldn't open DB file $timestampdb for writing: $!\n";

	$timestamp{$thing.$thgopts} = "$timestamp;$versionstamp";

	untie %timestamp;
    }
}

sub delete_timestamp {
    my $thing = shift;
    my $thgopts = shift || '';

    if (tied %timestamp) {
	delete $timestamp{$thing.$thgopts};
    } else {
	tie (%timestamp, "Devscripts::DB_File_Lock", $timestampdb,
	     O_RDWR()|O_CREAT(), 0600, $DB_HASH, "write")
	    or die "$progname: couldn't open DB file $timestampdb for writing: $!\n";

	delete $timestamp{$thing.$thgopts};

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

# Returns true if current cached version is older than critical version
# We're only using really simple version numbers here: a.b.c
sub old_cache_format_version {
    my $cacheversion = $_[0];

    my @cache = split /\./, $cacheversion;
    my @new = split /\./, $new_cache_format_version;

    push @cache, 0, 0, 0, 0;
    push @new, 0, 0;

    return
	($cache[0]<$new[0]) ||
	($cache[0]==$new[0] && $cache[1]<$new[1]) ||
	($cache[0]==$new[0] && $cache[1]==$new[1] && $cache[2]<$new[2]) ||
	($cache[0]==$new[0] && $cache[1]==$new[1] && $cache[2]==$new[2] &&
	 $cache[3]<$new[3]);
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

sub bts_mirror {
    my ($url, $timestamp, $force) = @_;

    init_agent() unless $ua;
    if ($url =~ m%/\d+$% and ! $refreshmode and ! $force) {
	# Single bug, worth doing timestamp checks
	my $request = HTTP::Request->new('HEAD', $url);
	my $response = $ua->request($request);

	if ($response->is_success) {
	    my $lm = $response->last_modified;
	    if (defined $lm and $lm <= abs($timestamp)) {
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

	return (MIRROR_DOWNLOADED, $response->status_line, $response->content, $response->header('Content-Type'));
    } else {
	return (MIRROR_ERROR, $response->status_line);
    }
}

sub init_agent {
    $ua = new LWP::UserAgent;  # we create a global UserAgent object
    $ua->agent("LWP::UserAgent/Devscripts/$version");
    $ua->env_proxy;
}

sub opts_done {
    if (@_) {
	die "$progname: unknown options to '$command[$index]': @_\n";
    }
}

sub edit {
    my $message = shift;
    my ($fh, $filename);
    ($fh, $filename) = tempfile("btsXXXX",
				  SUFFIX => ".mail",
				  DIR => File::Spec->tmpdir);
    open(OUT_MAIL, ">$filename")
	or die "$progname: writing to temporary file: $!\n";
    print OUT_MAIL $message;
    close OUT_MAIL;
    system("sensible-editor $filename");
    open(OUT_MAIL, "<$filename")
	or die "$progname: reading from temporary file: $!\n";
    $message = "";
    while(<OUT_MAIL>) {
	$message .= $_;
    }
    close OUT_MAIL;
    unlink($filename);
    return $message;
}

=back

=head1 ENVIRONMENT VARIABLES

=over 4

=item B<DEBEMAIL>

If this is set, the From: line in the email will be set to use this email
address instead of your normal email address (as would be determined by
B<mail>).

=item B<DEBFULLNAME>

If B<DEBEMAIL> is set, B<DEBFULLNAME> is examined to determine the full name
to use; if this is not set, B<bts> attempts to determine a name from
your F<passwd> entry.

=item B<BROWSER>

If set, it specifies the browser to use for the B<show> and B<bugs>
options.  See the description above.

=back

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables.  Command line options can be used to override
configuration file settings.  Environment variable settings are
ignored for this purpose.  The currently recognised variables are:

=over 4

=item B<BTS_OFFLINE>

If this is set to B<yes>, then it is the same as the B<--offline> command
line parameter being used.  Only has an effect on the B<show> and B<bugs>
commands.  The default is B<no>.  See the description of the B<show>
command above for more information.

=item B<BTS_CACHE>

If this is set to B<no>, then it is the same as the B<--no-cache> command
line parameter being used.  Only has an effect on the B<show> and B<bug>
commands.  The default is B<yes>.  Again, see the B<show> command above
for more information.

=item B<BTS_CACHE_MODE=>{B<min>,B<mbox>,B<full>}

How much of the BTS should we mirror when we are asked to cache something?
Just the minimum, or also the mbox or the whole thing?  The default is
B<min>, and it has the same meaning as the B<--cache-mode> command line
parameter.  Only has an effect on the cache.  See the B<cache> command for more
information.

=item B<BTS_FORCE_REFRESH>

If this is set to B<yes>, then it is the same as the B<--force-refresh>
command line parameter being used.  Only has an effect on the B<cache>
command.  The default is B<no>.  See the B<cache> command for more
information.

=item B<BTS_MAIL_READER>

If this is set, specifies a mail reader to use instead of B<mutt>.  Same as
the B<--mailreader> command line option.

=item B<BTS_SENDMAIL_COMMAND>

If this is set, specifies a B<sendmail> command to use instead of
F</usr/sbin/sendmail>.  Same as the B<--sendmail> command line option.

=item B<BTS_ONLY_NEW>

Download only new bugs when caching. Do not check for updates in
bugs we already have.  The default is B<no>.  Same as the B<--only-new>
command line option.

=item B<BTS_SMTP_HOST>

If this is set, specifies an SMTP host to use for sending mail rather
than using the B<sendmail> command.  Same as the B<--smtp-host> command line
option.

Note that this option takes priority over B<BTS_SENDMAIL_COMMAND> if both are
set, unless the B<--sendmail> option is used.

=item B<BTS_SMTP_AUTH_USERNAME>, B<BTS_SMTP_AUTH_PASSWORD>

If these options are set, then it is the same as the B<--smtp-username> and
B<--smtp-password> options being used.

=item B<BTS_SMTP_HELO>

Same as the B<--smtp-helo> command line option.

=item B<BTS_INCLUDE_RESOLVED>

If this is set to B<no>, then it is the same as the B<--no-include-resolved>
command line parameter being used.  Only has an effect on the B<cache>
command.  The default is B<yes>.  See the B<cache> command for more
information.

=item B<BTS_SUPPRESS_ACKS>

If this is set to B<yes>, then it is the same as the B<--no-ack> command
line parameter being used.  The default is B<no>.

=item B<BTS_INTERACTIVE>

If this is set to B<yes> or B<force>, then it is the same as the
B<--interactive> or B<--force-interactive> command line parameter being used.
The default is B<no>.

=item B<BTS_DEFAULT_CC>

Specify a list of e-mail addresses to which a carbon copy of the generated
e-mail to the control bot should automatically be sent.

=item B<BTS_SERVER>

Specify the name of a debbugs server which should be used instead of
bugs.debian.org.

=back

=head1 SEE ALSO

Please see L<http://www.debian.org/Bugs/server-control> for
more details on how to control the BTS using emails and
L<http://www.debian.org/Bugs/> for more information about the BTS.

querybts(1), reportbug(1)

=head1 COPYRIGHT

This program is Copyright (C) 2001-2003 by Joey Hess <joeyh@debian.org>.
Many modifications have been made, Copyright (C) 2002-2005 Julian
Gilbey <jdg@debian.org> and Copyright (C) 2007 Josh Triplett
<josh@freedesktop.org>.

It is licensed under the terms of the GPL, either version 2 of the
License, or (at your option) any later version.

=cut

# Please leave this alone unless you understand the seek above.
__DATA__
