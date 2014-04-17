#!/usr/bin/perl
#
# mk-origtargz: Rename upstream tarball, optionally changing the compression
# and removing unwanted files.
# Copyright (C) 2014 Joachim Breitner <nomeata@debian.org>
#
# It contains code formerly found in uscan.
# Copyright (C) 2002-2006, Julian Gilbey
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


=head1 NAME

mk-origtargz - rename upstream tarball, optionally changing the compression and removing unwanted files

=head1 SYNOPSIS

=over

=item B<mk-origtargz> [I<options>] F<foo-1.0.tar.gz>

=item B<mk-origtargz> B<--help>

=back

=head1 DESCRIPTION

B<mk-origtargz> renames the given file to match what is expected by
B<dpkg-buildpackage>, based on the source package name and version in
F<debian/changelog>. It can convert B<zip> to B<tar>, optionally change the
compression scheme and remove files according to B<Files-Excluded> in
F<debian/copyright>. The resulting file is placed in F<debian/../..>.

If the package name is given via the B<--package> option, no information is
read from F<debian/>, and the result file is placed in the current directory.

B<mk-origtargz> is commonly called via B<uscan>, which first obtains the
upstream tarball.

=head1 OPTIONS

=head2 Metadata options

The following options extend or replace information taken from F<debian/>.

=over

=item B<--package> I<package>

Use I<package> as the name of the Debian source package, and do not require or
use a F<debian/> directory. This option can only be used together with
B<--version>.

The default is to use the package name of the first entry in F<debian/changelog>.

=item B<-v>, B<--version> I<version>

Use I<version> as the version of the package. This needs to be the upstream version portion of a full Debian version, i.e. no Debian revision, no epoch.

The default is to use the upstream portion of the version of the first entry in F<debian/changelog>.

=item B<--exclude-file> I<glob>

Remove files matching the given I<glob> from the tarball, as if it was listed in
B<Files-Excluded>.

=item B<--copyright-file> I<filename>

Remove files matching the patterns found in I<filename>, which should have the format of a Debian F<copyright> file. Errors parsing that file are silently ignored, exactly as it is the case with F<debian/copyright>.

Both the B<--exclude-file> and B<--copyright-file> options amend the list of
patterns found in F<debian/copyright>. If you do not want to read that file,
you will have to use B<--package>.

=back

=head2 Action options

These options specify what exactly B<mk-origtargz> should do. The options
B<--copy>, B<--rename> and B<--symlink> are mutually exclusive.

=over

=item B<--symlink>

Make the resulting file a symlink to the given original file. (This is the
default behaviour.)

If the file has to be modified (because it is a B<zip> file, because of
B<--repack> or B<Files-Excluded>), this option behaves like B<--copy>.

=item B<--copy>

Make the resulting file a copy of the original file (unless it has to be modified, of course).

=item B<--rename>

Rename the original file.

If the file has to be modified (because it is a B<zip> file, because of B<--repack> or B<Files-Excluded>), this implies that the original file is deleted afterwards.

=item B<--repack>

If the given file is not in compressed using the desired format (see
B<--compression>), recompress it.

=item B<--compression> [ B<gzip> | B<bzip2> | B<lzma> | B<xz> ]

If B<--repack> is used, or if the given file is a B<zip> file, ensure that the resulting file is compressed using the given scheme. The default is B<gzip>.

=item B<-C>, B<--directory> I<directory>

Put the resulting file in the given directory.

=back

=cut

#=head1 CONFIGURATION VARIABLES
#
#The two configuration files F</etc/devscripts.conf> and
#F<~/.devscripts> are sourced by a shell in that order to set
#configuration variables. Command line options can be used to override
#configuration file settings. Environment variable settings are ignored
#for this purpose. The currently recognised variables are:

=head1 SEE ALSO

B<uscan>(1), B<uupdate>(1)

=head1 AUTHOR

B<mk-origtargz> and this manpage have been written by Joachim Breitner
<I<nomeata@debian.org>>.

=cut


