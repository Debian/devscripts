#!/bin/bash -e
# whodepends - show maintainers a package depends upon
# by Moshe Zadka <moshez@debian.org> and
# modified by Joshua Kwan <joshk@triplehelix.org>
# This script is in the public domain.

PROGNAME=`basename $0`

usage () {
	cat <<EOF
Usage: $PROGNAME [package] [package] ... [options]
  Check which maintainers a particular package depends on.
  $PROGNAME options:
    --source, -s      Show source packages instead of binary ones.
    --help, -h        Show this help screen.
    --version         Show version and copyright information.
EOF
}

version () {
	cat <<EOF
This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is by Moshe Zadka <moshez@debian.org>, and is in the public domain.
EOF
}

if [ -z "$1" ]; then
	usage
	exit 1
fi

while [ -n "$1" ]; do
	case "$1" in
		-s | --source) source=true ;;
		-h | --help) usage; exit 0 ;;
		--version) version; exit 0 ;;
		*)
			echo "Dependent maintainers for $1:"
			for package in `apt-cache showpkg $1 | sed -n '/Reverse Depends:/,/Dependencies/p' | grep '^ '|sed 's/,.*//'`; do
				if [ $source ]; then
					apt-cache showsrc $package |
					awk '/^Maintainer:/ {maint=$0} /^Package:/ {pkg=$0} END {print maint, pkg}' |
					sed 's/Maintainer: //;s/Package: //'
				else
					apt-cache show $package |
					awk '/^Maintainer:/ {maint=$0} END {print maint, "'$package'"}' |
					sed 's/Maintainer: //'
				fi
			done | sort -u | awk -F'>' '{ pack[$1]=pack[$1] $2 } END {for (val in pack) print val ">", "(" pack[val] ")"}' | sed 's/( /(/'
			echo
		;;
	esac
	shift
done
