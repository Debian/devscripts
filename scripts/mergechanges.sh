#!/bin/bash
##
## mergechanges -- merge Architecture: and Files: fields of a set of .changes
## Copyright 2002 Gergely Nagy <algernon@debian.org>
## Changes copyright 2002,2003 by Julian Gilbey <jdg@debian.org>
##
## $MadHouse: home/bin/mergechanges,v 1.1 2002/01/25 12:37:27 algernon Exp $
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

PROGNAME=`basename $0`

usage () {
    echo \
"Usage: $PROGNAME [-h|--help|--version] [-f] <file1> <file2> [<file> ...]
  Merge the changes files <file1>, <file2>, ....  Output on stdout
  unless -f option given, in which case, output to
  <package>_<version>_multi.changes in the same directory as <file1>."
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright (C) 2002 Gergely Nagy <algernon@debian.org>
Changes copyright 2002 by Julian Gilbey <jdg@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

# Commandline parsing
FILE=0

while [ $# -gt 0 ]; do
    case "$1" in
	-h|--help)
	    usage
	    exit 0
	    ;;
	--version)
	    version
	    exit 0
	    ;;
	-f)
	    FILE=1
	    shift
	    ;;
	-*)
	    echo "Unrecognised option $1.  Use $progname --help for help" >&2
	    exit 1
	    ;;
	*)
	    break
	    ;;
    esac
done

# Sanity check #0: Do we have enough parameters?
if [ $# -lt 2 ]; then
    echo "Not enough parameters." >&2
    echo "Usage: mergechanges [--help|--version] [-f] <file1> <file2> [<file...>]" >&2
    exit 1
fi

# Sanity check #1: Do the requested files exist?
for f in "$@"; do
    if ! test -r $f; then
	echo "ERROR: Cannot read $f!" >&2
	exit 1
    fi
done

# Extract the Architecture: field from all .changes files,
# and merge them, sorting out duplicates
ARCHS=$(grep -h "^Architecture: " "$@" | sed -e "s,^Architecture: ,," | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')

checksum_uniq() {
    awk '{if(arr[$NF] != 1){arr[$NF] = 1; print;}}'
}

# Extract & merge the Version: field from all files..
# Don't catch Version: GnuPG lines, though!
VERSION=$(grep -h "^Version: [0-9]" "$@" | sed -e "s,^Version: ,," | sort -u)
SVERSION=$(echo "$VERSION" | perl -pe 's/^\d+://')
# Extract & merge the sources from all files
SOURCE=$(grep -h "^Source: " "$@" | sed -e "s,^Source: ,," | sort -u)
# Extract & merge the files from all files
FILES=$(egrep -h "^ [0-9a-f]{32} [0-9]+" "$@" | checksum_uniq)
# Extract & merge the sha1 checksums from all files
SHA1S=$(egrep -h "^ [0-9a-f]{40} [0-9]+" "$@" | checksum_uniq)
# Extract & merge the sha256 checksums from all files
SHA256S=$(egrep -h "^ [0-9a-f]{64} [0-9]+" "$@" | checksum_uniq)
# Extract & merge the description from all files
DESCRIPTIONS=$(sed '/^Description:/,/^[^ ]/{/^ /p;d};d' "$@" | sort -u)
# Extract & merge the Formats from all files
FORMATS=$(grep -h "^Format: " "$@" | sed -e "s,^Format: ,," | sort -u)
# Extract & merge the Checksums-* field names from all files
CHECKSUMS=$(grep -h "^Checksums-.*:" "$@" | sort -u)
UNSUPCHECKSUMS="$(echo "${CHECKSUMS}" | grep -v "^Checksums-Sha\(1\|256\):" || true)"

# Sanity check #2: Versions must match
if test $(echo "${VERSION}" | wc -l) -ne 1; then
    echo "ERROR: Version numbers do not match:" >&2
    grep "^Version: [0-9]" "$@" >&2
    exit 1
fi

# Sanity check #3: Sources must match
if test $(echo "${SOURCE}" | wc -l) -ne 1; then
    echo "Error: Source packages do not match:" >&2
    grep "^Source: " "$@" >&2
    exit 1
fi

# Sanity check #4: Description for same binary must match
if test $(echo "${DESCRIPTIONS}" | sed -e 's/ \+- .*$//' | uniq -d | wc -l) -ne 0; then
    echo "Error: Descriptions do not match:" >&2
    echo "${DESCRIPTIONS}" >&2
    exit 1
fi

# Sanity check #5: Formats must match
if test $(echo "${FORMATS}" | wc -l) -ne 1; then
    if test "${FORMATS}" = "$(printf "1.7\n1.8\n")"; then
	FORMATS="1.7"
	CHECKSUMS=""
	UNSUPCHECKSUMS=""
	SHA1S=""
	SHA256S=""
    else
	echo "Error: Changes files have different Format fields:" >&2
	grep "^Format: " "$@" >&2
	exit 1
    fi
fi

# Sanity check #6: The Format must be one we understand
case "$FORMATS" in
    1.7|1.8) # Supported
        ;;
    *)
        echo "Error: Changes files use unknown Format:" >&2
        echo "${FORMATS}" >&2
        exit 1
        ;;
