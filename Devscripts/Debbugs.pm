# This is Debbugs.pm from the Debian devscripts package
#
#   Copyright (C) 2008 Adam D. Barratt
#   select() is Copyright (C) 2007 Don Armstrong
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

package Devscripts::Debbugs;

=head1 OPTIONS

=item select [key:value  ...]

Uses the SOAP interface to output a list of bugs which match the given
selection requirements.

The following keys are allowed, and may be given multiple times.

=over 8

=item package

Binary package name.

=item source

Source package name.

=item maintainer

E-mail address of the maintainer.

=item submitter

E-mail address of the submitter.

=item severity

Bug severity.

=item status

Status of the bug.

=item tag

Tags applied to the bug. If I<users> is specified, may include
usertags in addition to the standard tags.

=item owner

Bug's owner.

=item correspondent

Address of someone who sent mail to the log.

=item affects

Bugs which affect this package.

=item bugs

List of bugs to search within.

=item users

Users to use when looking up usertags.

=item archive

Whether to search archived bugs or normal bugs; defaults to 0
(i.e. only search normal bugs). As a special case, if archive is
'both', both archived and unarchived bugs are returned.

=back

For example, to select the set of bugs submitted by
jrandomdeveloper@example.com and tagged wontfix, one would use

select("submitter:jrandomdeveloper@example.com", "tag:wontfix")

=cut

use strict;
use warnings;

my $soapurl='Debbugs/SOAP/1';
our $btsurl='http://bugs.debian.org/';
my @errors;

sub init_soap {
    my $soapproxyurl;
    if ($btsurl =~ m%^https?://(.*)/?$%) {
	$soapproxyurl = $btsurl . '/';
    } else {
	$soapproxyurl = 'http://' . $btsurl . '/';
    }
    $soapproxyurl =~ s%//$%/%;
    $soapproxyurl .= 'cgi-bin/soap.cgi';
    my $soap = SOAP::Lite->uri($soapurl)->proxy($soapproxyurl);

    $soap->transport->env_proxy();
    $soap->on_fault(\&getSOAPError);

    return $soap;
}

my $soap_broken;
sub have_soap {
    return ($soap_broken ? 0 : 1) if defined $soap_broken;
    eval {
	require SOAP::Lite;
    };

    if ($@) {
	if ($@ =~ m%^Can't locate SOAP/%) {
	    $soap_broken="the libsoap-lite-perl package is not installed";
	} else {
	    $soap_broken="couldn't load SOAP::Lite: $@";
	}
    }
    else {
	$soap_broken = 0;
    }
    return ($soap_broken ? 0 : 1);
}

sub getSOAPError {
    my ($soap, $result) = @_;
    my $err;
    if (ref($result)) {
	$err = $result->faultstring;
    } else {
	$err = $soap->transport->status;
    }
    chomp $err;
    push @errors, $err;

    return new SOAP::SOM;
}

sub usertags {
    die "Couldn't run usertags: $soap_broken\n" unless have_soap();

    my @args = @_;

    my $soap = init_soap();
    my $usertags = $soap->get_usertag(@_);

    if (@errors or not defined $usertags) {
	my $error = join("\n", @errors);
	die "Error retrieving usertags from SOAP server: $error\n";
    }

    my $result = $usertags->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error retrieving usertags from SOAP server: $error\n";
    }

    return $result;
}

sub select {
    die "Couldn't run select: $soap_broken\n" unless have_soap();
    my @args = @_;
    my %valid_keys = (package => 'package',
                      pkg     => 'package',
                      src     => 'src',
                      source  => 'src',
                      maint   => 'maint',
                      maintainer => 'maint',
                      submitter => 'submitter',
                      from => 'submitter',
                      status    => 'status',
                      tag       => 'tag',
                      tags      => 'tag',
                      usertag   => 'tag',
                      usertags  => 'tag',
                      owner     => 'owner',
                      dist      => 'dist',
                      distribution => 'dist',
                      bugs       => 'bugs',
                      archive    => 'archive',
                      severity   => 'severity',
                      correspondent => 'correspondent',
                      affects       => 'affects',
    );
    my %users;
    my %search_parameters;
    my $soap = init_soap();
    for my $arg (@args) {
	my ($key,$value) = split /:/, $arg, 2;
	next unless $key;
	if (exists $valid_keys{$key}) {
	    if ($valid_keys{$key} eq 'archive') {
		$search_parameters{$valid_keys{$key}} = $value
		    if $value;
	    } else {
		push @{$search_parameters{$valid_keys{$key}}},
		    $value if $value;
	    }
	} elsif ($key =~/users?$/) {
	    $users{$value} = 1 if $value;
	} else {
	    warn "select(): Unrecognised key: $key\n";
	}
    }
    my %usertags;
    for my $user (keys %users) {
	my $ut = usertags($user);
	next unless defined $ut and $ut ne "";
	for my $tag (keys %{$ut}) {
	    push @{$usertags{$tag}},
	    @{$ut->{$tag}};
	}
    }
    my $bugs = $soap->get_bugs(%search_parameters,
	(keys %usertags)?(usertags=>\%usertags):()
    );

    if (@errors or not defined $bugs) {
	my $error = join("\n", @errors);
	die "Error while retrieving bugs from SOAP server: $error\n";
    }

    my $result = $bugs->result();
    if (@errors or not defined $result) {
	my $error = join( "\n", @errors );
	die "Error while retrieving bugs from SOAP server: $error\n";
    }

    return $result;
}

