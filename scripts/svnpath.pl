#!/usr/bin/perl

=head1 NAME

svnpath - output svn url with support for tags and branches

=head1 SYNOPSIS

B<svnpath>

B<svnpath tags>

B<svnpath branches>

B<svnpath trunk>

=head1 DESCRIPTION

B<svnpath> is intended to be run in a Subversion working copy.

In its simplest usage, B<svnpath> with no parameters outputs the svn url for
the repository associated with the working copy.

If a parameter is given, B<svnpath> attempts to instead output the url that
would be used for the tags, branches, or trunk. This will only work if it's
run in the top-level directory that is subject to tagging or branching.

For example, if you want to tag what's checked into Subversion as version
1.0, you could use a command like this:

  svn cp $(svnpath) $(svnpath tags)/1.0

That's much easier than using svn info to look up the repository url and
manually modifying it to derive the url to use for the tag, and typing in
something like this:

  svn cp svn+ssh://my.server.example/svn/project/trunk svn+ssh://my.server.example/svn/project/tags/1.0

svnpath uses a simple heuristic to convert between the trunk, tags, and
branches paths. It replaces the first occurrence of B<trunk>, B<tags>, or
B<branches> with the name of what you're looking for. This will work ok for
most typical Subversion repository layouts.

If you have an atypical layout and it does not work, you can add a
F<~/.svnpath> file. This file is perl code, which can modify the path in $url.
For example, the author uses this file:

 #!/usr/bin/perl
 # svnpath personal override file

 # For d-i I sometimes work from a full d-i tree branch. Remove that from
 # the path to get regular tags or branches directories.
 $url=~s!d-i/(rc|beta)[0-9]+/!!;
 $url=~s!d-i/sarge/!!;
 1

=cut

$ENV{LANG}="C";

my $wanted=shift;
my $path=shift;

if (length $path) {
	chdir $path || die "$path: unreadable\n";
}

our $url = `svn info . 2>/dev/null|grep -i ^URL: | cut -d ' ' -f 2`;
if (! length $url) {
	# Try svk instead.
	$url = `svk info .| grep -i '^Depot Path:' | cut -d ' ' -f 3`;
}

if (! length $url) {
	die "cannot get url";
}

if (length $wanted) {
	# Now jut substitute into it.
	$url=~s!/(?:trunk|branches|tags)($|/)!/$wanted$1!;

	if (-e "$ENV{HOME}/.svnpath") {
		require "$ENV{HOME}/.svnpath";
	}
}

print $url;

=head1 LICENSE

GPL version 2 or later

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut
