#!/bin/sh
#
# dcmd: expand file lists of .dsc/.changes files in the command line
#
# Copyright (C) 2008 Romain Francoise <rfrancoise@debian.org>
# Copyright (C) 2008 Christoph Berg <myon@debian.org>
# Copyright (C) 2008 Adam D. Barratt <adsb@debian.org>
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
    printf "Usage: %s [options] [command] [dsc or changes file] [...]\n" $PROGNAME
}

endswith()
{
    case $1 in
	*$2) return 0 ;;
	*) return 1;;
    esac
}

# Instead of parsing the file completely as the previous Python
# implementation did (using python-debian), let's just select lines
# that look like they might be part of the file list.
RE="^ [0-9a-f]{32} [0-9]+ ((([a-zA-Z-]+/)?[a-zA-Z1-]+|-) ([a-zA-Z]+|-) )?(.*)$"

maybe_expand()
{
    local dir
    local sedre
    if [ -e "$1" ] && (endswith "$1" .changes || endswith "$1" .dsc); then
	# Need to escape whatever separator is being used in sed expression so
	# it doesn't prematurely end the s command
	dir=$(dirname "$1" | sed 's/,/\\,/g')
	if [ "$(echo "$1" | cut -b1-2)" != "./" ]; then
	    sedre="\."
	fi
	sed --regexp-extended -n "s,$RE,$dir/\5,p" <"$1" | sed "s,^$sedre/,,"
    fi
}

DSC=1; BCHANGES=1; SCHANGES=1; ARCHDEB=1; INDEPDEB=1; TARBALL=1; DIFF=1
CHANGES=1; DEB=1; ARCHUDEB=1; INDEPUDEB=1; UDEB=1;
FILTERED=0; FAIL_MISSING=1

while [ $# -gt 0 ]; do
    TYPE=""
    case "$1" in
	--version|-v) version; exit 0;;
	--help|-h) usage; exit 0;;
	--no-fail-on-missing|-r) FAIL_MISSING=0;;
	--fail-on-missing) FAIL_MISSING=1;;
	--) shift; break;;
	--no-*)
	    TYPE=${1#--no-}
	    case "$FILTERED" in
		1)  echo "$PROGNAME: Can't combine --foo and --no-foo options" >&2;
		    exit 1;;
		0)  FILTERED=-1;;
	    esac;;
	--**)
	    TYPE=${1#--}
	    case "$FILTERED" in
		-1) echo "$PROGNAME: Can't combine --foo and --no-foo options" >&2;
		    exit 1;;
		0)  FILTERED=1; DSC=0; BCHANGES=0; SCHANGES=0; CHANGES=0
		    ARCHDEB=0; INDEPDEB=0; DEB=0; ARCHUDEB=0; INDEPUDEB=0
		    UDEB=0; TARBALL=0; DIFF=0;;
	    esac;;
	*) break;;
    esac

    case "$TYPE" in
	"") ;;
	dsc) [ "$FILTERED" = "1" ] && DSC=1 || DSC=0;;
	changes) [ "$FILTERED" = "1" ] &&
	    { BCHANGES=1; SCHANGES=1; CHANGES=1; } ||
	    { BCHANGES=0; SCHANGES=0; CHANGES=0; } ;;
	bchanges) [ "$FILTERED" = "1" ] && BCHANGES=1 || BCHANGES=0;;
	schanges) [ "$FILTERED" = "1" ] && SCHANGES=1 || SCHANGES=1;;
	deb) [ "$FILTERED" = "1" ] &&
	    { ARCHDEB=1; INDEPDEB=1; DEB=1; } ||
	    { ARCHDEB=0; INDEPDEB=0; DEB=0; };;
	archdeb) [ "$FILTERED" = "1" ] && ARCHDEB=1 || ARCHDEB=0;;
	indepdeb) [ "$FILTERED" = "1" ] && INDEPDEB=1 || INDEPDEB=0;;
	udeb) [ "$FILTERED" = "1" ] &&
	    { ARCHUDEB=1; INDEPUDEB=1; UDEB=1; } ||
	    { ARCHUDEB=0; INDEPUDEB=0; UDEB=0; };;
	archudeb) [ "$FILTERED" = "1" ] && ARCHUDEB=1 || ARCHUDEB=0;;
	indepudeb) [ "$FILTERED" = "1" ] && INDEPUDEB=1 || INDEPUDEB=0;;
	tar|orig) [ "$FILTERED" = "1" ] && TARBALL=1 || TARBALL=0;;
	diff) [ "$FILTERED" = "1" ] && DIFF=1 || DIFF=0;;
	*) echo "$PROGNAME: Unknown option '$1'" >&2; exit 1;;
    esac
    shift
done

