#!/usr/bin/perl

# This program takes .changes or .dsc files as arguments and verifies
# that they're properly signed by a Debian developer, and that the local
# copies of the files mentioned in them match the MD5 sums given.

# Copyright 1998 Roderick Schertler <roderick@argon.org>
# Modifications copyright 1999,2000,2002 Julian Gilbey <jdg@debian.org>
# Drastically simplified to match katie's signature checking Feb 2002
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

use 5.004;	# correct pipe close behavior
use strict;
use warnings;
use Cwd;
use Fcntl;
use Dpkg::IPC;
use File::Spec;
use File::Temp;
use File::Basename;
use POSIX	qw(:errno_h);
use Getopt::Long qw(:config gnu_getopt);
use List::Util qw(first);

BEGIN {
    eval { require Digest::MD5; };
    if ($@) {
	my $progname = basename $0;
	if ($@ =~ /^Can\'t locate Digest\/MD5\.pm/) {
	    die "$progname: you must have the libdigest-md5-perl package installed\nto use this script\n";
	}
	die "$progname: problem loading the Digest::MD5 module:\n  $@\nHave you installed the libdigest-md5-perl package?\n";
    }
}

my $progname = basename $0;
my $modified_conf_msg;
my $Exit = 0;
my $start_dir = cwd;
my $verify_sigs = 1;
my $use_default_keyrings = 1;
my $verbose = 0;
my $havegpg = first { -x $_ } qw(/usr/bin/gpg2 /usr/bin/gpg);

sub usage {
    print <<"EOF";
Usage: $progname [options] dsc-or-changes-file ...
  Options: --help      Display this message
           --version   Display version and copyright information
           --keyring <keyring>
                       Add <keyring> to the list of keyrings used
           --no-default-keyrings
                       Do not check against the default keyrings
           --nosigcheck, --no-sig-check, -u
                       Do not verify the GPG signature
           --no-conf, --noconf
                       Do not read the devscripts config file
           --verbose
	               Do not suppress GPG output.


Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1998 Roderick Schertler <roderick\@argon.org>
Modifications are copyright 1999, 2000, 2002 Julian Gilbey <jdg\@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF

sub xwarndie_mess {
    my @mess = ("$progname: ", @_);
    $mess[$#mess] =~ s/:$/: $!\n/;	# XXX loses if it's really /:\n/
    return @mess;
}

sub xwarn {
    warn xwarndie_mess @_;
    $Exit ||= 1;
}

sub xdie {
    die xwarndie_mess @_;
}

sub get_rings {
    my @rings = @_;
    my @keyrings = qw(/usr/share/keyrings/debian-keyring.gpg
	    /usr/share/keyrings/debian-maintainers.gpg);
    if (defined $ENV{HOME} && -r "$ENV{HOME}/.gnupg/trustedkeys.gpg") {
	unshift(@keyrings, "$ENV{HOME}/.gnupg/trustedkeys.gpg");
    }
    unshift(@keyrings, '/org/keyring.debian.org/keyrings/debian-keyring.gpg');
    if (system('dpkg-vendor', '--derives-from', 'Ubuntu') == 0) {
        unshift(@keyrings, qw(/usr/share/keyrings/ubuntu-master-keyring.gpg
			      /usr/share/keyrings/ubuntu-archive-keyring.gpg));
    }
    for (@keyrings) {
	push @rings, $_ if -r;
    }
    return @rings if @rings;
    xdie "can't find any system keyrings\n";
}

sub check_signature($\@;\$) {
    my ($file, $rings, $outref) = @_;

    my $fh = eval { File::Temp->new() }
	or xdie "unable to open status file for gpg: $@\n";

    # Allow the status file descriptor to pass on to the child process
    my $flags = fcntl($fh, F_GETFD, 0);
    fcntl($fh, F_SETFD, $flags & ~FD_CLOEXEC);

    my $fd = fileno $fh;
    my @cmd;
    push @cmd, $havegpg, "--status-fd", $fd,
	       qw(--batch --no-options --no-default-keyring --always-trust);
    foreach (@$rings) { push @cmd, '--keyring'; push @cmd, $_; }

    my ($out, $err) = ('', '');
    eval {
	spawn(exec => \@cmd,
	    from_file => $file,
	    to_string => \$out,
	    error_to_string => \$err,
	    wait_child => 1);
    };

    if ($@) {
	print $out if ($verbose);
	return $err || $@;
    }

    seek($fh, 0, SEEK_SET);
    my $status;
    $status .= $_ while <$fh>;
    close $fh;

    if ($status !~ m/^\[GNUPG:\] VALIDSIG/m) {
	return $out;
    }

    if (defined $outref) {
	$$outref = $out;
    }

    return '';
}

sub process_file {
    my ($file, @rings) = @_;
    my ($filedir, $filebase);
    my $sigcheck;

    print "$file:\n";

    # Move to the directory in which the file appears to live
    chdir $start_dir or xdie "can't chdir to original directory!\n";
    if ($file =~ m-(.*)/([^/]+)-) {
	$filedir = $1;
	$filebase = $2;
	unless (chdir $filedir) {
	    xwarn "can't chdir $filedir:";
	    return;
	}
    } else {
	$filebase = $file;
    }

    my $out;
    if ($verify_sigs) {
	$sigcheck = check_signature $filebase, @rings, $out;
	if ($sigcheck) {
	    xwarn "$file failed signature check:\n$sigcheck";
	    return;
	} else {
	    print "      Good signature found\n";
	}
    }
    else {
	if (!open SIGNED, '<', $filebase) {
	    xwarn "can't open $file:";
	    return;
	}
	$out = do { local $/; <SIGNED> };
	if (!close SIGNED) {
	    xwarn "problem reading $file:";
	    return;
	}
    }

    if ($file =~ /\.changes$/ and $out =~ /^Format:\s*(.*)$/mi) {
	my $format = $1;
	unless ($format =~ /^(\d+)\.(\d+)$/) {
	    xwarn "$file has an unrecognised format: $format\n";
	    return;
	}
	my ($major, $minor) = split /\./, $format;
	$major += 0;
	$minor += 0;
	unless ($major == 1 and $minor <= 8) {
	    xwarn "$file is an unsupported format: $format\n";
	    return;
	}
    }

    my @spec = map { split /\n/ } $out =~ /^Files:\s*\n((?:[ \t]+.*\n)+)/mgi;
    unless (@spec) {
	xwarn "no file spec lines in $file\n";
	return;
    }

    my @checksums = map { split /\n/ } $out =~ /^Checksums-(\S+):\s*\n/mgi;
    @checksums = grep {!/^Sha(1|256)$/i} @checksums;
    if (@checksums) {
	xwarn "$file contains unsupported checksums:\n"
	    . join (", ", @checksums) . "\n";
	return;
    }

    my %sha1s = map { reverse split /(\S+)\s*$/m }
	$out =~ /^Checksums-Sha1:\s*\n((?:[ \t]+.*\n)+)/mgi;
    my %sha256s = map { reverse split /(\S+)\s*$/m }
	$out =~ /^Checksums-Sha256:\s*\n((?:[ \t]+.*\n)+)/mgi;
    my $md5o = Digest::MD5->new or xdie "can't initialize MD5\n";
    my $any;
    for (@spec) {
	unless (/^\s+([0-9a-f]{32})\s+(\d+)\s+(?:\S+\s+\S+\s+)?(\S+)\s*$/) {
	    xwarn "invalid file spec in $file `$_'\n";
	    next;
	}
	my ($md5, $size, $filename) = ($1, $2, $3);
	my ($sha1, $sha1size, $sha256, $sha256size);
	$filename !~ m,[/\x00],
	    or xdie "File name contains invalid characters: $file";

	if (keys %sha1s) {
	    $sha1 = $sha1s{$filename};
	    unless (defined $sha1) {
		xwarn "no sha1 for `$filename' in $file\n";
		next;
	    }
	    unless ($sha1 =~ /^\s+([0-9a-f]{40})\s+(\d+)\s*$/) {
		xwarn "invalid sha1 spec in $file `$sha1'\n";
		next;
	    }
	    ($sha1, $sha1size) = ($1, $2);
	} else {
	    $sha1size = $size;
	}

	if (keys %sha256s) {
	    $sha256 = $sha256s{$filename};
	    unless (defined $sha256) {
		xwarn "no sha256 for `$filename' in $file\n";
		next;
	    }
	    unless ($sha256 =~ /^\s+([0-9a-f]{64})\s+(\d+)\s*$/) {
		xwarn "invalid sha256 spec in $file `$sha256'\n";
		next;
	    }
	    ($sha256, $sha256size) = ($1, $2);
	} else {
	    $sha256size = $size;
	}

	unless (open FILE, '<', $filename) {
	    if ($! == ENOENT) {
		print STDERR "   skipping  $filename (not present)\n";
	    }
	    else {
		xwarn "can't read $filename:";
	    }
	    next;
	}

	$any = 1;
	print "   validating $filename\n";

	# size
	my $this_size = -s FILE;
	unless (defined $this_size) {
	    xwarn "can't fstat $filename:";
	    next;
	}
	unless ($this_size == $size) {
	    xwarn "invalid file length for $filename (wanted $size got $this_size)\n";
	    next;
	}
	unless ($this_size == $sha1size) {
	    xwarn "invalid sha1 file length for $filename (wanted $sha1size got $this_size)\n";
	    next;
	}
	unless ($this_size == $sha256size) {
	    xwarn "invalid sha256 file length for $filename (wanted $sha256size got $this_size)\n";
	    next;
	}

	# MD5
	$md5o->reset;
	$md5o->addfile(*FILE);
	my $this_md5 = $md5o->hexdigest;
	unless ($this_md5 eq $md5) {
	    xwarn "MD5 mismatch for $filename (wanted $md5 got $this_md5)\n";
	    next;
	}

	my $this_sha1;
	eval {
	    spawn(exec => ['sha1sum', $filename],
		to_string => \$this_sha1,
		wait_child => 1);
	};
	($this_sha1) = split /\s/,$this_sha1,2;
	$this_sha1 ||= '';
	unless (! keys %sha1s or $this_sha1 eq $sha1) {
	    xwarn "SHA1 mismatch for $filename (wanted $sha1 got $this_sha1)\n";
	    next;
	}

	my $this_sha256;
	eval {
	    spawn(exec => ['sha256sum', $filename],
		to_string => \$this_sha256,
		wait_child => 1);
	};
	($this_sha256) = split /\s/,$this_sha256,2;
	$this_sha256 ||= '';
	unless (! keys %sha256s or $this_sha256 eq $sha256) {
	    xwarn "SHA256 mismatch for $filename (wanted $sha256 got $this_sha256)\n";
	    next;
	}

	close FILE;

	if ($filename =~ /\.dsc$/ && $verify_sigs) {
	    $sigcheck = check_signature $filename, @rings;
	    if ($sigcheck) {
		xwarn "$filename failed signature check:\n$sigcheck";
		next;
	    } else {
		print "      Good signature found\n";
	    }
	}
    }

    $any or
	xwarn "$file didn't specify any files present locally\n";
}

sub main {
    @ARGV or xdie "no .changes or .dsc files specified\n";

    my @rings;

    # Handle config file unless --no-conf or --noconf is specified
    # The next stuff is boilerplate
    if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
	$modified_conf_msg = "  (no configuration files read)";
	shift @ARGV;
    } else {
	my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
	my %config_vars = (
			   'DSCVERIFY_KEYRINGS' => '',
			   );
	my %config_default = %config_vars;

	my $shell_cmd;
	# Set defaults
	foreach my $var (keys %config_vars) {
	    $shell_cmd .= "$var='$config_vars{$var}';\n";
	}
	$shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
	$shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
	# Read back values
	foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
	my $shell_out = `/bin/bash -c '$shell_cmd'`;
	@config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

	foreach my $var (sort keys %config_vars) {
	    if ($config_vars{$var} ne $config_default{$var}) {
		$modified_conf_msg .= "  $var=$config_vars{$var}\n";
	    }
	}
	$modified_conf_msg ||= "  (none)\n";
	chomp $modified_conf_msg;

	$config_vars{'DSCVERIFY_KEYRINGS'} =~ s/^\s*:\s*//;
	$config_vars{'DSCVERIFY_KEYRINGS'} =~ s/\s*:\s*$//;
	@rings = split /\s*:\s*/, $config_vars{'DSCVERIFY_KEYRINGS'};
    }

    GetOptions(
	'help' => sub { usage; exit 0; },
	'version' => sub { print $version; exit 0; },
	'sigcheck|sig-check!' => \$verify_sigs,
	'u' => sub { $verify_sigs = 0 },
	'noconf|no-conf' => sub {
	    die "--$_[0] is only acceptable as the first command-line option!\n";
	},
	'default-keyrings!' => \$use_default_keyrings,
	'keyring=s@' => sub {
	    my $ring = $_[1];
	    if (-r $ring) { push @rings, $ring; }
	    else { die "Keyring $ring unreadable\n" }
	},
	'verbose' => \$verbose,
    ) or do { usage; exit 1 };

    @ARGV or xdie "no .changes or .dsc files specified\n";

    @rings = get_rings @rings if $use_default_keyrings and $verify_sigs;

    for my $file (@ARGV) {
	process_file $file, @rings;
    }

    return 0;
}

$Exit = main || $Exit;
$Exit = 1 if $Exit and not $Exit % 256;
if ($Exit) { print STDERR "Validation FAILED!!\n"; }
else { print "All files validated successfully.\n"; }
exit $Exit;
