package Devscripts::MkOrigtargz;

use strict;
use Cwd 'abs_path';
use Devscripts::Compression
  qw/compression_guess_from_file compression_get_property/;
use Devscripts::MkOrigtargz::Config;
use Devscripts::Output;
use Devscripts::Utils;
use Dpkg::Changelog::Debian;
use Dpkg::Control::Hash;
use Dpkg::IPC;
use Dpkg::Version;
use File::Copy;
use File::Spec;
use File::Temp qw/tempdir/;
use File::Which;
use Moo;

# regexp-assemble << END
# tar\.gz
# tgz
# tar\.bz2
# tbz2?
# tar\.lzma
# tlz(?:ma?)?
# tar\.xz
# txz
# tar\.Z
# END
use constant tar_regex =>
  qr/t(?:ar\.(?:[gx]z|lzma|bz2|Z)|lz(?:ma?)?|[gx]z|bz2?)/;

has config => (
    is      => 'rw',
    default => sub {
        Devscripts::MkOrigtargz::Config->new->parse;
    },
);

has exclude_globs => (
    is      => 'rw',
    lazy    => 1,
    default => sub { $_[0]->config->exclude_file },
);

has status => (is => 'rw', default => sub { 0 });
has destfile_nice => (is => 'rw');

sub do {
    my ($self) = @_;
    $self->parse_copyrights or $self->make_orig_targz;
    return $self->status;
}

sub make_orig_targz {
    my ($self) = @_;
    my $mime = compression_guess_from_file($self->config->upstream);

    my $is_zipfile = (defined $mime and $mime eq 'zip');
    my $is_tarfile = $self->config->upstream =~ tar_regex;
    my $is_xpifile = $self->config->upstream =~ /\.xpi$/i;

    unless ($is_zipfile or $is_tarfile) {
        # TODO: Should we ignore the name and only look at what file knows?
        ds_die 'Parameter '
          . $self->config->upstream
          . ' does not look like a tar archive or a zip file.';
        return $self->status(1);
    }

    if ($is_tarfile and not $self->config->repack) {
        # If we are not explicitly repacking, but need to generate a file
        # (usually due to Files-Excluded), then we want to use the original
        # compression scheme.
        $self->config->compression(
            compression_guess_from_file($self->config->upstream))
          unless (defined $self->config->compression);

        if (not defined $self->config->compression) {
            ds_die
              "Unknown or no compression used in $self->config->upstream.";
            return $self->status(1);
        }
    }
    $self->config->compression(
        &Devscripts::MkOrigtargz::Config::default_compression)
      unless (defined $self->config->compression);

    # Now we know what the final filename will be
    my $destfilebase = sprintf "%s_%s.%s.tar", $self->config->package,
      $self->config->version, $self->config->orig;
    my $destfiletar = sprintf "%s/%s", $self->config->directory, $destfilebase;
    my $destext
      = compression_get_property($self->config->compression, "file_ext");
    my $destfile = sprintf "%s.%s", $destfiletar, $destext;

    # $upstream_tar is $upstream, unless the latter was a zip file.
    my $upstream_tar = $self->config->upstream;

    # Remember this for the final report
    my $zipfile_deleted = 0;

    # If the file is a zipfile, we need to create a tarfile from it.
    if ($is_zipfile) {
        if ($self->config->signature) {
            $self->config->signature(4);    # repack upstream file
        }
        if ($is_xpifile) {
            unless (which 'xpi-unpack') {
                ds_die( "xpi-unpack binary not found."
                      . " You need to install the package mozilla-devscripts"
                      . " to be able to repack .xpi upstream archives.\n");
                return $self->status(1);
            }
        } else {
            unless (which 'unzip') {
                ds_die( "unzip binary not found."
                      . " You need to install the package unzip"
                      . " to be able to repack .zip upstream archives.\n");
                return $self->status(1);
            }
        }

        my $tempdir = tempdir("uscanXXXX", TMPDIR => 1, CLEANUP => 1);
        # Parent of the target directory should be under our control
        $tempdir .= '/repack';
        my @cmd;
        if ($is_xpifile) {
            @cmd = ('xpi-unpack', $upstream_tar, $tempdir);
            unless (ds_exec_no_fail(@cmd) >> 8 == 0) {
                ds_die("Repacking from xpi failed (could not xpi-unpack)\n");
                return $self->status(1);
            }
        } else {
            unless (mkdir $tempdir) {
                ds_die("Unable to mkdir($tempdir): $!\n");
                return $self->status(1);
            }
            @cmd = ('unzip', '-q');
            push @cmd, split ' ', $self->config->unzipopt
              if defined $self->config->unzipopt;
            push @cmd, ('-d', $tempdir, $upstream_tar);
            unless (ds_exec_no_fail(@cmd) >> 8 == 0) {
                ds_die("Repacking from zip or jar failed (could not unzip)\n");
                return $self->status(1);
            }
        }

# Figure out the top-level contents of the tarball.
# If we'd pass "." to tar we'd get the same contents, but the filenames would
# start with ./, which is confusing later.
# This should also be more reliable than, say, changing directories and globbing.
        unless (opendir(TMPDIR, $tempdir)) {
            ds_die("Can't open $tempdir $!\n");
            return $self->status(1);
        }
        my @files = grep { $_ ne "." && $_ ne ".." } readdir(TMPDIR);
        close TMPDIR;

        # tar it all up
        spawn(
            exec => [
                'tar',          '--owner=root',
                '--group=root', '--mode=a+rX',
                '--create',     '--file',
                "$destfiletar", '--directory',
                $tempdir,       @files
            ],
            wait_child => 1
        );
        unless (-e "$destfiletar") {
            ds_die(
"Repacking from zip or jar to tar.$destext failed (could not create tarball)\n"
            );
            return $self->status(1);
        }
        eval {
            compress_archive($destfiletar, $destfile,
                $self->config->compression);
        };
        return $self->status(1) if ($@);

        # rename means the user did not want this file to exist afterwards
        if ($self->config->mode eq "rename") {
            unlink $upstream_tar;
            $zipfile_deleted++;
        }

        $self->config->mode('repack');
        $upstream_tar = $destfile;
    }

# From now on, $upstream_tar is guaranteed to be a compressed tarball. It is always
# a full (possibly relative) path, and distinct from $destfile.

    # Find out if we have to repack
    my $do_repack = 0;
    if ($self->config->repack) {
        my $comp = compression_guess_from_file($upstream_tar);
        unless ($comp) {
            ds_die("Cannot determine compression method of $upstream_tar");
            return $self->status(1);
        }
        $do_repack = $comp ne $self->config->compression;
    }

    # Removing files
    my $deletecount = 0;
    my @to_delete;

    if (@{ $self->exclude_globs }) {
        my @files;
        my $files;
        spawn(
            exec       => ['tar', '-t', '-a', '-f', $upstream_tar],
            to_string  => \$files,
            wait_child => 1
        );
        @files = split /^/, $files;
        chomp @files;

        my %delete;
        # find out what to delete
        my @exclude_info;
        eval {
            @exclude_info
              = map { { glob => $_, used => 0, regex => glob_to_regex($_) } }
              @{ $self->exclude_globs };
        };
        return $self->status(1) if ($@);
        for my $filename (@files) {
            my $last_match;
            for my $info (@exclude_info) {
                if (
                    $filename
                    =~ m@^(?:[^/]*/)? # Possible leading directory, ignore it
				(?:$info->{regex}) # User pattern
				(?:/.*)?$          # Possible trailing / for a directory
			      @x
                ) {
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
                ds_warn
"No files matched excluded pattern as the last matching glob: $info->{glob}\n";
            }
        }

        # ensure files are mentioned before the directory they live in
        # (otherwise tar complains)
        @to_delete = sort { $b cmp $a } keys %delete;

        $deletecount = scalar(@to_delete);
    }

    if ($deletecount) {
        $destfilebase = sprintf "%s_%s%s.%s.tar", $self->config->package,
          $self->config->version, $self->config->repack_suffix,
          $self->config->orig;
        $destfiletar = sprintf "%s/%s", $self->config->directory,
          $destfilebase;
        $destfile = sprintf "%s.%s", $destfiletar, $destext;

        # Zip -> tar process already created $destfile, so need to rename it
        if ($is_zipfile) {
            move($upstream_tar, $destfile);
            $upstream_tar = $destfile;
        }
    }

    # Actually do the unpack, remove, pack cycle
    if ($do_repack || $deletecount) {
        if ($self->config->signature) {
            $self->config->signature(4);    # repack upstream file
        }
        eval { decompress_archive($upstream_tar, $destfiletar) };
        return $self->status(1) if ($@);
        unlink $upstream_tar if $self->config->mode eq "rename";
    # We have to use piping because --delete is broken otherwise, as documented
    # at https://www.gnu.org/software/tar/manual/html_node/delete.html
        if (@to_delete) {
            # ARG_MAX: max number of bytes exec() can handle
            my $arg_max;
            spawn(
                exec       => ['getconf', 'ARG_MAX'],
                to_string  => \$arg_max,
                wait_child => 1
            );
            # Under Hurd `getconf` above returns "undefined".
            # It's apparently unlimited (?), so we just use a arbitrary number.
            if ($arg_max =~ /\D/) { $arg_max = 131072; }
            # Usually NAME_MAX=255, but here we use 128 to be on the safe side.
            $arg_max = int($arg_max / 128);
          # We use this lame splice on a totally arbitrary $arg_max because
          # counting how many bytes there are in @to_delete is too inefficient.
            while (my @next_n = splice @to_delete, 0, $arg_max) {
                spawn(
                    exec       => ['tar', '--delete', @next_n],
                    from_file  => $destfiletar,
                    to_file    => $destfiletar . ".tmp",
                    wait_child => 1
                ) if scalar(@next_n) > 0;
                move($destfiletar . ".tmp", $destfiletar);
            }
        }
        eval {
            compress_archive($destfiletar, $destfile,
                $self->config->compression);
        };
        return $self->status(1) if ($@);

        # Symlink no longer makes sense
        $self->config->mode('repack');
        $upstream_tar = $destfile;
    }

    # Final step: symlink, copy or rename for tarball.

    my $same_name = abs_path($destfile) eq abs_path($self->config->upstream);
    unless ($same_name) {
        if (    $self->config->mode ne "repack"
            and $upstream_tar ne $self->config->upstream) {
            ds_die "Assertion failed";
            return $self->status(1);
        }

        if ($self->config->mode eq "symlink") {
            my $rel
              = File::Spec->abs2rel($upstream_tar, $self->config->directory);
            symlink $rel, $destfile;
        } elsif ($self->config->mode eq "copy") {
            copy($upstream_tar, $destfile);
        } elsif ($self->config->mode eq "rename") {
            move($upstream_tar, $destfile);
        }
    }

    # Final step: symlink, copy or rename for signature file.

    my $is_ascfile = $self->config->signature_file =~ /\.asc$/i;
    my $is_gpgfile = $self->config->signature_file =~ /\.(gpg|pgp|sig|sign)$/i;

    my $destsigfile;
    if ($self->config->signature == 1) {
        $destsigfile = sprintf "%s.asc", $destfile;
    } elsif ($self->config->signature == 2) {
        $destsigfile = sprintf "%s.asc", $destfiletar;
    } elsif ($self->config->signature == 3) {
        # XXX FIXME XXX place holder
        $destsigfile = sprintf "%s.asc", $destfile;
    } else {
        # $self->config->signature == 0 or 4
        $destsigfile = "";
    }

    if ($self->config->signature == 1 or $self->config->signature == 2) {
        if ($is_gpgfile) {
            my $enarmor
              = `gpg --output - --enarmor $self->{config}->{signature_file} 2>&1`;
            unless ($? == 0) {
                ds_die
"mk-origtargz: Failed to convert $self->{config}->{signature_file} to *.asc\n";
                return $self->status(1);
            }
            $enarmor =~ s/ARMORED FILE/SIGNATURE/;
            $enarmor =~ /^Comment:/d;
            unless (open(DESTSIG, ">> $destsigfile")) {
                ds_die
                  "mk-origtargz: Failed to open $destsigfile for append: $!\n";
                return $self->status(1);
            }
            print DESTSIG $enarmor;
        } else {
            if (abs_path($self->config->signature_file) ne
                abs_path($destsigfile)) {
                if ($self->config->mode eq "symlink") {
                    my $rel = File::Spec->abs2rel(
                        $self->config->signature_file,
                        $self->config->directory
                    );
                    symlink $rel, $destsigfile;
                } elsif ($self->config->mode eq "copy") {
                    copy($self->config->signature_file, $destsigfile);
                } elsif ($self->config->mode eq "rename") {
                    move($self->config->signature_file, $destsigfile);
                } else {
                    ds_die 'Strange mode="' . $self->config->mode . "\"\n";
                    return $self->status(1);
                }
            }
        }
    } elsif ($self->config->signature == 3) {
        print
"Skip adding upstream signature since upstream file has non-detached signature file.\n";
    } elsif ($self->config->signature == 4) {
        print
          "Skip adding upstream signature since upstream file is repacked.\n";
    }

    # Final check: Is the tarball usable

# We are lazy and rely on Dpkg::IPC to report an error message (spawn does not report back the error code).
# We don't expect this to occur often anyways.
    my $ret = spawn(
        exec => ['tar', '--list', '--auto-compress', '--file', $destfile],
        wait_child => 1,
        to_file    => '/dev/null'
    );

    # Tell the user what we did

    my $upstream_nice = File::Spec->canonpath($self->config->upstream);
    my $destfile_nice = File::Spec->canonpath($destfile);
    $self->destfile_nice($destfile_nice);

    if ($same_name) {
        print "Leaving $destfile_nice where it is";
    } else {
        if ($is_zipfile or $do_repack or $deletecount) {
            print "Successfully repacked $upstream_nice as $destfile_nice";
        } elsif ($self->config->mode eq "symlink") {
            print "Successfully symlinked $upstream_nice to $destfile_nice";
        } elsif ($self->config->mode eq "copy") {
            print "Successfully copied $upstream_nice to $destfile_nice";
        } elsif ($self->config->mode eq "rename") {
            print "Successfully renamed $upstream_nice to $destfile_nice";
        } else {
            ds_die 'Unknown mode ' . $self->config->mode;
            return $self->status(1);
        }
    }

    if ($deletecount) {
        print ", deleting ${deletecount} files from it";
    }
    if ($zipfile_deleted) {
        print ", and removed the original file";
    }
    print ".\n";
    return 0;
}

sub decompress_archive {
    my ($from_file, $to_file) = @_;
    my $comp = compression_guess_from_file($from_file);
    unless ($comp) {
        die("Cannot determine compression method of $from_file");
    }

    my $cmd = compression_get_property($comp, 'decomp_prog');
    spawn(
        exec       => $cmd,
        from_file  => $from_file,
        to_file    => $to_file,
        wait_child => 1
    );
}

sub compress_archive {
    my ($from_file, $to_file, $comp) = @_;

    my $cmd = compression_get_property($comp, 'comp_prog');
    push(@{$cmd}, '-' . compression_get_property($comp, 'default_level'));
    spawn(
        exec       => $cmd,
        from_file  => $from_file,
        to_file    => $to_file,
        wait_child => 1
    );
    unlink $from_file;
}

# Adapted from Text::Glob::glob_to_regex_string
sub glob_to_regex {
    my ($glob) = @_;

    if ($glob =~ m@/$@) {
        ds_warn
          "Files-Excluded pattern ($glob) should not have a trailing /\n";
        chop($glob);
    }
    if ($glob =~ m/(?<!\\)(?:\\{2})*\\(?![\\*?])/) {
        die
"Invalid Files-Excluded pattern ($glob), \\ can only escape \\, *, or ? characters\n";
    }

    my ($regex, $escaping);
    for my $c ($glob =~ m/(.)/gs) {
        if (
               $c eq '.'
            || $c eq '('
            || $c eq ')'
            || $c eq '|'
            || $c eq '+'
            || $c eq '^'
            || $c eq '$'
            || $c eq '@'
            || $c eq '%'
            || $c eq '{'
            || $c eq '}'
            || $c eq '['
            || $c eq ']'
            ||
            # Escape '#' since we're using /x in the pattern match
            $c eq '#'
        ) {
            $regex .= "\\$c";
        } elsif ($c eq '*') {
            $regex .= $escaping ? "\\*" : ".*";
        } elsif ($c eq '?') {
            $regex .= $escaping ? "\\?" : ".";
        } elsif ($c eq "\\") {
            if ($escaping) {
                $regex .= "\\\\";
                $escaping = 0;
            } else {
                $escaping = 1;
            }
            next;
        } else {
            $regex .= $c;
            $escaping = 0;
        }
        $escaping = 0;
    }

    return $regex;
}

sub parse_copyrights {
    my ($self) = @_;
    for my $copyright_file (@{ $self->config->copyright_file }) {
        my $data = Dpkg::Control::Hash->new();
        my $okformat
          = qr'https?://www.debian.org/doc/packaging-manuals/copyright-format/[.\d]+';
        eval {
            $data->load($copyright_file);
            1;
        } or do {
            undef $data;
        };
        if (not -e $copyright_file) {
            ds_die "File $copyright_file not found.";
            return $self->status(1);
        } elsif ($data
            && defined $data->{format}
            && $data->{format} =~ m@^$okformat/?$@) {
            if ($data->{ $self->config->excludestanza }) {
                push(
                    @{ $self->exclude_globs },
                    grep { $_ }
                      split(/\s+/, $data->{ $self->config->excludestanza }));
            }
        } else {
            if (open my $file, '<', $copyright_file) {
                while (my $line = <$file>) {
                    if ($line =~ m/\b$self->{config}->{excludestanza}.*:/i) {
                        ds_warn "The file $copyright_file mentions "
                          . $self->config->excludestanza
                          . ", but its "
                          . "format is not recognized. Specify Format: "
                          . "https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/ "
                          . "in order to remove files from the tarball with mk-origtargz.\n";
                        last;
                    }
                }
                close $file;
            } else {
                ds_die "Unable to read $copyright_file: $!\n";
                return $self->status(1);
            }
        }
    }
}

1;
