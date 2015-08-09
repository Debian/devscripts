#!/bin/bash
#
# Copyright 2006-2008 (C) Kees Cook <kees@ubuntu.com>
# Modified by Siegfried-A. Gevatter <rainct@ubuntu.com>
# Modified by Daniel Hahler <ubuntu@thequod.de>
#
# ##################################################################
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# See file /usr/share/common-licenses/GPL for more details.
#
# ##################################################################
#
# By default only the name of the patch system is printed.  Verbose mode can be
# enabled with -v.

if [ "$1" = "-h" ] || [ "$1" = "--help" ]
then
	cat <<EOM
Usage: $0 [-v]

Run this inside the source directory of a Debian package and it will detect
the patch system that it uses.

 -v: Enable verbose mode:
     - Print a list of all those files outside the debian/ directory that have
       been modified (if any).
     - Report additional details about patch systems, if available.
EOM
	exit 0
fi

while [ ! -r debian/rules ];
do
	if [ "$PWD" = "/" ]; then
		echo "Can't find debian/rules."
		exit 1
	fi
	cd ..
done

VERBOSE=0
if [ "$1" = "-v" ]
then
	VERBOSE=1
fi

if [ "$VERBOSE" -gt 0 ]; then
	files=`lsdiff -z ../$(dpkg-parsechangelog -SSource)_$(dpkg-parsechangelog -SVersion).diff.gz 2>/dev/null | grep -v 'debian/'`
	if [ -n "$files" ]
	then
		echo "Following files were modified outside of the debian/ directory:"
		echo "$files"
		echo "--------------------"
		echo
		echo -n "Patch System: "
	fi
fi

if fgrep -q quilt debian/source/format 2>/dev/null; then
	echo "quilt"
	exit 0
fi

# Do not change the output of existing checks by default, as there are build
# tools that rely on the exisitng output.  If changes in reporting is needed,
# please check the "VERBOSE" flag (see below for examples).  Feel free
# to add new patchsystem detection and reporting.
for filename in $(echo "debian/rules"; grep ^include debian/rules | fgrep -v '$(' | awk '{print $2}')
do
	fgrep patchsys.mk "$filename" | grep -q -v "^#" && {
		if [ "$VERBOSE" -eq 0 ]; then
			echo "cdbs"; exit 0;
		else
			echo "cdbs (patchsys.mk: see 'cdbs-edit-patch')"; exit 0;
		fi
	}
	fgrep quilt "$filename" | grep -q -v "^#" && { echo "quilt"; exit 0; }
	fgrep dbs-build.mk "$filename" | grep -q -v "^#" && {
		if [ "$VERBOSE" -eq 0 ]; then
			echo "dbs"; exit 0;
		else
			echo "dbs (see 'dbs-edit-patch')"; exit 0;
		fi
	}
	fgrep dpatch "$filename" | grep -q -v "^#" && {
		if [ "$VERBOSE" -eq 0 ]; then
			echo "dpatch"; exit 0;
		else
			echo "dpatch (see 'patch-edit-patch')"; exit 0;
		fi
	}
	fgrep '*.diff' "$filename" | grep -q -v "^#" && {
		if [ "$VERBOSE" -eq 0 ]; then
			echo "diff splash"; exit 0;
		else
			echo "diff splash (check debian/rules)"; exit 0;
		fi
	}
done
[ -d debian/patches ] || {
	if [ "$VERBOSE" -eq 0 ]; then
		echo "patchless?"; exit 0;
	else
		echo "patchless? (did not find debian/patches/)"; exit 0;
	fi
}
if [ "$VERBOSE" -eq 0 ]; then
	echo "unknown patch system"
else
	echo "unknown patch system (see debian/patches/ and debian/rules)"
fi
