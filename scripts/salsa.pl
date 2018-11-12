#!/usr/bin/perl

=head1 NAME

salsa - tool to manipulate salsa repositories and group members

=head1 SYNOPSIS

  # salsa <command> <args>
  salsa whoami
  salsa search_project devscripts
  salsa search_project qa/qa
  salsa search_group js-team
  salsa search_group perl-team/modules
  salsa search_user yadd
  salsa push_repo . --group js-team --kgb --irc devscripts --tagpending
  salsa update_repo node-mongodb --group js-team --disable-kgb --desc \
        --desc-pattern "Package %p"
  salsa update_repo js-team/node-mongodb --kgb --irc debian-js
  salsa update_safe --all --desc --desc-pattern "Debian package %p" \
        --group js-team
  salsa checkout node-mongodb --group js-team
  salsa checkout js-team/node-mongodb
  salsa add_user developer foobar --group-id 2665
  salsa update_user maintainer foobar --group js-team
  salsa del_user foobar --group js-team

=head1 DESCRIPTION

B<salsa> is a designed to create and configure repositories on
L<https://salsa.debian.org> and manage users of groups.

A Salsa token is required, except for search* commands, and must be set in
command line I<(see below)>, or in your configuration file I<(~/.devscripts)>:

  SALSA_TOKEN=abcdefghi

or

  SALSA_TOKEN=`cat ~/.token`

or

  SALSA_TOKEN_FILE=~/.dpt.conf

If you choose to link another file, it must contain a line with something like:

  <anything>SALSA_PRIVATE_TOKEN=xxxx
  <anything>SALSA_TOKEN=xxxx

=head1 COMMANDS

=head2 Managing users and groups

=over

=item B<add_user>

Add a user to a group.

  salsa --group js-group add_user guest foouser
  salsa --group-id 1234 add_user guest foouser
  salsa --group-id 1234 add_user maintainer 1245

First argument is the GitLab's access levels: guest, reporter, developer,
maintainer, owner.

=item B<del_user>

Remove a user from a group

  salsa --group js-team del_user foouser
  salsa --group-id=1234 del_user foouser

=item B<list_groups>

List sub groups of current one if group is set, groups of current user
else.

=item B<group>

Show group members.

  salsa --group js-team group
  salsa --group-id 1234 group

=item B<search_group>

Search for a group using given string. Shows group id and other
information.

  salsa search_group perl-team
  salsa search_group perl-team/modules
  salsa search_group 2666

=item B<search_user>

Search for a user using given string. Shows user id and other information.

  salsa search_user yadd

=item B<update_user>

Update user role in a group.

  salsa --group-id 1234 update_user guest foouser
  salsa --group js-team update_user maintainer 1245

First argument is the GitLab's access levels: guest, reporter, developer,
maintainer, owner.

=item B<whoami>

Gives information on the token owner

  salsa whoami

=back

=head2 Managing repositories

One of C<--group>, C<--group-id>, C<--user> or C<--user-id> is required to
manage repositories. If both are set, salsa warns and only
C<--user>/C<--user-id> is used. If none is given, salsa uses current user id
I<(token owner)>.

=over

=item B<check_repo>

Verify that repo(s) are well configured. It works exactly like B<update_repo>
except that it does not modify anything but just lists projects not well
configured with found errors.

  salsa --user yadd --tagpending --kgb --irc=devscripts check_repo test
  salsa --group js-team check_repo --all
  salsa --group js-team --rename-head check_repo test1 test2 test3

=item B<checkout> or B<co>

Clone repo in current dir. If directory already
exists, update local repo.

  salsa --user yadd co devscripts
  salsa --group js-team co node-mongodb
  salsa co js-team/node-mongodb

=item B<create_repo>

Create public empty project. If C<--group>/C<--group-id> is set, project is
created in group directory, else in user directory.

  salsa --user yadd create_repo test
  salsa --group js-team --kgb --irc-channel=devscripts create_repo test

=item B<del_repo>

Delete a repository.

=item B<fork>

Forks a project in group/user repository and set "upstream" to original
project. Example:

  $ salsa fork js-team/node-mongodb --verbose
  ...
  salsa.pl info: node-mongodb ready in node-mongodb/
  $ cd node-mongodb
  $ git remote --verbose show
  origin          git@salsa.debian.org:me/node-mongodb (fetch)
  origin          git@salsa.debian.org:me/node-mongodb (push)
  upstream        git@salsa.debian.org:js-team/node-mongodb (fetch)
  upstream        git@salsa.debian.org:js-team/node-mongodb (push)