esac

# Sanity check #7: Unknown checksum fields
if test -n "${UNSUPCHECKSUMS}"; then
    echo "Error: Unsupported checksum fields:" >&2
    echo "${UNSUPCHECKSUMS}" >&2
    exit 1
fi

if test ${FILE} = 1; then
    DIR=`dirname "$1"`
    REDIR1="> '${DIR}/${SOURCE}_${SVERSION}_multi.changes'"
    REDIR2=">$REDIR1"
fi

# Temporary output
OUTPUT=`tempfile`
DESCFILE=`tempfile`
trap "rm -f '${OUTPUT}' '${DESCFILE}'" 0 1 2 3 7 10 13 15

if test $(echo "${DESCRIPTIONS}" | wc -l) -ne 0; then
    echo "Description: " > "${DESCFILE}"
    echo "${DESCRIPTIONS}" >> "${DESCFILE}"
fi

# Copy one of the files to ${OUTPUT}, nuking any PGP signature
if $(grep -q "BEGIN PGP SIGNED MESSAGE" "$1"); then
    perl -ne 'next if 1../^$/; next if /^$/..1; print' "$1" > ${OUTPUT}
else
    cp "$1" ${OUTPUT}
fi

# Replace the Architecture: field, nuke the value of Checksums-*: and Files:,
# and insert the Description: field before the Changes: field
eval "awk -- '/^[^ ]/{ deleting=0 }
    /^ /{
        if (!deleting) {
            print
        }
        next
    }
    /^Architecture: /{printf \"%s ${ARCHS}\\n\", \$1; next}
    /^Changes:/{
        field=\$0
        while ((getline < \"${DESCFILE}\") > 0) {
            print
        }
        printf \"%s\\n\", field
        next
    }
    /^Format: /{ printf \"%s ${FORMATS}\\n\", \$1; next}
    /^(Checksums-.*|Files|Description):/{ deleting=1; next }
    { print }' \
    ${OUTPUT} ${REDIR1}"

# Voodoo magic to get the merged file and checksum lists into the output
if test -n "${SHA1S}"; then
    eval "echo 'Checksums-Sha1: ' ${REDIR2}"
    eval "echo '${SHA1S}' ${REDIR2}"
fi
if test -n "${SHA256S}"; then
    eval "echo 'Checksums-Sha256: ' ${REDIR2}"
    eval "echo '${SHA256S}' ${REDIR2}"
fi
eval "echo 'Files: ' ${REDIR2}"
eval "echo '${FILES}' ${REDIR2}"

exit 0
