#!/usr/bin/perl

# git-deborig -- try to produce Debian orig.tar using git-archive(1)

# Copyright (C) 2016-2017  Sean Whitton <spwhitton@spwhitton.name>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 NAME

git-deborig - try to produce Debian orig.tar using git-archive(1)

=head1 SYNOPSIS

B<git deborig> [B<-f>] [I<REF>]

=head1 DESCRIPTION

B<git-deborig> tries to produce the orig.tar you need for your upload
by calling git-archive(1) on an existing git tag or branch head.  It
was written with the dgit-maint-merge(7) workflow in mind, but can be
used with other workflows.

B<git-deborig> will try several common tag names.  If this fails, or
if more than one of those common tags are present, you can specify the
tag or branch head to archive on the command line (I<REF> above).

B<git-deborig> should be invoked from the root of the git repository,
which should contain I<debian/changelog>.

=head1 OPTIONS

=over 4

=item B<-f>

Overwrite any existing orig.tar in the parent directory.

=back

=head1 SEE ALSO

git-archive(1), dgit-maint-merge(7)

=head1 AUTHOR

B<git-deborig> was written by Sean Whitton <spwhitton@spwhitton.name>.

=cut

use strict;
use warnings;
no warnings "experimental::smartmatch";

use Git::Wrapper;
use Dpkg::Changelog::Parse;
use Dpkg::IPC;
use Dpkg::Version;
use List::Compare;

# Sanity check #1
die "pwd doesn't look like a Debian source package in a git repository ..\n"
  unless ( -d ".git" && -e "debian/changelog" );

# Process command line args
die "usage: git deborig [-f] [REF]\n"
  if ( scalar @ARGV >= 3 || (scalar @ARGV == 2 && !("-f" ~~ @ARGV)) );
my $overwrite = 0;
my $user_ref;
foreach my $arg ( @ARGV ) {
    if ( $arg eq "-f" ) {
        $overwrite = 1;
    } else {
        $user_ref = $arg;
    }
}

# Extract source package name and version from d/changelog
my $changelog = Dpkg::Changelog::Parse->changelog_parse({});
my $version = $changelog->{Version};
my $source = $changelog->{Source};
my $upstream_version = $version->version();

# Sanity check #2
die "this looks like a native package .." if $version->is_native();

# Default to gzip
my $compressor = "gzip -cn";
my $compression = "gz";
# Now check if we can use xz
if ( -e "debian/source/format" ) {
    open( my $format_fh, '<', "debian/source/format" )
      or die "couldn't open debian/source/format for reading";
    my $format = <$format_fh>;
    chomp($format) if defined $format;
    if ( $format eq "3.0 (quilt)" ) {
        $compressor = "xz -c";
        $compression = "xz";
    }
    close $format_fh;
}

my $orig = "../${source}_$upstream_version.orig.tar.$compression";
die "$orig already exists: not overwriting without -f\n"
  if ( -e $orig && ! $overwrite );

if ( defined $user_ref ) {      # User told us the tag/branch to archive
    # We leave it to git-archive(1) to determine whether or not this
    # ref exists; this keeps us forward-compatible
    archive_ref($user_ref);
} else {    # User didn't specify a tag/branch to archive
    # Get available git tags
    my $git = Git::Wrapper->new(".");
    my @all_tags = $git->tag();

    # convert according to DEP-14 rules
    my $git_upstream_version = $upstream_version;
    $git_upstream_version =~ y/:~/%_/;
    $git_upstream_version =~ s/\.(?=\.|$|lock$)/.#/g;

    # See which candidate version tags are present in the repo
    my @candidate_tags = ("$git_upstream_version",
                          "v$git_upstream_version",
                          "upstream/$git_upstream_version"
                         );
    my $lc = List::Compare->new(\@all_tags, \@candidate_tags);
    my @version_tags = $lc->get_intersection();

    # If there is only one candidate version tag, we're good to go.
    # Otherwise, let the user know they can tell us which one to use
    if ( scalar @version_tags > 1 ) {
        print "tags ", join(", ", @version_tags), " all exist in this repository\n";
        print "tell me which one you want to make an orig.tar from: git deborig TAG\n";
        exit 1;
    } elsif ( scalar @version_tags < 1 ) {
        print "couldn't find any of the following tags: ",
          join(", ", @candidate_tags), "\n";
        print "tell me a tag or branch head to make an orig.tar from: git deborig REF\n";
        exit 1;
    } else {
        my $tag = shift @version_tags;
        archive_ref($tag);
    }
}

sub archive_ref {
    my $ref = shift;

    # For compatibility with dgit, we have to override any
    # export-subst and export-ignore git attributes that might be set
    rename ".git/info/attributes", ".git/info/attributes-deborig"
      if ( -e ".git/info/attributes" );
    my $attributes_fh;
    unless ( open( $attributes_fh, '>', ".git/info/attributes" ) ) {
        rename ".git/info/attributes-deborig", ".git/info/attributes"
          if ( -e ".git/info/attributes-deborig" );
        die "could not open .git/info/attributes for writing";
    }
    print $attributes_fh "* -export-subst\n";
    print $attributes_fh "* -export-ignore\n";
    close $attributes_fh;

    spawn(exec => ['git', '-c', "tar.tar.${compression}.command=${compressor}",
                   'archive', "--prefix=${source}-${upstream_version}/",
                   '-o', $orig, $ref],
          wait_child => 1,
          nocheck => 1);

    # Restore situation before we messed around with git attributes
    if ( -e ".git/info/attributes-deborig" ) {
        rename ".git/info/attributes-deborig", ".git/info/attributes";
    } else {
        unlink ".git/info/attributes";
    }
}
