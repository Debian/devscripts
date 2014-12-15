#!/bin/bash

# Output arch (tla/Bazaar) archive names, with support for branches

# Copyright (C) 2005 Colin Watson <cjwatson@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

# Which arch implementation should we use?
if type baz >/dev/null 2>&1; then
	PROGRAM=baz
else
	PROGRAM=tla
fi

WANTED="$1"
ME="$($PROGRAM tree-version)"

if [ "$WANTED" ]; then
	ARCHIVE="$($PROGRAM parse-package-name --arch "$ME")"
	CATEGORY="$($PROGRAM parse-package-name --category "$ME")"
	case $WANTED in
		*--*)
			echo "$ARCHIVE/$CATEGORY--$WANTED"
			;;
		*)
			VERSION="$($PROGRAM parse-package-name --vsn "$ME")"
			echo "$ARCHIVE/$CATEGORY--$WANTED--$VERSION"
			;;
	esac
else
	echo "$ME"
fi