args=""
for arg in "$@"; do
    temparg="$(maybe_expand "$arg")"
    if [ -z "$temparg" ]; then
	# Not expanded, so simply add to argument list
	args="$args $arg"
    else
	SEEN_INDEPDEB=0; SEEN_ARCHDEB=0; SEEN_SCHANGES=0; SEEN_BCHANGES=0
	SEEN_INDEPUDEB=0; SEEN_ARCHUDEB=0; SEEN_UDEB=0;
	SEEN_TARBALL=0; SEEN_DIFF=0; SEEN_DSC=0
	MISSING=0
	newarg=""
	# Output those items from the expanded list which were
	# requested, and record which files are contained in the list
	eval $(echo "$temparg" | while read THISARG; do
	    if [ -z "$THISARG" ]; then
		# Skip
		:
	    elif endswith "$THISARG" _all.deb; then
		[ "$INDEPDEB" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_INDEPDEB=1;"
	    elif endswith "$THISARG" .deb; then
		[ "$ARCHDEB" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_ARCHDEB=1;"
	    elif endswith "$THISARG" _all.udeb; then
		[ "$INDEPUDEB" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_INDEPUDEB=1;"
	    elif endswith "$THISARG" .udeb; then
		[ "$ARCHUDEB" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_ARCHUDEB=1;"
	    elif endswith "$THISARG" .tar.gz || \
		 endswith "$THISARG" .tar.xz || \
		 endswith "$THISARG" .tar.lzma || \
		 endswith "$THISARG" .tar.bz2; then
		[ "$TARBALL" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_TARBALL=1;"
	    elif endswith "$THISARG" _source.changes; then
		[ "$SCHANGES" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_SCHANGES=1;"
	    elif endswith "$THISARG" .changes; then
		[ "$BCHANGES" = "0" ] || echo "newarg\"\$newarg $THISARG\";"
		echo "SEEN_BCHANGES=1;"
	    elif endswith "$THISARG" .dsc; then
		[ "$DSC" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_DSC=1;"
	    elif endswith "$THISARG" .diff.gz; then
		[ "$DIFF" = "0" ] || echo "newarg=\"\$newarg $THISARG\";"
		echo "SEEN_DIFF=1;"
	    elif [ "$FILTERED" != "1" ]; then
		# What is it? Output anyway
		echo "newarg=\"\$newarg $THISARG\";"
	    fi
	done)

	INCLUDEARG=1
	if endswith "$arg" _source.changes; then
	    [ "$SCHANGES" = "1" ] || INCLUDEARG=0
	    SEEN_SCHANGES=1
	elif endswith "$arg" .changes; then
	    [ "$BCHANGES" = "1" ] || INCLUDEARG=0
	    SEEN_BCHANGES=1
	elif endswith "$arg" .dsc; then
	    [ "$DSC" = "1" ] || INCLUDEARG=0
	    SEEN_DSC=1
	fi

	if [ "$FAIL_MISSING" = "1" ] && [ "$FILTERED" = "1" ]; then
	    if [ "$CHANGES" = "1" ]; then
		if [ "$SEEN_SCHANGES" = "0" ] && [ "$SEEN_BCHANGES" = "0" ]; then
		    MISSING=1; echo "$arg: .changes fiie not found" >&2
		fi
	    else
		if [ "$SCHANGES" = "1" ] && [ "$SEEN_SCHANGES" = "0" ]; then
		    MISSING=1; echo "$arg: source .changes file not found" >&2
		fi
		if [ "$BCHANGES" = "1" ] && [ "$SEEN_BCHANGES" = "0" ]; then
		    MISSING=1; echo "$arg: binary .changes file not found" >&2
		fi
	    fi

	    if [ "$DEB" = "1" ]; then
		if  [ "$SEEN_INDEPDEB" = "0" ] && [ "$SEEN_ARCHDEB" = "0" ]; then
		    MISSING=1; echo "$arg: binary packages not found" >&2
		fi
	    else
		if [ "$INDEPDEB" = "1" ] && [ "$SEEN_INDEPDEB" = "0" ]; then
		    MISSING=1; echo "$arg: arch-indep packages not found" >&2
		fi
		if [ "$ARCHDEB" = "1" ] && [ "$SEEN_ARCHDEB" = "0" ]; then
		    MISSING=1; echo "$arg: arch-dep packages not found" >&2
		fi
	    fi

	    if [ "$UDEB" = "1" ]; then
		if [ "$SEEN_INDEPUDEB" = "0" ] && [ "$SEEN_ARCHUDEB" = "0" ]; then
		    MISSING=1; echo "$arg: udeb packages not found" >&2
		fi
	    else
		if [ "$INDEPUDEB" = "1" ] && [ "$SEEN_INDEPUDEB" = "0" ]; then
		    MISSING=1; echo "$arg: arch-indep udeb packages not found" >&2
		fi
		if [ "$ARCHUDEB" = "1" ] && [ "$SEEN_ARCHUDEB" = "0" ]; then
		    MISSING=1; echo "$arg: arch-dep udeb packages not found" >&2
		fi

	    fi

	    if [ "$DSC" = "1" ] && [ "$SEEN_DSC" = "0" ]; then
		MISSING=1; echo "$arg: .dsc file not found" >&2
	    fi
	    if [ "$TARBALL" = "1" ] && [ "$SEEN_TARBALL" = "0" ]; then
		MISSING=1; echo "$arg: upstream tar not found" >&2
	    fi
	    if [ "$DIFF" = "1" ] && [ "$SEEN_DIFF" = "0" ]; then
		MISSING=1; echo "$arg: Debian diff not found" >&2
	    fi

	    [ "$MISSING" = "0" ] || exit 1
	fi

	args="$args $newarg"
	[ "$INCLUDEARG" = "0" ] || args="$args $arg"
    fi
done

if [ -e "$1" ] && (endswith "$1" .changes || endswith "$1" .dsc); then
    set -- $args
    for arg in $args; do
	echo $arg
    done
    exit 0
fi

exec $args
