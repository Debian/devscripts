#!/bin/sh -e
#
# Copyright 2005 Branden Robinson
# Changes copyright 2007 by their respective authors
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

usage() {
    cat <<EOF
Usage: manpage-alert [options] [paths]
  Options:
    -h, --help          This usage screen.
    -V, --version       Display the version and copyright information.
    -f, --file          Show filenames of missing manpages
                        without any leading text.
    -p, --package       Show filenames of missing manpages
                        with their package name.
    -n, --no-stat       Do not show statistics at the end.

  This script will locate executables in the given paths with manpage
  outputs for which no manpage is available and its statictics.

  If no paths are specified on the command line, "/bin /sbin /usr/bin
  /usr/sbin /usr/games" will be used by default.
EOF
}

version() {
    cat <<EOF
This is manpage-alert, from the Debian devscripts package, version ###VERSION###.
This code is (C) 2005 by Branden Robinson, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

showpackage() {
    F1="$1"
    P1="$(LANG=C dpkg-query -S "$F1" 2> /dev/null || true )"
    P1="$(echo "$P1" | sed -e 's/diversion by \(.+\) to:/\1/')"
    # symlink may be created by postinst script for alternatives etc.,
    if [ -z "$P1" ] && [ -L "$F1" ]; then
        F2=$(readlink -f "$F1")
        P2="$(LANG=C dpkg-query -S "$F2" 2> /dev/null || true )"
        P2="$(echo "$P2" | sed -e 's/diversion by \(.+\) to:/\1/')"
    fi
    if [ -n "$P1" ]; then
        echo "$P1"
    elif [ -n "$P2" ]; then
        echo "unknown_package: $F1 -> $P2"
    else
        echo "unknown_package: $F1"
    fi
}

SHOWPACKAGE=DEFAULT
SHOWSTAT=TRUE

while [ -n "$1" ]; do
    case "$1" in
        -h|--help) usage; exit 0;;
        -V|--version) version; exit 0;;
        -p|--package) SHOWPACKAGE=PACKAGE
            shift
            ;;
        -f|--file) SHOWPACKAGE=FILE
            shift
            ;;
        -n|--no-stat) SHOWSTAT=FALSE
            shift
            ;;
        *)  break
            ;;
    esac
done

if [ $# -lt 1 ]; then
    set -- /bin /sbin /usr/bin /usr/sbin /usr/games
fi

NUM_EXECUTABLES=0
NUM_MANPAGES_FOUND=0
NUM_MANPAGES_MISSING=0

for DIR in "$@"; do
    for F in "$DIR"/*; do
        # Skip as it's a symlink to /usr/bin
        if [ "$F" = "/usr/bin/X11" ]; then continue; fi
        NUM_EXECUTABLES=$(( $NUM_EXECUTABLES + 1 ))

        if OUT=$(man -w -S 1:8:6 "${F##*/}" 2>&1 >/dev/null); then
            NUM_MANPAGES_FOUND=$(( $NUM_MANPAGES_FOUND + 1 ))
        else
            if [ $SHOWPACKAGE = "PACKAGE" ]; then 
                # echo "<packagename>: <filename>"
                showpackage "$F"
            elif [ $SHOWPACKAGE = "FILE" ]; then
                # echo "<filename>"
                echo "$F"
            else
                # echo "No manual entry for <filename>"
                echo "$OUT" | perl -ne "next if /^.*'man 7 undocumented'.*$/;" \
                  -e "s,(\W)\Q${F##*/}\E(?:\b|$),\1$F,; s,//,/,; print;"
            fi
            NUM_MANPAGES_MISSING=$(( $NUM_MANPAGES_MISSING + 1 ))
        fi
    done
done

if [ $SHOWSTAT = "TRUE" ]; then 
echo
printf "Of %d commands, found manpages for %d (%d missing).\n" \
    $NUM_EXECUTABLES \
    $NUM_MANPAGES_FOUND \
    $NUM_MANPAGES_MISSING
fi

# vim:set ai et sw=4 ts=4 tw=80:
