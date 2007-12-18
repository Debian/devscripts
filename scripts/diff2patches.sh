#!/bin/sh

####################
#    Copyright (C) 2007 by Raphael Geissert <atomo64@gmail.com>
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
####################

set -e

if [ -z "$1" ]; then
	echo "Usage: $0 FILE.diff.gz"
	echo "debian/control must exist on the current path"
	echo "If debian/patches exists and is a directory, patches are extracted there"
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "Couldn't find $1!"
	exit 1
fi

if [ -x /usr/bin/dh_testdir ]; then
	/usr/bin/dh_testdir || exit 1
else
	[ ! -f debian/control ] && echo "Couldn't find debian/control!" && exit 1
fi

DEB_PATCHES=debian
[ -d debian/patches ] && DEB_PATCHES=debian/patches
echo "Patches will be extracted under $DEB_PATCHES/"

FILES=`zcat "$1" | lsdiff --strip 1 | egrep -v ^debian/`

for f in $FILES; do
	[ ! -z "$f" ] || continue
	echo -n "Extracting $f..."
	NF="$DEB_PATCHES/`echo "$f" | sed 's#/#___#g'`.patch"
	zcat "$1" | filterdiff -i "$f" -p1 > $NF
	echo "done"
done

exit 0
