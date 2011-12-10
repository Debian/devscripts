#!/bin/sh

#   dscextract.sh - Extract a single file from a Debian source package
#   Copyright (C) 2011 Christoph Berg <myon@debian.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

set -eu

die () {
	echo "$*" >&2
	exit 2
}

setzip () {
	case $1 in
		*.gz) ZIP=--gzip ;;
		*.xz) ZIP=--xz ;;
		*.lzma) ZIP=--lzma ;;
		*.bz2) ZIP=--bzip2 ;;
	esac
}

FAST=""
while getopts "f" opt ; do
	case $opt in
		f) FAST=yes ;;
		*) exit 2 ;;
	esac
done
# shift away args
shift $(($OPTIND - 1))

[ $# = 2 ] || die "Usage: $(basename $0) <dsc> <file>"
DSC="$1"
test -e "$DSC" || die "$DSC not found"
FILE="$2"

DSCDIR=$(dirname "$DSC")
WORKDIR=$(mktemp -d --tmpdir dscextract.XXXXXX)
trap "rm -rf $WORKDIR" 0 2 3 15

if DIFFGZ=$(egrep '^ [0-9a-f]{32,64} [0-9]+ [^ ]+\.diff\.(gz|xz|lzma|bz2)$' "$DSC") ; then
	DIFFGZ=$(echo "$DIFFGZ" | cut -d ' ' -f 4 | head -n 1)
	test -e "$DSCDIR/$DIFFGZ" || die "$DSCDIR/$DIFFGZ: not found"
	filterdiff -p1 -i "$FILE" -z "$DSCDIR/$DIFFGZ" > "$WORKDIR/patch"
	if test -s "$WORKDIR/patch" ; then
		# case 1: file found in .diff.gz
		if ! grep -q '^@@ -0,0 ' "$WORKDIR/patch" ; then
			# case 1a: patch requires original file
			ORIGTGZ=$(egrep '^ [0-9a-f]{32,64} [0-9]+ [^ ]+\.orig\.tar\.(gz|xz|lzma|bz2)$' "$DSC") || die "no orig.tar.* found in $DSC"
			ORIGTGZ=$(echo "$ORIGTGZ" | cut -d ' ' -f 4 | head -n 1)
			setzip $ORIGTGZ
			test -e "$DSCDIR/$ORIGTGZ" || die "$DSCDIR/$ORIGTGZ not found"
			tar --extract --to-stdout $ZIP --file "$DSCDIR/$ORIGTGZ" --wildcards "*/$FILE" > "$WORKDIR/output" 2>/dev/null || :
			test -s "$WORKDIR/output" || die "$FILE not found in $DSCDIR/$ORIGTGZ, but required by patch"
		fi
		patch --silent "$WORKDIR/output" < "$WORKDIR/patch"
		test -s "$WORKDIR/output" || die "patch $FILE did not produce any output"
		cat "$WORKDIR/output"
		exit 0
	elif [ "$FAST" ] ; then
		# in fast mode, don't bother looking into .orig.tar.gz
		exit 1
	fi
fi

if DEBIANTARGZ=$(egrep '^ [0-9a-f]{32,64} [0-9]+ [^ ]+\.debian\.tar\.(gz|xz|lzma|bz2)$' "$DSC") ; then
	case $FILE in
		debian/*)
			DEBIANTARGZ=$(echo "$DEBIANTARGZ" | cut -d ' ' -f 4 | head -n 1)
			test -e "$DSCDIR/$DEBIANTARGZ" || die "$DSCDIR/$DEBIANTARGZ not found"
			setzip $DEBIANTARGZ
			tar --extract --to-stdout $ZIP --file "$DSCDIR/$DEBIANTARGZ" "$FILE" > "$WORKDIR/output" 2>/dev/null || :
			test -s "$WORKDIR/output" || exit 1
			# case 2a: file found in .debian.tar.gz
			cat "$WORKDIR/output"
			exit 0
			# for 3.0 format, no need to look in other places here
			;;
		*)
			ORIGTGZ=$(egrep '^ [0-9a-f]{32,64} [0-9]+ [^ ]+\.orig\.tar\.(gz|xz|lzma|bz2)$' "$DSC") || die "no orig.tar.gz found in $DSC"
			ORIGTGZ=$(echo "$ORIGTGZ" | cut -d ' ' -f 4 | head -n 1)
			test -e "$DSCDIR/$ORIGTGZ" || die "$DSCDIR/$ORIGTGZ not found"
			setzip $ORIGTGZ
			tar --extract --to-stdout $ZIP --file "$DSCDIR/$ORIGTGZ" --wildcards --no-wildcards-match-slash "*/$FILE" > "$WORKDIR/output" 2>/dev/null || :
			test -s "$WORKDIR/output" || exit 1
			# case 2b: file found in .orig.tar.gz
			# TODO: apply patches from debian.tar.gz
			cat "$WORKDIR/output"
			exit 0
			;;
	esac
fi

if TARGZ=$(egrep '^ [0-9a-f]{32,64} [0-9]+ [^ ]+\.tar\.(gz|xz|lzma|bz2)$' "$DSC") ; then
	TARGZ=$(echo "$TARGZ" | cut -d ' ' -f 4 | head -n 1)
	test -e "$DSCDIR/$TARGZ" || die "$DSCDIR/$TARGZ not found"
	setzip $TARGZ
	tar --extract --to-stdout $ZIP --file "$DSCDIR/$TARGZ" --wildcards --no-wildcards-match-slash "*/$FILE" > "$WORKDIR/output" 2>/dev/null || :
	test -s "$WORKDIR/output" || exit 1
	# case 3: file found in .tar.gz or .orig.tar.gz
	cat "$WORKDIR/output"
	exit 0
fi

exit 1
