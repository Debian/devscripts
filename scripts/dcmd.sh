#!/bin/sh
#
# dcmd: expand file lists of .dsc/.changes files in the command line
#
# Copyright (C) 2008 Romain Francoise <rfrancoise@debian.org>
# Copyright (C) 2008 Christoph Berg <myon@debian.org>
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

# Usage:
#
# dcmd replaces any reference to a .dsc or .changes file in the command
# line with the list of files in its 'Files' section, plus the
# .dsc/.changes file itself.
#
# $ dcmd sha1sum rcs_5.7-23_amd64.changes
# f61254e2b61e483c0de2fc163321399bbbeb43f1  rcs_5.7-23.dsc
# 7a2b283b4c505d8272a756b230486a9232376771  rcs_5.7-23.diff.gz
# e3bac970a57a6b0b41c28c615f2919c931a6cb68  rcs_5.7-23_amd64.deb
# c531310b18773d943249cfaa8b539a9b6e14b8f4  rcs_5.7-23_amd64.changes
# $

PROGNAME=`basename $0`

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2008 by Romain Francoise, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

usage()
{
    printf "Usage: %s [command] [dsc or changes file] [...]\n" $PROGNAME
}

endswith()
{
    [ $(basename "$1" $2)$2 = $(basename "$1") ]
}

# Instead of parsing the file completely as the previous Python
# implementation did (using python-debian), let's just select lines
# that look like they might be part of the file list.
RE="^ [0-9a-f]{32} [0-9]+ ([a-z1]+ [a-z]+ )?(.*)$"

maybe_expand()
{
    local dir
    if [ -e "$1" ] && (endswith "$1" .changes || endswith "$1" .dsc); then
	dir=$(dirname "$1")
	sed -rn "s,$RE,$dir/\2,p" <"$1" | sed 's,^\./,,'
    fi
}

if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
    version
    exit 0
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
fi

args=""
for arg in "$@"; do
    args="$args $(maybe_expand "$arg") $arg"
done

if [ -e "$1" ] && (endswith "$1" .changes || endswith "$1" .dsc); then
    set -- $args
    for arg in $args; do
	echo $arg
    done
    exit 0
fi

exec $args
