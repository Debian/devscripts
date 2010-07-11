#!/bin/bash -e

####################
#    Copyright (C) 2007, 2008 by Raphael Geissert <atomo64@gmail.com>
#
#    This file is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This file is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this file  If not, see <http://www.gnu.org/licenses/>.
#
#    On Debian systems, the complete text of the GNU General
#    Public License 3 can be found in '/usr/share/common-licenses/GPL-3'.
####################

PROGNAME=$(basename "$0")

usage () {
    echo \
"Usage: $PROGNAME [options] FILE.diff.gz
  Options:
    --help          Show this message
    --version       Show version and copyright information
  debian/control must exist on the current path for this script to work
  If debian/patches exists and is a directory, patches are extracted there,
  otherwise they are extracted under debian/ (unless the environment variable
  DEB_PATCHES is defined and points to a valid directory, in which case
  patches are extracted there)."
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2007, 2008 by Raphael Geissert, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 3 or later."
}

case "$1" in
	--help) usage; exit 0 ;;
	--version) version; exit 0 ;;
esac

if ! which lsdiff >/dev/null 2>&1; then
	echo "lsdiff was not found in \$PATH, package patchutils probably not installed!"
	exit 1
fi

diffgz="$1"

if [ ! -f "$diffgz" ]; then
	[ -z "$diffgz" ] && diffgz="an unspecified .diff.gz"
	echo "Couldn't find $diffgz, aborting!"
	exit 1
fi

if [ -x /usr/bin/dh_testdir ]; then
	/usr/bin/dh_testdir || exit 1
else
	[ ! -f debian/control ] && echo "Couldn't find debian/control!" && exit 1
fi

if [ -z "$DEB_PATCHES" ] || [ ! -d "$DEB_PATCHES" ]; then
	DEB_PATCHES=debian
	[ -d debian/patches ] && DEB_PATCHES=debian/patches
else
	DEB_PATCHES="$(readlink -f "$DEB_PATCHES")"
fi

echo "Patches will be extracted under $DEB_PATCHES/"

FILES=$(zcat "$diffgz" | lsdiff --strip 1 | egrep -v ^debian/) || \
	echo "$(basename "$diffgz") doesn't contain any patch outside debian/"

for file in $FILES; do
	[ ! -z "$file" ] || continue
	echo -n "Extracting $file..."
	newFileName="$DEB_PATCHES/$(echo "$file" | sed 's#/#___#g').patch"
	zcat "$diffgz" | filterdiff -i "$file" -p1 > "$newFileName"
	echo "done"
done

exit
