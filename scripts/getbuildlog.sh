#!/bin/sh
#
# getbuildlog: download package build logs from Debian auto-builders
#
# Copyright © 2008 Frank S. Thomas <fst@debian.org>
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
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

set -e

PROGNAME=`basename $0`

usage() {
    cat <<EOT
Usage: $PROGNAME <package> [<version-pattern>] [<architecture-pattern>]
  Downloads build logs of <package> from Debian auto-builders.
  If <version-pattern> or <architecture-pattern> are given, only build logs
  whose versions and architectures, respectively, matches the given patterns
  are downloaded.

  If <version-pattern> is "last" then only the logs for the most recent
  version of <package> found on buildd.debian.org will be downloaded.

  If <version-pattern> is "last-all" then the logs for the most recent
  version found on each build log index will be downloaded.
Options:
  -h, --help        Show this help message.
  -V, --version     Show version and copyright information.
Examples:
  # Download amd64 build log for hello version 2.2-1:
  $PROGNAME hello 2\.2-1 amd64

  # Download mips(el) build logs of all glibc versions:
  $PROGNAME glibc "" mips.*

  # Download all build logs of backported wesnoth versions:
  $PROGNAME wesnoth .*bpo.*
EOT
}

version() {
    cat <<EOT
This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2008 by Frank S. Thomas, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOT
}

[ "$1" = "-h" ] || [ "$1" = "--help" ] && usage && exit 0
[ "$1" = "-V" ] || [ "$1" = "--version" ] && version && exit 0

[ $# -ge 1 ] && [ $# -le 3 ] || { usage && exit 1; }

if ! which wget >/dev/null 2>&1; then
    echo "$PROGNAME: this program requires the wget package to be installed";
    exit 1
fi

PACKAGE=$1
VERSION=${2:-[:~+.[:alnum:]-]+}
ARCH=${3:-[[:alnum:]-]+}
ESCAPED_PACKAGE=`echo "$PACKAGE" | sed -e 's/\+/\\\+/g'`

GET_LAST_VERSION=no
if [ "$VERSION" = "last" ]; then
    GET_LAST_VERSION=yes
    VERSION=[:~+.[:alnum:]-]+
elif [ "$VERSION" = "last-all" ]; then
    GET_LAST_VERSION=all
    VERSION=[:~+.[:alnum:]-]+
fi

PATTERN="fetch\.(cgi|php)\?pkg=$ESCAPED_PACKAGE&arch=$ARCH&ver=$VERSION&\
stamp=[[:digit:]]+"

getbuildlog() {
    BASE=$1
    ALL_LOGS=`mktemp`

    trap "rm -f $ALL_LOGS" EXIT INT QUIT TERM

    wget -q -O $ALL_LOGS "$BASE/status/logs.php?pkg=$PACKAGE"

    # Put each href in $ALL_LOGS on a separate line so that $PATTERN
    # matches only one href. This is required because grep is greedy.
    sed -i -e "s/href=\"/\nhref=\"/g" $ALL_LOGS
    # Quick-and-dirty unescaping
    sed -i -e "s/&amp;/\&/g" -e "s/%2B/\+/g" -e "s/%3A/:/g" -e "s/%7E/~/g" $ALL_LOGS

    # If only the last version was requested, extract and sort
    # the listed versions and determine the highest
    if [ "$GET_LAST_VERSION" != "no" ]; then
	LASTVERSION=$( \
	    for match in `grep -E -o "$PATTERN" $ALL_LOGS`; do
		ver=${match##*ver=}
		echo ${ver%%&*}
	    done | perl -e '
		use lib "/usr/share/devscripts";
		use Devscripts::Versort;
		while (<>) { push @versions, [$_]; }
		@versions = Devscripts::Versort::versort(@versions);
		print $versions[0][0]; ' | sed -e "s/\+/\\\+/g"
	)

	NEWPATTERN="fetch\.(cgi|php)\?pkg=$ESCAPED_PACKAGE&\
arch=$ARCH&ver=$LASTVERSION&stamp=[[:digit:]]+"
    else
	NEWPATTERN=$PATTERN
    fi

    for match in `grep -E -o "$NEWPATTERN" $ALL_LOGS`; do
	ver=${match##*ver=}
	ver=${ver%%&*}
	arch=${match##*arch=}
	arch=${arch%%&*}
	match=`echo $match | sed -e 's/\+/%2B/g'`
        wget -O "${PACKAGE}_${ver}_${arch}.log" "$BASE/status/$match&raw=1"
    done

    rm -f $ALL_LOGS

    if [ "$GET_LAST_VERSION" = "yes" ]; then
	PATTERN=$NEWPATTERN
	GET_LAST_VERSION=no
    fi
}

getbuildlog http://buildd.debian.org
getbuildlog http://buildd.debian-ports.org