use strict;
use warnings;
use File::Temp qw/tempdir/;
use Getopt::Long qw(:config gnu_getopt);
use Pod::Usage;

use Dpkg::IPC;
use File::Spec;
use File::Temp qw/tempfile/;

BEGIN { push(@INC, '/usr/share/devscripts') } # append to @INC, so that -I . has precedence
use Devscripts::Compression qw/compression_is_supported compression_guess_from_file compression_get_property/;
use Cwd 'abs_path';
use File::Copy;
use Dpkg::Control::Hash;

BEGIN {
    eval { require Text::Glob; };
    if ($@) {
        my $progname = basename($0);
        if ($@ =~ /^Can\'t locate Text\/Glob\.pm/) {
            die "$progname: you must have the libtext-glob-perl package installed\nto use this script\n";
        } else {
            die "$progname: problem loading the Text::Glob module:\n  $@\nHave you installed the libtext-glob-perl package?\n";
        }
    }
}


sub decompress_archive($$);
sub compress_archive($$$);


my $package = undef;
my $version = undef;
my @exclude_globs = ();
my @copyright_files = ();

my $destdir = undef;
my $compression = "gzip";
my $mode = undef; # can be symlink, rename or copy. Can internally be repacked if the file was repacked.
my $repack = 0;

my $upstream = undef;

# option parsing

sub die_opts ($) {
	pod2usage({-exitval => 3, -verbose => 1, -msg => shift @_});
}

sub setmode {
	my $newmode = shift @_;
	if (defined $mode and $mode ne $newmode) {
		die_opts (sprintf "--%s and --%s are mutually exclusive", $mode, $newmode);
	}
	$mode = $newmode;
}

GetOptions(
	"package=s" => \$package,
	"version|v=s" => \$version,
	"exclude-file=s" => \@exclude_globs,
	"copyright-file=s" => \@copyright_files,
	"compression=s" => \$compression,
	"symlink" => \&setmode,
	"rename" => \&setmode,
	"copy" => \&setmode,
	"repack" => \$repack,
	"directory|C=s" => \$destdir,
	"help|h" => sub { pod2usage({-exitval => 0, -verbose => 1}); },
) or pod2usage({-exitval => 3, -verbose=>1});

$mode ||= "symlink";

# sanity checks
unless (compression_is_supported($compression)) {
	die_opts (sprintf "Unknown compression scheme %s", $compression);
}

if (defined $package and not defined $version) {
	die_opts "If you use --package, you also have to specify --version."
}

if (@ARGV != 1) {
	die_opts "Please specify original tarball."
}
$upstream = $ARGV[0];

# get information from debian/

unless (defined $package) {
	# get package name
	open F, "debian/changelog" or die "debian/changelog: $!\n";
	my $line = <F>;
	close F;
	unless ($line =~ /^(\S+) \((\S+)\)/) {
		die "could not parse debian/changelog:1: $line";
	}
	$package = $1;

	# get version number
	unless (defined $version) {
		$version = $2;
		unless ($version =~ /-/) {
			print "Package with native version number $version; mk-origtargz makes no sense for native packages.\n";
			exit 0;
		}
		$version =~ s/(.*)-.*/$1/; # strip everything from the last dash
		$version =~ s/^\d+://; # strip epoch
	}

	unshift @copyright_files, "debian/copyright";

	# set destination directory
	unless (defined $destdir) {
		$destdir = "..";
	}
} else {
	unless (defined $destdir) {
		$destdir = ".";
	}
}

for my $copyright_file (@copyright_files) {
	# get files-excluded
	my $data = Dpkg::Control::Hash->new();
	my $okformat = qr'http://www.debian.org/doc/packaging-manuals/copyright-format/[.\d]+';
        eval {
		$data->load($copyright_file);
		1;
        } or do {
		undef $data;
        };
        if (   $data
            && defined $data->{'format'}
            && $data->{'format'} =~ m{^$okformat/?$}
            && $data->{'files-excluded'})
        {
		my @rawexcluded = ($data->{"files-excluded"} =~ /(?:\A|\G\s+)((?:\\.|[^\\\s])+)/g);
		# un-escape
		push @exclude_globs, map { s/\\(.)/$1/g; s?/+$??; $_ } @rawexcluded;
	 }
}


