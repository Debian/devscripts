#!/usr/bin/perl
#
# mk-origtargz: Rename upstream tarball, optionally changing the compression
# and removing unwanted files.
# Copyright (C) 2014 Joachim Breitner <nomeata@debian.org>
# Copyright (C) 2015 James McCoy <jamessan@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


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
compression scheme and remove files according to B<Files-Excluded> and
B<Files-Excluded->I<component> in F<debian/copyright>. The resulting file is
placed in F<debian/../..>. (In F<debian/copyright>, the B<Files-Excluded> and
B<Files-Excluded->I<component> stanzas are a part of the first paragraph and
there is a blank line before the following paragraphs which contain B<Files>
and other stanzas.  See B<uscan>(1) "COPYRIGHT FILE EXAMPLE".)

The archive type for B<zip> is detected by "B<file --dereference --brief
--mime-type>" command.  So any B<zip> type archives such as B<jar> are treated
in the same way.  The B<xpi> archive is detected by its extension and is
handled properly using the B<xpi-unpack> command.

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

Use I<version> as the version of the package. This needs to be the upstream
version portion of a full Debian version, i.e. no Debian revision, no epoch.

The default is to use the upstream portion of the version of the first entry in
F<debian/changelog>.

=item B<--exclude-file> I<glob>

Remove files matching the given I<glob> from the tarball, as if it was listed in
B<Files-Excluded>.

=item B<--copyright-file> I<filename>

Remove files matching the patterns found in I<filename>, which should have the
format of a Debian F<copyright> file 
(B<Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/>
to be precise). Errors parsing that file are silently ignored, exactly as is
the case with F<debian/copyright>.

Unmatched patterns will emit a warning so the user can verify whether it is
correct.  If there are multiple patterns which match a file, only the last one
will count as being matched.

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

If the file has to be modified (because it is a B<zip>, or B<xpi> file, because
of B<--repack> or B<Files-Excluded>), this option behaves like B<--copy>.

=item B<--copy>

Make the resulting file a copy of the original file (unless it has to be
modified, of course).

=item B<--rename>

Rename the original file.

If the file has to be modified (because it is a B<zip>, or B<xpi> file, because
of B<--repack> or B<Files-Excluded>), this implies that the original file is
deleted afterwards.

=item B<--repack>

If the given file is not compressed using the desired format (see
B<--compression>), recompress it.

=item B<-S>, B<--repack-suffix> I<suffix>

If the file has to be modified, because of B<Files-Excluded>, append I<suffix>
to the upstream version.

=item B<-c>, B<--component> I<componentname>

Use <componentname> as the component name for the secondary upstream tarball.
Set I<componentname> as the component name.  This is used only for the 
secondary upstream tarball of the Debian source package.  
Then I<packagename_version.orig-componentname.tar.gz> is created.

=item B<--compression> [ B<gzip> | B<bzip2> | B<lzma> | B<xz> ]

If B<--repack> is used, or if the given file is a B<zip> or B<xpi> file, ensure
that the resulting file is compressed using the given scheme. The default is
B<gzip>.

=item B<-C>, B<--directory> I<directory>

Put the resulting file in the given directory.

=item B<--unzipopt> I<options>

Add the extra options to use with the B<unzip> command such as B<-a>, B<-aa>,
and B<-b>.

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
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use Pod::Usage;

use Dpkg::Changelog::Debian;
use Dpkg::IPC;
use Dpkg::Version;
use File::Spec;

use Devscripts::Compression qw/compression_is_supported compression_guess_from_file compression_get_property/;
use Cwd 'abs_path';
use File::Copy;
use Dpkg::Control::Hash;

sub decompress_archive($$);
sub compress_archive($$$);


my $package = undef;
my $version = undef;
my $component = undef;
my $orig="orig";
my $excludestanza="Files-Excluded";
my @exclude_globs = ();
my @copyright_files = ();

my $destdir = undef;
my $unzipopt = undef;
my $compression = "gzip";
my $mode = undef; # can be symlink, rename or copy. Can internally be repacked if the file was repacked.
my $repack = 0;
my $suffix = '';

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
    "component|c=s" => \$component,
    "exclude-file=s" => \@exclude_globs,
    "copyright-file=s" => \@copyright_files,
    "compression=s" => \$compression,
    "symlink" => \&setmode,
    "rename" => \&setmode,
    "copy" => \&setmode,
    "repack" => \$repack,
    'repack-suffix|S=s' => \$suffix,
    "directory|C=s" => \$destdir,
    "unzipopt=s" => \$unzipopt,
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

if (defined $component) {
    $orig="orig-$component";
    $excludestanza="Files-Excluded-$component";
}

if (@ARGV != 1) {
    die_opts "Please specify original tarball."
}
$upstream = $ARGV[0];

# get information from debian/

unless (defined $package) {
    # get package name
    my $c = Dpkg::Changelog::Debian->new(range => { count => 1 });
    $c->load('debian/changelog');
    if (my $msg = $c->get_parse_errors()) {
	die "could not parse debian/changelog:\n$msg";
    }
    my ($entry) = @{$c};
    $package = $entry->get_source();

    # get version number
    unless (defined $version) {
	my $debversion = Dpkg::Version->new($entry->get_version());
	# In the following line, use $debversion->is_native() as soon as
	# we need to depend on dpkg-dev >= 1.17.0 anyways
	if ($debversion->{no_revision}) {
	    print "Package with native version number $debversion; mk-origtargz makes no sense for native packages.\n";
	    exit 0;
	}
	$version = $debversion->version();
    }

    unshift @copyright_files, "debian/copyright" if -r "debian/copyright";

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
    my $okformat = qr'https?://www.debian.org/doc/packaging-manuals/copyright-format/[.\d]+';
    eval {
	$data->load($copyright_file);
	1;
    } or do {
	undef $data;
    };
    if (not -e $copyright_file) {
	die "File $copyright_file not found.";
    } elsif (   $data
	     && defined $data->{format}
	     && $data->{format} =~ m@^$okformat/?$@)
    {
	if ($data->{$excludestanza}) {
	    push(@exclude_globs, grep { $_ } split(/\s+/, $data->{$excludestanza}));
	}
    } else {
	open my $file, '<', $copyright_file or die "Unable to read $copyright_file: $!\n";
	while (my $line = <$file>) {
	    if ($line =~ m/\b${excludestanza}.*:/i) {
		warn "WARNING: The file $copyright_file mentions $excludestanza, but its ".
		     "format is not recognized. Specify Format: ".
		     "https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/ ".
		     "in order to remove files from the tarball with mk-origtargz.\n";
		last;
	    }
	}
	close $file;
    }
}


# Gather information about the upstream file.

# This makes more sense in Dpkg:Compression
my $tar_regex = qr/\.(tar\.gz   |tgz
		     |tar\.bz2  |tbz2?
		     |tar\.lzma |tlz(?:ma?)?
		     |tar\.xz   |txz
		     |tar\.Z
		     )$/x;

unless (-e $upstream) {
    die "Could not read $upstream: $!"
}

my $mime = compression_guess_from_file($upstream);

my $is_zipfile = (defined $mime and $mime eq 'zip');
my $is_tarfile = $upstream =~ $tar_regex;
my $is_xpifile = $upstream =~ /\.xpi$/i;

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
my $destfilebase = sprintf "%s_%s.%s.tar", $package, $version, $orig;
my $destfiletar = sprintf "%s/%s", $destdir, $destfilebase;
my $destext = compression_get_property($compression, "file_ext");
my $destfile = sprintf "%s.%s", $destfiletar, $destext;


# $upstream_tar is $upstream, unless the latter was a zip file.
my $upstream_tar = $upstream;

# Remember this for the final report
my $zipfile_deleted = 0;

# If the file is a zipfile, we need to create a tarfile from it.
if ($is_zipfile) {
    if ($is_xpifile) {
	system('command -v xpi-unpack >/dev/null 2>&1') >> 8 == 0
	    or die("xpi-unpack binary not found. You need to install the package mozilla-devscripts to be able to repack .xpi upstream archives.\n");
    } else {
	system('command -v unzip >/dev/null 2>&1') >> 8 == 0
	    or die("unzip binary not found. You need to install the package unzip to be able to repack .zip upstream archives.\n");
    }

    my $tempdir = tempdir ("uscanXXXX", TMPDIR => 1, CLEANUP => 1);
    # Parent of the target directory should be under our control
    $tempdir .= '/repack';
    my @cmd;
    if ($is_xpifile) {
	@cmd = ('xpi-unpack', $upstream_tar, $tempdir);
	system(@cmd) >> 8 == 0
	    or die("Repacking from xpi failed (could not xpi-unpack)\n");
    } else {
	mkdir $tempdir or die("Unable to mkdir($tempdir): $!\n");
	@cmd = ('unzip', '-q');
	push @cmd, split ' ', $unzipopt if defined $unzipopt;
	push @cmd, ('-d', $tempdir, $upstream_tar);
	system(@cmd) >> 8 == 0
	    or die("Repacking from zip or jar failed (could not unzip)\n");
    }

    # Figure out the top-level contents of the tarball.
    # If we'd pass "." to tar we'd get the same contents, but the filenames would
    # start with ./, which is confusing later.
    # This should also be more reliable than, say, changing directories and globbing.
    opendir(TMPDIR, $tempdir) || die("Can't open $tempdir $!\n");
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
	die("Repacking from zip or jar to tar.$destext failed (could not create tarball)\n");
    }
    compress_archive($destfiletar, $destfile, $compression);

    # rename means the user did not want this file to exist afterwards
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
	die("Cannot determine compression method of $upstream_tar");
    }
    $do_repack = $comp ne $compression;
}

