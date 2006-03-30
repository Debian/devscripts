#!/usr/bin/perl

=head1 NAME

mass-bug - mass-file a bug report against a list of packages

=head1 SYNOPSIS

mass-bug [--display|--send] --subject="bug subject" template package-list

=head1 DESCRIPTION

mass-bug assists in filing a mass bug report in the Debian BTS on a set of
packages. For each package in the package-list file (which should list one
package per line), it fills out the template, adds BTS pseudo-headers, and
either displays or sends the bug report.

Warning: Some care has been taken to avoid unpleasant and common mistakes,
but this is still a power tool that can generate massive amounts of bug
report mails. Use it with care, and read the documentation in the
Developer's Reference about mass filing of bug reports first.

=head1 TEMPLATE

The template file is the body of the message that will be sent for each bug
report, excluding the BTS pseudo-headers. In the template, #PACKAGE# is
replaced with the name of the package.

Note that text in the template will be automatically word-wrapped to 70
columns.

=head1 OPTIONS

=over 4

=item --display

Fill out the templates for each package and display them all for
verification. This is the default behavior.

=item --send

Actually send the bug reports.

=item --subject="bug subject"

Specify the subject of the bug report. The subject will be automatically
prefixed with the name of the package that the bug is filed on.

=over 4

=back

=head1 ENVIRONMENT

DEBEMIL and EMAIL can be set in the environment to control the email
address that the bugs are sent from.

=cut

use warnings;
use strict;
use Getopt::Long;
use Text::Wrap;

$Text::Wrap::columns=70;
my $submission_email="maintonly\@bugs.debian.org";
my $sendmailcmd='/usr/sbin/sendmail';

sub usage {
	die "Usage: mass-bug [--display|--send] --subject=\"bug subject\" template package-list\n";
}

sub gen_subject {
	my $subject=shift;
	my $package=shift;
	
	return "$package\: $subject";
}

sub gen_bug {
	my $template_text=shift;
	my $package=shift;

	$template_text=~s/#PACKAGE#/$package/g;
	$template_text=fill("", "", $template_text);
	return "Package: $package\n\n$template_text";
}
		
sub div {
	print +("-" x 79)."\n";
}

sub mailbts {
	my ($subject, $body, $to, $from) = @_;

	if (defined $from) {
		my $date = `822-date`;
		chomp $date;

		my $pid = open(MAIL, "|-");
		if (! defined $pid) {
			die "mass-bug: Couldn't fork: $!\n";
		}
		if ($pid) {
			# parent
			print MAIL <<"EOM";
From: $from
To: $to
Subject: $subject
Date: $date
X-Generator: mass-bug

$body
EOM
			close MAIL or die "mass-bug: sendmail error: $!\n";
		}
		else {
			# child
			exec(split(' ', $sendmailcmd), "-t")
				or die "mass-bug: error running sendmail: $!\n";
		}
	}
	else { # No $from
		unless (system("command -v mail >/dev/null 2>&1") == 0) {
			die "mass-bug: You need to either specify an email address (say using DEBEMAIL)\n or have the mailx/mailutils package installed to send mail!\n";
		}
		my $pid = open(MAIL, "|-");
		if ($pid) {
			# parent
			print MAIL $body;
			close MAIL or die "mass-bug: mail: $!\n";
		}
		else {
			# child
			exec("mail", "-s", $subject, $to)
				or die "mass-bug: error running mail: $!\n";
		}
	}
}

my $mode="display";
my $subject;
if (! GetOptions(
		 "display" => sub { $mode="display" },
		 "send" => sub { $mode="send" },
		 "subject=s" => \$subject,
		 )) {
	usage();
}

if (! defined $subject || ! length $subject) {
	print STDERR "You must specify a subject for the bug reports.\n";
	usage();
}

if (@ARGV != 2) {
	usage();
}

my $template=shift;
my $package_list=shift;

my $template_text;
open (T, "$template") || die "read $template: $!";
{
	local $/=undef;
	$template_text=<T>;
}
close T;
if (! length $template_text) {
	die "empty template\n";
}

my @packages;
open (L, "$package_list") || die "read $package_list: $!";
while (<L>) {
	chomp;
	if (! /^[-+.a-z0-9]+$/) {
		die "\"$_\" does not look like the name of a Debian package\n";
	}
	push @packages, $_;
}
close L;

# Uses variables from above.
sub showsample {
	my $package=shift;

	print "To: $submission_email\n";
	print "Subject: ".gen_subject($subject, $package)."\n";
	print "\n";
	print gen_bug($template_text, $package)."\n";
}

if ($mode eq 'display') {
	print "Displaying all ".int(@packages)." bug reports..\n";
	print "Run again with --send switch to send the bug reports.\n";
	div();
	foreach my $package (@packages) {
		showsample($package);
		div();
	}
}
elsif ($mode eq 'send') {
	my $from;
	$from ||= $ENV{'DEBEMAIL'};
	$from ||= $ENV{'EMAIL'};
	
	print "Preparing to send ".int(@packages)." bug reports like this one:\n";
	div();
	showsample($packages[0]);
	div();
	$|=1;
	print "Press enter to mass-file bug reports. ";
	<STDIN>;
	print "\n";
	foreach my $package (@packages) {
		print "Sending bug for $package ...\n";
		mailbts(gen_subject($subject, $package),
			gen_bug($template_text, $package),
			$submission_email, $from);
	}
	print "All bugs sent.\n";
}

=head1 LICENSE

GPL

=head1 AUTHOR

Joey Hess <joeyh@debian.org>

=cut
