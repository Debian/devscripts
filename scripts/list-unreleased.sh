#!/bin/bash

# Script searches for packages with pending changes (UNRELEASED) and
# either lists them or displays the relevant changelog entry.

# Usage: list-unreleased [-cR]
#        -c : display pending changes
#        -R : don't recurse

# Copyright: Frans Pop <elendil@planet.nl>, 2007
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.

PATHS=""
DO_CL=""
RECURSE=1

while true; do
	case "$1" in
	    "")
		break ;;
	    -c)
		DO_CL=1
		;;
	    -R)
		RECURSE=
		;;
	    -*)
		echo "unrecognized argument '$1'"
		exit 1
		;;
	    *)
		PATHS="${PATHS:+$PATHS }$1"
		;;
	esac
	shift
done

[ "$PATHS" ] || PATHS=.

vcs_dirs='(\.(svn|hg|git|bzr)|_darcs|_MTN|CVS)'
get_list() {
	local path="$1"

	for dir in $(
		if [ "$RECURSE" ]; then
			find "$path" -type d | egrep -v "$vcs_dirs"
		else
			find "$path" -maxdepth 1 -type d | egrep -v "$vcs_dirs"
		fi
	); do
		changelog="$dir/debian/changelog"
		if [ -f "$changelog" ] ; then
			if head -n1 "$changelog" | grep -q UNRELEASED; then
				echo $dir
			fi
		fi
	done | sort
}

print_cl() {
	local package="$1"
	changelog="$package/debian/changelog"

	# Check if more than one UNRELEASED entry at top of changelog
	Ucount=$(grep "^[^ ]" $changelog | \
		 head -n2 | grep -c UNRELEASED)
	if [ $Ucount -eq 1 ]; then
		sed -n "1,/^ --/p" $changelog
	else
		echo "ERROR: changelog has more than one UNRELEASED entry!"
		# Second sed is to add back a blank line between entries
		sed -n "/^[^ ].*UNRELEASED/,/^ --/p" $changelog | \
			sed '2,$s/^\([^ ]\)/\n\1/'
	fi
}

first=""
for path in $PATHS; do
	if [ -z "$DO_CL" ]; then
		echo "$(get_list "$path" | sed "s:^\./::")"
	else
		for package in $(get_list "$path"); do
			[ -z "$first" ] || echo -e "\n====================\n"
			first=1

			print_cl "$package"
		done
	fi
done