# Gather information about the upstream file.

my $zip_regex = qr/\.(zip|jar)$/;
# This makes more sense in Dpkg:Compression
my $tar_regex = qr/\.(tar\.gz  |tgz
                     |tar\.bz2 |tbz2?
                     |tar.lzma |tlz(?:ma?)?
                     |tar.xz   |txz)$/x;

my $is_zipfile = $upstream =~ $zip_regex;
my $is_tarfile = $upstream =~ $tar_regex;

unless (-e $upstream) {
	die "Could not read $upstream: $!"
}

unless ($is_zipfile or $is_tarfile) {
	# TODO: Should we ignore the name and only look at what file knows?
	die "Parameter $upstream does not look like a tar archive or a zip file."
}

if ($is_tarfile and not $repack) {
	# If we are not explicitly repacking, but need to generate a file
	# (usually due to Files-Excluded), then we want to use the original
	# compression scheme.
	$compression = compression_guess_from_file ($upstream);

	if (not defined $compression) {
		die "Unknown or no compression used in $upstream."
	}
}


# Now we know what the final filename will be
my $destfilebase = sprintf "%s_%s.orig.tar", $package, $version;
my $destfiletar = sprintf "%s/%s", $destdir, $destfilebase;
my $suffix = compression_get_property($compression, "file_ext");
my $destfile = sprintf "%s.%s", $destfiletar, $suffix;


# $upstream_tar is $upstream, unless the latter was a zip file.
my $upstream_tar = $upstream;

# Remember this for the final report
my $zipfile_deleted = 0;

# If the file is a zipfile, we need to create a tarfile from it.
if ($is_zipfile) {
	system('command -v unzip >/dev/null 2>&1') >> 8 == 0
		or die("unzip binary not found. You need to install the package unzip to be able to repack .zip upstream archives.\n");

        my $tempdir = tempdir ("uscanXXXX", TMPDIR => 1, CLEANUP => 1);
        # Parent of the target directory should be under our control
        $tempdir .= '/repack';
        mkdir $tempdir or uscan_die("Unable to mkdir($tempdir): $!\n");
        system('unzip', '-q', '-a', '-d', $tempdir, $upstream_tar) == 0
            or uscan_die("Repacking from zip or jar failed (could not unzip)\n");

        # Figure out the top-level contents of the tarball.
        # If we'd pass "." to tar we'd get the same contents, but the filenames would
        # start with ./, which is confusing later.
        # This should also be more reliable than, say, changing directories and globbing.
        opendir(TMPDIR, $tempdir) || uscan_die("Can't open $tempdir $!\n");
        my @files = grep {$_ ne "." && $_ ne ".."} readdir(TMPDIR);
        close TMPDIR;


        # tar it all up
        spawn(exec => ['tar',
		'--owner=root', '--group=root', '--mode=a+rX',
		'--create', '--file', "$destfiletar",
		'--directory', $tempdir,
		@files],
              wait_child => 1);
        unless (-e "$destfiletar") {
            uscan_die("Repacking from zip or jar to tar.$suffix failed (could not create tarball)\n");
        }
        compress_archive($destfiletar, $destfile, $compression);

	# rename means the user did not want this file to exit afterwards
	if ($mode eq "rename") {
		unlink $upstream_tar;
		$zipfile_deleted++;
	}

	$mode = "repack";
	$upstream_tar = $destfile;
}

# From now on, $upstream_tar is guaranteed to be a compressed tarball. It is always
# a full (possibly relative) path, and distinct from $destfile.

# Find out if we have to repack
my $do_repack = 0;
if ($repack) {
	my $comp = compression_guess_from_file($upstream_tar);
        unless ($comp) {
           uscan_die("Cannot determine compression method of $upstream_tar");
        }
	$do_repack = $comp ne $compression;

}

# Removing files
my $deletecount = 0;
my @to_delete;

if (scalar @exclude_globs > 0) {
	my @files;
	my $files;
	spawn(exec => ['tar', '-t', '-a', '-f', $upstream_tar],
	      to_string => \$files,
	      wait_child => 1);
	@files = split /^/, $files;
	chomp @files;

	# find out what to delete
	{
		no warnings 'once';
		$Text::Glob::strict_leading_dot = 0;
		$Text::Glob::strict_wildcard_slash = 0;
	}
	for my $filename (@files) {
		my $do_exclude = 0;
		for my $exclude (@exclude_globs) {
			$do_exclude ||=
				Text::Glob::match_glob("$exclude",     $filename) ||
				Text::Glob::match_glob("$exclude/",    $filename) ||
				Text::Glob::match_glob("*/$exclude",   $filename) ||
				Text::Glob::match_glob("*/$exclude/",  $filename);
		}
		push @to_delete, $filename if $do_exclude;
	}

	# ensure files are mentioned before the directory they live in
	# (otherwise tar complains)
	@to_delete = sort {$b cmp $a}  @to_delete;

	$deletecount = scalar(@to_delete);
}

# Actually do the unpack, remove, pack cycle
if ($do_repack || $deletecount) {
	decompress_archive($upstream_tar, $destfiletar);
	unlink $upstream_tar if $mode eq "rename";
	spawn(exec => ['tar', '--delete', '--file', $destfiletar, @to_delete ]
		,wait_child => 1) if scalar(@to_delete) > 0;
	compress_archive($destfiletar, $destfile, $compression);

	# Symlink no longer makes sense
	$mode = "repack";
	$upstream_tar = $destfile;
}

# Final step: symlink, copy or rename.

my $same_name = abs_path($destfile) eq abs_path($upstream);
unless ($same_name) {
	if ($mode ne "repack") { die "Assertion failed" unless $upstream_tar eq $upstream; }

	if ($mode eq "symlink") {
		my $rel = File::Spec->abs2rel( $upstream_tar, $destdir );
		symlink $rel, $destfile;
	} elsif ($mode eq "copy") {
		copy $upstream_tar, $destfile;
	} elsif ($mode eq "rename") {
		move $upstream_tar, $destfile;
	}
}

# Tell the use what we did

my $upstream_nice = File::Spec->canonpath($upstream);
my $destfile_nice = File::Spec->canonpath($destfile);

if ($same_name) {
	print "Leaving $destfile_nice where it is";
} else {
	if ($is_zipfile or $do_repack or $deletecount) {
		print "Successfully repacked $upstream_nice as $destfile_nice";
	} elsif ($mode eq "symlink") {
		print "Successfully symlinked $upstream_nice to $destfile_nice";
	} elsif ($mode eq "copy") {
		print "Successfully copied $upstream_nice to $destfile_nice";
	} elsif ($mode eq "rename") {
		print "Successfully renamed $upstream_nice to $destfile_nice";
	} else {
		die "Unknown mode $mode."
	}
}

if ($deletecount) {
	print ", deleting ${deletecount} files from it";
}
if ($zipfile_deleted) {
	print ", and removed the original file"
}
print ".\n";

exit 0;

sub decompress_archive($$) {
    my ($from_file, $to_file) = @_;
    my $comp = compression_guess_from_file($from_file);
    unless ($comp) {
       uscan_die("Cannot determine compression method of $from_file");
    }

    my $cmd = compression_get_property($comp, 'decomp_prog');
    spawn(exec => $cmd,
        from_file => $from_file,
        to_file => $to_file,
        wait_child => 1);
}

sub compress_archive($$$) {
    my ($from_file, $to_file, $comp) = @_;

    my $cmd = compression_get_property($comp, 'comp_prog');
    push(@{$cmd}, '-'.compression_get_property($comp, 'default_level'));
    spawn(exec => $cmd,
        from_file => $from_file,
        to_file => $to_file,
        wait_child => 1);
    unlink $from_file;
}