For a group:

  salsa fork --group js-team user/node-foo

=item B<forks>

List forks of project(s).

  mysalsa forks qa/qa debian/devscripts

Project can be set using full path or using B<--group>/B<--group-id> or
B<--user>/B<--user-id>, else it is searched in current user namespace.

=item B<ls> or B<list_repos>

Shows project owned by user or group. If Second
argument exists, search only matching projects

  salsa --group js-team list_repos
  salsa --user yadd list_repos foo*

=item B<merge_request>, B<mr>

Creates a merge request.

Suppose you created a fork using B<salsa fork>, modify some things in a new
branch using one commit and want to propose it to original project
I<(branch "master")>. You just have to launch this in source directory:

  salsa mr

Other example:

  salsa mr --mr-dst-project debian/foo --mr-dst-branch debian/master

or simply

  salsa mr debian/foo debian/master

Note that unless destination project has been set using command line,
B<salsa merge_request> will search it in the following order:

=over 4

=item using GitLab API: salsa will detect from where this project was forked

=item using "upstream" origin

=item else salsa will use source project as destination project

=back

To force salsa to use source project as destination project, you can use
"same":

  salsa mr --mr-dst-project same
  # or
  salsa mr same

New merge request will be created using last commit title and description.

See B<--mr-*> options for more.

=item B<merge_requests>, B<mrs>

List opened merge requests for project(s)

  salsa mrs qa/qa debian/devscripts

Project can be set using full path or using B<--group>/B<--group-id> or
B<--user>/B<--user-id>, else it is searched in current user namespace.

=item B<protect_branch>

Protect/unprotect a branch.

=over

=item Set protection

  #                                    project      branch merge push
  salsa --group js-team protect_branch node-mongodb master m     d

"merge" and "push" can be one of:

=over

=item B<o>, B<owner>: owner only

=item B<m>, B<maintainer>: B<o> + maintainers allowed

=item B<d>, B<developer>: B<m> + developers allowed

=item B<r>, B<reporter>: B<d> + reporters allowed

=item B<g>, B<guest>: B<r> + guest allowed

=back

=item Unprotect

  salsa --group js-team protect_branch node-mongodb master no

=back

=item B<protected_branches>

List protected branches

  salsa --group js-team protected_branches node-mongodb

=item B<push_repo>

Create a new project from a local Debian source directory configured with
git.

B<push_repo> executes the following steps:

=over

=item gets project name using debian/changelog file;

=item lanches B<git remote add upstream ...>;

=item launches B<create_repo>;

=item pushes local repo.

=back

Examples:

  salsa --user yadd push_repo ./test
  salsa --group js-team --kgb --irc-channel=devscripts push_repo .

=item B<search>, B<search_project>, B<search_repo>

Search for a project using given string. Shows name, owner id and other
information.

  salsa search devscripts
  salsa search debian/devscripts
  salsa search 18475

=item B<update_repo>

Configure repo(s) using parameters given to command line.
A repo name has to be given unless B<--all> is set. Prefer to use
B<update_safe>.

  salsa --user yadd --tagpending --kgb --irc=devscripts update_repo test
  salsa --group js-team update_repo --all
  salsa --group js-team --rename-head update_repo test1 test2 test3
  salsa update_repo js-team/node-mongodb --kgb --irc debian-js

By default when using B<--all>, salsa will fail on first error. If you want
to continue, set B<--no-fail>. In this case, salsa will display a warning for
each project that has fail but continue with next project. Then to see full
errors, set B<--verbose>.

=item B<update_safe>

Launch B<check_repo> an ask before launching B<update_repo> (unless B<--yes>).

  salsa --user yadd --tagpending --kgb --irc=devscripts update_safe test
  salsa --group js-team update_safe --all
  salsa --group js-team --rename-head update_safe test1 test2 test3
  salsa update_safe js-team/node-mongodb --kgb --irc debian-js

=back

=head2 Other

=over

=item B<purge_cache>

Empty local cache.

=back

=head1 OPTIONS

=head2 General options

=over

=item B<-C>, B<--chdir>

Change directory before launching command

  salsa -C ~/debian co debian/libapache2-mod-fcgid

=item B<--cache-file>

File to store cached values. Default to B<~/.cache/salsa.json>. An empty value
disables cache.