sub status {
    die "Couldn't run status: $soap_broken\n" unless have_soap();
    my @args = @_;

    my $soap = init_soap();

    my $bugs = $soap->get_status(@args);

    if (@errors or not defined $bugs) {
	my $error = join("\n", @errors);
	die "Error while retrieving bug statuses from SOAP server: $error\n";
    }

    my $result = $bugs->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error while retrieving bug statuses from SOAP server: $error\n";
    }

    return $result;
}

sub versions {
    die "Couldn't run versions: $soap_broken\n" unless have_soap();

    my @args = @_;
    my %valid_keys = (package => 'package',
                      pkg     => 'package',
                      src => 'source',
                      source => 'source',
                      time => 'time',
                      binary => 'no_source_arch',
                      notsource => 'no_source_arch',
                      archs => 'return_archs',
                      displayarch => 'return_archs',
    );

    my %search_parameters;
    my @archs = ();
    my @dists = ();

    for my $arg (@args) {
	my ($key,$value) = split /:/, $arg, 2;
	$value ||= "1";
	if ($key =~ /^arch(itecture)?$/) {
	    push @archs, $value;
	} elsif ($key =~ /^dist(ribution)?$/) {
	    push @dists, $value;
	} elsif (exists $valid_keys{$key}) {
	    $search_parameters{$valid_keys{$key}} = $value;
	}
    }

    $search_parameters{arch} = \@archs if @archs;
    $search_parameters{dist} = \@dists if @dists;

    my $soap = init_soap();

    my $versions = $soap->get_versions(%search_parameters);

    if (@errors or not defined $versions) {
	my $error = join("\n", @errors);
	die "Error while retrieving package versions from SOAP server: $error\n";
    }

    my $result = $versions->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error while retrieivng package versions from SOAP server: $error";
    }

    return $result;
}

sub versions_with_arch {
    die "Couldn't run versions_with_arch: $soap_broken\n" unless have_soap();
    my @args = @_;

    my $versions = versions(@args, 'displayarch:1');

    if (not defined $versions) {
	die "Error while retrieivng package versions from SOAP server: $@";
    }

    return $versions;
}

sub newest_bugs {
    die "Couldn't run newest_bugs: $soap_broken\n" unless have_soap();
    my $count = shift || '';

    return if $count !~ /^\d+$/;

    my $soap = init_soap();

    my $bugs = $soap->newest_bugs($count);

    if (@errors or not defined $bugs) {
	my $error = join("\n", @errors);
	die "Error while retrieving newest bug list from SOAP server: $error";
    }

    my $result = $bugs->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error while retrieving newest bug list from SOAP server: $error";
    }

    return $result;
}

# debbugs currently ignores the $msg_num parameter
# but eventually it might not, so we support passing it

sub bug_log {
    die "Couldn't run bug_log: $soap_broken\n" unless have_soap();

    my $bug = shift || '';
    my $message = shift;

    return if $bug !~ /^\d+$/;

    my $soap = init_soap();

    my $log = $soap->get_bug_log($bug, $message);

    if (@errors or not defined $log) {
	my $error = join("\n", @errors);
	die "Error while retrieving bug log from SOAP server: $error\n";
    }

    my $result = $log->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error while retrieving bug log from SOAP server: $error\n";
    }

    return $result;
}

sub binary_to_source {
    die "Couldn't run binary_to_source: $soap_broken\n"
	unless have_soap();

    my $soap = init_soap();

    my $binpkg = shift;
    my $binver = shift;
    my $arch = shift;

    return if not defined $binpkg or not defined $binver;

    my $mapping = $soap->binary_to_source($binpkg, $binver, $arch);

    if (@errors or not defined $mapping) {
	my $error = join("\n", @errors);
	die "Error while retrieving binary to source mapping from SOAP server: $error\n";
    }

    my $result = $mapping->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error while retrieving binary to source mapping from SOAP server: $error\n";
    }

    return $result;
}

sub source_to_binary {
    die "Couldn't run source_to_binary: $soap_broken\n"
	unless have_soap();

    my $soap = init_soap();

    my $srcpkg = shift;
    my $srcver = shift;

    return if not defined $srcpkg or not defined $srcver;

    my $mapping = $soap->source_to_binary($srcpkg, $srcver);

    if (@errors or not defined $mapping) {
	my $error = join("\n", @errors);
	die "Error while retrieving source to binary mapping from SOAP server: $error\n";
    }

    my $result = $mapping->result();

    if (@errors or not defined $result) {
	my $error = join("\n", @errors);
	die "Error while retrieving source to binary mapping from SOAP server: $error\n";
    }

    return $result;
}

1;

__END__