# Removing files
my $deletecount = 0;
my @to_delete;

if (@exclude_globs) {
    my @files;
    my $files;
    spawn(exec => ['tar', '-t', '-a', '-f', $upstream_tar],
	  to_string => \$files,
	  wait_child => 1);
    @files = split /^/, $files;
    chomp @files;

    my %delete;
    # find out what to delete
    my @exclude_info = map { { glob => $_, used => 0, regex => glob_to_regex($_) } } @exclude_globs;
    for my $filename (@files) {
	my $last_match;
	for my $info (@exclude_info) {
	    if ($filename =~ m@^(?:[^/]*/)?        # Possible leading directory, ignore it
				(?:$info->{regex}) # User pattern
				(?:/.*)?$          # Possible trailing / for a directory
			      @x) {
		$delete{$filename} = 1 if !$last_match;
		$last_match = $info;
	    }
	}
	if (defined $last_match) {
	    $last_match->{used} = 1;
	}
    }

    for my $info (@exclude_info) {
	if (!$info->{used}) {
	    warn "No files matched excluded pattern as the last matching glob: $info->{glob}\n";
	}
    }

    # ensure files are mentioned before the directory they live in
    # (otherwise tar complains)
    @to_delete = sort {$b cmp $a} keys %delete;

    $deletecount = scalar(@to_delete);
}

if ($deletecount) {
    $destfilebase = sprintf "%s_%s%s.%s.tar", $package, $version, $suffix, $orig;
    $destfiletar = sprintf "%s/%s", $destdir, $destfilebase;
    $destfile = sprintf "%s.%s", $destfiletar, $destext;

    # Zip -> tar process already created $destfile, so need to rename it
    if ($is_zipfile) {
	move $upstream_tar, $destfile;
	$upstream_tar = $destfile;
    }
}

# Actually do the unpack, remove, pack cycle
if ($do_repack || $deletecount) {
    decompress_archive($upstream_tar, $destfiletar);
    unlink $upstream_tar if $mode eq "rename";
    # We have to use piping because --delete is broken otherwise, as documented
    # at https://www.gnu.org/software/tar/manual/html_node/delete.html
    if (@to_delete) {
	spawn(exec => ['tar', '--delete', @to_delete ],
	      from_file => $destfiletar,
	      to_file => $destfiletar . ".tmp",
	      wait_child => 1) if scalar(@to_delete) > 0;
	move ($destfiletar . ".tmp", $destfiletar);
    }
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

# Final check: Is the tarball usable

# We are lazy and rely on Dpkg::IPC to report an error message (spawn does not report back the error code).
# We don't expect this to occur often anyways.
my $ret = spawn(exec => ['tar', '--list', '--auto-compress', '--file', $destfile ],
      wait_child => 1,
      to_file => '/dev/null');

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
	die("Cannot determine compression method of $from_file");
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

# Adapted from Text::Glob::glob_to_regex_string
sub glob_to_regex {
    my ($glob) = @_;

    if ($glob =~ m@/$@) {
	warn "WARNING: Files-Excluded pattern ($glob) should not have a trailing /\n";
	chop($glob);
    }
    if ($glob =~ m/(?<!\\)(?:\\{2})*\\(?![\\*?])/) {
	die "Invalid Files-Excluded pattern ($glob), \\ can only escape \\, *, or ? characters\n";
    }

    my ($regex, $escaping);
    for my $c ($glob =~ m/(.)/gs) {
	if ($c eq '.' || $c eq '(' || $c eq ')' || $c eq '|' ||
	    $c eq '+' || $c eq '^' || $c eq '$' || $c eq '@' || $c eq '%' ||
	    $c eq '{' || $c eq '}' || $c eq '[' || $c eq ']' ||
	    # Escape '#' since we're using /x in the pattern match
	    $c eq '#') {
	    $regex .= "\\$c";
	}
	elsif ($c eq '*') {
	    $regex .= $escaping ? "\\*" : ".*";
	}
	elsif ($c eq '?') {
	    $regex .= $escaping ? "\\?" : ".";
	}
	elsif ($c eq "\\") {
	    if ($escaping) {
		$regex .= "\\\\";
		$escaping = 0;
	    }
	    else {
		$escaping = 1;
	    }
	    next;
	}
	else {
	    $regex .= $c;
	    $escaping = 0;
	}
	$escaping = 0;
    }

    return $regex;
}