C<.devscripts> value: B<SALSA_CACHE_FILE>

=item B<--no-cache>

Disable cache usage. Same as B<--cache-file ''>

=item B<--conffile>, B<--conf-file>

Add or replace default configuration files (C</etc/devscripts.conf> and
C<~/.devscripts>). This can only be used as the first option given on the
command-line.

=over

=item replace:

  salsa --conf-file test.conf <command>...
  salsa --conf-file test.conf --conf-file test2.conf  <command>...

=item add:

  salsa --conf-file +test.conf <command>...
  salsa --conf-file +test.conf --conf-file +test2.conf  <command>...

If one B<--conf-file> has no C<+>, default configuration files are ignored.

=back

=item B<--no-conf>, B<--noconf>

Don't read any configuration files. This can only be used as the first option
given on the command-line.

=item B<--debug>

Enable debugging output

=item B<--group>

Team to use. Use C<salsa search_group name> to find it.

C<.devscripts> value: B<SALSA_GROUP>

Be careful when you use B<SALSA_GROUP> in your C<.devscripts> file. Every
B<salsa> commands will be executed in group space, for example if you want to
propose a little change in a project using B<salsa fork> + B<salsa mr>, this
"fork" will be done in group space unless you set a B<--user>/B<--user-id>.
Prefer to use an alias in your C<.bashrc> file. Example:

  alias jsteam_admin="salsa --group js-team"

or

  alias jsteam_admin="salsa --conf-file ~/.js.conf

then you can fix B<SALSA_GROUP> in C<~/.js.conf>

=item B<--group-id>

Team id to use. Use C<salsa search_group name> to find it.

C<.devscripts> value: B<SALSA_GROUP_ID>

Be careful when you use B<SALSA_GROUP_ID> in your C<.devscripts> file. Every
B<salsa> commands will be executed in group space, for example if you want to
propose a little change in a project using B<salsa fork> + B<salsa mr>, this
"fork" will be done in group space unless you set a B<--user>/B<--user-id>.
Prefer to use an alias in your C<.bashrc> file. Example:

  alias jsteam_admin="salsa --group-id 2666"

or

  alias jsteam_admin="salsa --conf-file ~/.js.conf

then you can fix B<SALSA_GROUP_ID> in C<~/.js.conf>

=item B<--help>: displays this manpage

=item B<-i>, B<--info>

Prompt before sensible changes.

C<.devscripts> value: B<SALSA_INFO>

=item B<--path>

Repo path. Default to group or user path.

C<.devscripts> value: B<SALSA_REPO_PATH>

=item B<--token>

Token value (see above).

=item B<--token-file>

File to find token (see above).

=item B<--user>

Username to use. If neither B<--group>, B<--group-id>, B<--user> or B<--user-id>
is set, salsa uses current user id (corresponding to salsa private token).

=item B<--user-id>

User id to use. Use C<salsa search_user name> to find one. If neither
B<--group>, B<--group-id>, B<--user> or B<--user-id> is set, salsa uses current
user id (corresponding to salsa private token).

C<.devscripts> value: B<SALSA_USER_ID>

=item B<--verbose>

Enable verbose output.

=item B<--yes>

Never ask for consent.

C<.devscripts> value: B<SALSA_YES>

=back

=head2 Update/create repo options

=over

=item B<--all>

When set, all project of group/user are affected by command.

=over

=item B<--skip>: ignore project with B<--all>. Example:

  salsa update_repo --tagpending --all --skip qa --skip devscripts

C<.devscripts> value: B<SALSA_SKIP>. To set multiples values, use spaces.
Example

  SALSA_SKIP=qa devscripts

=item B<--skip-file>: ignore projects in this file (1 project per line)

  salsa update_repo --tagpending --all --skip-file ~/.skip

C<.devscripts> value: B<SALSA_SKIP_FILE>

=back

=item B<--desc> B<--no-desc>

Configure repo description using pattern given in B<desc-pattern>

C<.devscripts> value: B<SALSA_DESC>

=item B<--desc-pattern>

Repo description pattern. Default to "Debian package %p". "%p" is replaced by
repo name, while %P is replaced by repo name given in command (may contains
full path).

C<.devscripts> value: B<SALSA_DESC_PATTERN>

=item B<--enable-issues>, B<--no-enable-issues>, B<--disable-issues>,
B<--no-disable-issues>

Enable, ignore or disable issues.

C<.devscripts> values: B<SALSA_ENABLE_ISSUES>, B<SALSA_DISABLE_ISSUES>

=item B<--enable-mr>, B<--no-enable-mr>, B<--disable-mr>, B<--no-disable-mr>

Enable, ignore or disable merge requests.

C<.devscripts> values: B<SALSA_ENABLE_MR>, B<SALSA_DISABLE_MR>

=item B<--irc-channel>

IRC channel for KGB.

C<.devscript> value: B<SALSA_IRC_CHANNEL>

=item B<--kgb>, B<--no-kgb>, B<--disable-kgb>, <--no-disable-kgb>

Enable, ignore or disable KGB webhook.

C<.devscripts> value: B<SALSA_KGB>

=item B<--no-fail>

Don't stop on error when using B<update_repo> with B<--all>.

C<.devscripts> value: B<SALSA_NO_FAIL>

=item B<--rename-head>

Rename HEAD branch given by B<--source-branch> into B<--dest-branch> and change
"default branch" of project. Works only with B<update_repo>.

=over

=item B<--source-branch>: default "master"

C<.devscripts> value: B<SALSA_SOURCE_BRANCH>

=item B<--dest-branch>: default "debian/master"

C<.devscripts> value: B<SALSA_DEST_BRANCH>

=back

=item B<--tagpending>, B<--no-tagpending>, B<--disable-tagpending>,
B<--no-disable-tagpending>

Enable, ignore or disable "tagpending" webhook.

C<.devscripts> value: B<SALSA_TAGPENDING>

=back

=head2 Merge requests options

=over

=item B<--mr-title>

Title for merge request. Default: last commit title.

=item B<--mr-desc>

Description of new MR. Default:

=over

=item empty if B<--mr-title> is set

=item last commit description if any

=back

=item B<--mr-dst-branch> (or second command line argument)

Destination branch. Default to "master".

=item B<--mr-dst-project> (or first command line argument)

Destination project. Default: project from which the current project was
forked; or, if not found, "upstream" value found using
B<git remote --verbose show>; or using source project.

If B<--mr-dst-project> is set to B<same>, salsa will use source project as
destination.

=item B<--mr-src-branch>

Source branch. Default: current branch.

=item B<--mr-src-project>

Source project. Default: current project found using
B<git remote --verbose show>.

=item B<--mr-allow-squash>, B<--no-mr-allow-squash>

Allow upstream project to squash your commits, this is the default.

C<.devscripts> value: B<SALSA_MR_ALLOW_SQUASH>

=item B<--mr-remove-source-branch>, B<--no-mr-remove-source-branch>

Remove source branch if merge request is accepted. Default: no.

C<.devscripts> value: B<SALSA_MR_REMOVE_SOURCE_BRANCH>

=back

=head2 Options to manage other Gitlab instances

=over

=item B<--api-url>

GitLab API. Default: L<https://salsa.debian.org/api/v4>.

C<.devscripts> value: B<SALSA_API_URL>

=item B<--git-server-url>

Default to "git@salsa.debian.org:"

C<.devscripts> value: B<SALSA_GIT_SERVER_URL>

=item B<--kgb-server-url>

Default to L<http://kgb.debian.net:9418/webhook/?channel=>

C<.devscripts> value: B<SALSA_KGB_SERVER_URL>

=item B<--tagpending-server-url>

Default to L<https://webhook.salsa.debian.org/tagpending/>

C<.devscripts> value: B<SALSA_TAGPENDING_SERVER_URL>

=back

=head3 Configuration file example

Example to use salsa with L<https://gitlab.ow2.org> (group "lemonldap-ng"):

  SALSA_TOKEN=`cat ~/.ow2-gitlab-token`
  SALSA_API_URL=https://gitlab.ow2.org/api/v4
  SALSA_GIT_SERVER_URL=git@gitlab.ow2.org:
  SALSA_GROUP_ID=34

Then to use it, add something like this in your C<.bashrc> file:

  alias llng_admin='salsa --conffile ~/.salsa-ow2.conf'

=head1 SEE ALSO

B<dpt-salsa>

=head1 AUTHOR

Xavier Guimard E<lt>yadd@debian.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, Xavier Guimard E<lt>yadd@debian.orgE<gt>

It contains code formely found in L<dpt-salsa> I<(pkg-perl-tools)>
copyright 2018, gregor herrmann E<lt>gregoa@debian.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut

use Devscripts::Salsa;

exit Devscripts::Salsa->new->run;

