
=head1 NAME

Devscripts::Uscan::FindFiles - watchfile finder

=head1 SYNOPSIS

  use Devscripts::Uscan::Config;
  use Devscripts::Uscan::FindFiles;
  
  # Get config
  my $config = Devscripts::Uscan::Config->new->parse;
  
  # Search watchfiles
  my @wf = find_watch_files($config);

=head1 DESCRIPTION

This package exports B<find_watch_files()> function. This function search
Debian watchfiles following configuration parameters.

=head1 SEE ALSO

L<uscan>, L<Devscripts::Uscan::WatchFile>, L<Devscripts::Uscan::Config>

=head1 AUTHOR

B<uscan> was originally written by Christoph Lameter
E<lt>clameter@debian.orgE<gt> (I believe), modified by Julian Gilbey
E<lt>jdg@debian.orgE<gt>. HTTP support was added by Piotr Roszatycki
E<lt>dexter@debian.orgE<gt>. B<uscan> was rewritten in Perl by Julian Gilbey.
Xavier Guimard E<lt>yadd@debian.orgE<gt> rewrote uscan in object
oriented Perl.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2006 by Julian Gilbey <jdg@debian.org>,
2018 by Xavier Guimard <yadd@debian.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut

package Devscripts::Uscan::FindFiles;

use strict;
use filetest 'access';
use Cwd qw/cwd/;
use Exporter 'import';
use Devscripts::Uscan::Output;
use Devscripts::Versort;
use Dpkg::Changelog::Parse qw(changelog_parse);
use File::Basename;

our @EXPORT = ('find_watch_files');

sub find_watch_files {
    my ($config) = @_;
    my $opwd = cwd();

    # when --watchfile is used
    if (defined $config->watchfile) {
        uscan_verbose "Option --watchfile=$config->{watchfile} used";
        my ($config) = (@_);

        # no directory traversing then, and things are very simple
        if (defined $config->package) {

            # no need to even look for a changelog!
            return (
                ['.', $config->package, $config->uversion, $config->watchfile]
            );
        } else {
            # Check for debian/changelog file
            until (-r 'debian/changelog') {
                chdir '..' or uscan_die "can't chdir ..: $!";
                if (cwd() eq '/') {
                    uscan_die "Are you in the source code tree?\n"
                      . "   Cannot find readable debian/changelog anywhere!";
                }
            }

            my ($package, $debversion, $uversion)
              = scan_changelog($config, $opwd, 1);

            return ([cwd(), $package, $uversion, $config->watchfile]);
        }
    }

    # when --watchfile is not used, scan watch files
    push @ARGV, '.' if !@ARGV;
    {
        local $, = ',';
        uscan_verbose "Scan watch files in @ARGV";
    }

    # Run find to find the directories.  We will handle filenames with spaces
    # correctly, which makes this code a little messier than it would be
    # otherwise.
    my @dirs;
    open FIND, '-|', 'find', @ARGV, qw(-follow -type d -name debian -print)
      or uscan_die "Couldn't exec find: $!";

    while (<FIND>) {
        chomp;
        push @dirs, $_;
        uscan_debug "Found $_";
    }
    close FIND;

    uscan_die "No debian directories found" unless @dirs;

    my @debdirs = ();

    my $origdir = cwd;
    for my $dir (@dirs) {
        $dir =~ s%/debian$%%;

        unless (chdir $origdir) {
            uscan_warn "Couldn't chdir back to $origdir, skipping: $!";
            next;
        }
        unless (chdir $dir) {
            uscan_warn "Couldn't chdir $dir, skipping: $!";
            next;
        }

        uscan_verbose "Check debian/watch and debian/changelog in $dir";

        # Check for debian/watch file
        if (-r 'debian/watch') {
            unless (-r 'debian/changelog') {
                uscan_warn
                  "Problems reading debian/changelog in $dir, skipping";
                next;
            }
            my ($package, $debversion, $uversion)
              = scan_changelog($config, $opwd);
            next unless ($package);

            uscan_verbose
              "package=\"$package\" version=\"$uversion\" (no epoch/revision)";
            push @debdirs, [$debversion, $dir, $package, $uversion];
        }
    }

    uscan_warn "No watch file found" unless @debdirs;

    # Was there a --upstream-version option?
    if (defined $config->uversion) {
        if (@debdirs == 1) {
            $debdirs[0][3] = $config->uversion;
        } else {
            uscan_warn
"ignoring --upstream-version as more than one debian/watch file found";
        }
    }

    # Now sort the list of directories, so that we process the most recent
    # directories first, as determined by the package version numbers
    @debdirs = Devscripts::Versort::deb_versort(@debdirs);

    # Now process the watch files in order.  If a directory d has
    # subdirectories d/sd1/debian and d/sd2/debian, which each contain watch
    # files corresponding to the same package, then we only process the watch
    # file in the package with the latest version number.
    my %donepkgs;
    my @results;
    for my $debdir (@debdirs) {
        shift @$debdir;    # don't need the Debian version number any longer
        my $dir       = $$debdir[0];
        my $parentdir = dirname($dir);
        my $package   = $$debdir[1];
        my $version   = $$debdir[2];

        if (exists $donepkgs{$parentdir}{$package}) {
            uscan_warn
"Skipping $dir/debian/watch\n   as this package has already been found";
            next;
        }

        unless (chdir $origdir) {
            uscan_warn "Couldn't chdir back to $origdir, skipping: $!";
            next;
        }
        unless (chdir $dir) {
            uscan_warn "Couldn't chdir $dir, skipping: $!";
            next;
        }

        uscan_verbose
"$dir/debian/changelog sets package=\"$package\" version=\"$version\"";
        push @results, [$dir, $package, $version, "debian/watch", cwd];
    }
    unless (chdir $origdir) {
        uscan_die "Couldn't chdir back to $origdir! $!";
    }
    return @results;
}

sub scan_changelog {
    my ($config, $opwd, $die) = @_;
    my $out
      = $die
      ? sub { uscan_die(@_) }
      : sub { uscan_warn($_[0] . ', skipping') };

    # Figure out package info we need
    my $changelog = eval { changelog_parse(); };
    if ($@) {
        return $out->("Problems parsing debian/changelog:");
    }

    my ($package, $debversion, $uversion);
    $package = $changelog->{Source};
    return $out->("Problem determining the package name from debian/changelog")
      unless defined $package;
    $debversion = $changelog->{Version};
    return $out->("Problem determining the version from debian/changelog")
      unless defined $debversion;
    uscan_verbose
"package=\"$package\" version=\"$debversion\" (as seen in debian/changelog)";

    # Check the directory is properly named for safety
    if ($config->check_dirname_level == 2
        or ($config->check_dirname_level == 1 and cwd() ne $opwd)) {
        my $good_dirname;
        my $re = $config->check_dirname_regex;
        $re =~ s/PACKAGE/\Q$package\E/g;
        if ($re =~ m%/%) {
            $good_dirname = (cwd() =~ m%^$re$%);
        } else {
            $good_dirname = (basename(cwd()) =~ m%^$re$%);
        }
        return $out->("The directory name "
              . basename(cwd())
              . " doesn't match the requirement of\n"
              . "   --check_dirname_level=$config->{check_dirname_level} --check-dirname-regex=$re .\n"
              . "   Set --check-dirname-level=0 to disable this sanity check feature."
        ) unless defined $good_dirname;
    }

    # Get current upstream version number
    if (defined $config->uversion) {
        $uversion = $config->uversion;
    } else {
        $uversion = $debversion;
        $uversion =~ s/-[^-]+$//;    # revision
        $uversion =~ s/^\d+://;      # epoch
    }
    return ($package, $debversion, $uversion);
}
1;
