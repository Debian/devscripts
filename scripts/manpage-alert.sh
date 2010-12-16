#!/bin/bash
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
Usage: manpage-alert [options | paths]
  Options:
    -h, --help          This usage screen.
    -V, --version       Display the version and copyright information

  This script will locate executables in the given paths for which no
  manpage is available.

  If no paths are specified on the command line, "/bin /sbin /usr/bin
  /usr/sbin /usr/games" will be used by default.
EOF
}

version() {
    cat <<EOF
This is manpage-alert, from the Debian devscripts package, version ###VERSION###
This code is (C) 2005 by Branden Robinson, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

case "$1" in
    --help|-h) usage; exit 0;;
    --version|-V) version; exit 0;;
esac

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

        OUT=$(man -w -S 1:8:6 "${F##*/}" 2>&1 >/dev/null)
        RET=$?
        if [ $RET = "0" ]; then
            NUM_MANPAGES_FOUND=$(( $NUM_MANPAGES_FOUND + 1 ))
        else
            echo "$OUT" | perl -ne "next if /^.*'man 7 undocumented'.*$/;" \
              -e "s,(\W)\Q${F##*/}\E(?:\b|$),\1$F,; s,//,/,; print;"
            NUM_MANPAGES_MISSING=$(( $NUM_MANPAGES_MISSING + 1 ))
        fi
    done
done

printf "Of %d commands, found manpages for %d (%d missing).\n" \
    $NUM_EXECUTABLES \
    $NUM_MANPAGES_FOUND \
    $NUM_MANPAGES_MISSING

# vim:set ai et sw=4 ts=4 tw=80:
