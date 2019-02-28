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

synopsis () {
    echo "Usage: $PROGNAME [-h|--help|--version] [-d] [-S|--source] [-i|--indep] [-f] <file1> <file2> [<file> ...]"
}

usage () {
    synopsis
    cat <<EOT
  Merge the changes files <file1>, <file2>, ....  Output on stdout
  unless -f option given, in which case, output to
  <package>_<version>_multi.changes in the same directory as <file1>.
  If -i is given, only source and architecture-independent packages
  are included in the output.
  If -S is given, only the source package is included in the output.
EOT
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
DELETE=0
REMOVE_ARCHDEP=0
REMOVE_INDEP=0

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
	-d)
	    DELETE=1
	    shift
	    ;;
	-i|--indep)
	    REMOVE_ARCHDEP=1
	    shift
	    ;;
	-S|--source)
	    REMOVE_ARCHDEP=1
	    REMOVE_INDEP=1
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
    synopsis >&2
    exit 1
fi

# Sanity check #1: Do the requested files exist?
for f in "$@"; do
    if ! test -r $f; then
	echo "ERROR: Cannot read $f!" >&2
	exit 1
    fi
done

# Get a (possibly multi-line) field.
get_field () {
    perl -e '
    use warnings;
    use strict;
    use autodie;

    use Dpkg::Control;

    my $field = shift;
    foreach my $file (@ARGV) {
        my $changes = Dpkg::Control->new(type => CTRL_FILE_CHANGES);
        $changes->load($file);
        next unless defined $changes->{$field};
        print $changes->{$field};
        print "\n";
    }
    ' "$@"
}

# Extract the Architecture: field from all .changes files,
# and merge them, sorting out duplicates. Skip architectures
# other than all and source if desired.
ARCHS=$(get_field Architecture "$@" | tr ' ' '\n' | sort -u)
if test ${REMOVE_ARCHDEP} = 1; then
    ARCHS=$(echo "$ARCHS" | grep -E '^(all|source)$')
fi
if test ${REMOVE_INDEP} = 1; then
    ARCHS=$(echo "$ARCHS" | grep -vxF all)
fi
ARCHS=$(echo "$ARCHS" | tr '\n' ' ' | sed 's/ $//')

checksum_uniq() {
    local line
    local IFS=
    if test ${REMOVE_ARCHDEP} = 1 -o ${REMOVE_INDEP} = 1; then
	while read line; do
	    case "$line" in
		("")
		    # empty first line
		    echo "$line"
		    ;;
		(*.dsc|*.diff.gz|*.tar.*|*_source.buildinfo)
		    # source
		    echo "$line"
		    ;;
		(*_all.deb|*_all.udeb|*_all.buildinfo)
		    # architecture-indep
		    if test ${REMOVE_INDEP} = 0; then
			echo "$line"
		    fi
		    ;;
		(*.deb|*.udeb|*.buildinfo)
		    # architecture-specific
		    if test ${REMOVE_ARCHDEP} = 0; then
			echo "$line"
		    fi
		    ;;
		(*)
		    echo "Unrecognised file, is it architecture-dependent?" >&2
		    echo "$line" >&2
		    exit 1
		    ;;
	    esac
	done | awk '{if(arr[$NF] != 1){arr[$NF] = 1; print;}}'
    else
	awk '{if(arr[$NF] != 1){arr[$NF] = 1; print;}}'
    fi
}

# Extract & merge the Version: field from all files..
# Don't catch Version: GnuPG lines, though!
VERSION=$(get_field Version "$@" | sort -u)
SVERSION=$(echo "$VERSION" | perl -pe 's/^\d+://')
# Extract & merge the sources from all files
SOURCE=$(get_field Source "$@" | sort -u)
# Extract & merge the files from all files
FILES=$(get_field Files "$@" | checksum_uniq)
# Extract & merge the sha1 checksums from all files
SHA1S=$(get_field Checksums-Sha1 "$@" | checksum_uniq)
# Extract & merge the sha256 checksums from all files
SHA256S=$(get_field Checksums-Sha256 "$@" | checksum_uniq)
# Extract & merge the description from all files
DESCRIPTIONS=$(get_field Description "$@" | sort -u)
# Extract & merge the Formats from all files
FORMATS=$(get_field Format "$@" | sort -u)
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
OUTPUT=$(mktemp --tmpdir mergechanges.tmp.XXXXXXXXXX)
DESCFILE=$(mktemp --tmpdir mergechanges.tmp.XXXXXXXXXX)
trap 'rm -f "${OUTPUT}" "${DESCFILE}"' EXIT

# Copy one of the files to ${OUTPUT}, nuking any PGP signature
if $(grep -q "BEGIN PGP SIGNED MESSAGE" "$1"); then
    perl -ne 'next if 1../^$/; next if /^$/..1; print' "$1" > ${OUTPUT}
else
    cp "$1" ${OUTPUT}
fi

# Combine the Binary: and Description: fields. This is straightforward,
# unless we want to exclude some binary packages, in which case we need
# more thought.
BINARY=$(get_field Binary "$@" | tr ' ' '\n' | sort -u)
if test ${REMOVE_ARCHDEP} = 1 && test ${REMOVE_INDEP} = 1; then
    BINARY=
    DESCRIPTIONS=
elif test ${REMOVE_ARCHDEP} = 1 || test ${REMOVE_INDEP} = 1; then
    keep_binaries=$(
        get_field Files "$@" | while read -r line; do
            file="${line##* }"
            case "$line" in
                ("")
                    # empty first line
                    echo "$line"
                    ;;
                (*.dsc|*.diff.gz|*.tar.*|*.buildinfo)
                    # source or buildinfo
                    ;;
                (*_all.deb|*_all.udeb)
                    # architecture-indep
                    package="${file%%_*}"

                    if ! echo "$BINARY" | grep -q -x -F "$package"; then
                        echo "Error: $package not found in Binary field" >&2
                        echo "$line" >&2
                        exit 1
                    fi

                    if test ${REMOVE_INDEP} != 1; then
                        echo "$package"
                    fi
                    ;;
                (*.deb|*.udeb)
                    # architecture-specific
                    package="${file%%_*}"

                    if ! echo "$BINARY" | grep -q -x -F "$package"; then
                        echo "Error: $package not found in Binary field" >&2
                        echo "$line" >&2
                        exit 1
                    fi

                    if test ${REMOVE_ARCHDEP} != 1; then
                        echo "$package"
                    fi
                    ;;
                (*)
                    echo "Unrecognised file, is it architecture-dependent?" >&2
                    echo "$line" >&2
                    exit 1
                    ;;
            esac
        done \
    | tr '\n' ' ')

    BINARY=$(
        echo "$BINARY" |
        while read -r line; do
            if echo " $keep_binaries" | grep -q -F " $line "; then
                echo "$line";
            fi
        done
    )
    DESCRIPTIONS=$(
        echo "$DESCRIPTIONS" |
        while read -r line; do
            package="${line%% *}"
            if echo " $keep_binaries" | grep -q -F " $package "; then
                echo "$line";
            fi
        done
    )
fi
BINARY=$(echo "$BINARY" | tr '\n' ' ' | sed 's/ $//')

if test -n "${DESCRIPTIONS}"; then
    printf "Description:" > "${DESCFILE}"
    echo "${DESCRIPTIONS}" | sed -e 's/^/ /' >> "${DESCFILE}"
fi

if [ -n "$BINARY" ]; then
    BINARY="Binary: $BINARY\\n"
fi

# Modify the output to be the merged version:
# * Replace the Architecture: and Binary: fields
# * Nuke the value of Checksums-*: and Files:
# * Insert the Description: field before the Changes: field
#
# We print Binary directly before Source instead of directly replacing
# Binary, because with dpkg 1.19.3, if the first .changes file is
# source-only, it won't have a Binary field at all.
eval "awk -- '/^[^ ]/{ deleting=0 }
    /^ /{
        if (!deleting) {
            print
        }
        next
    }
    /^Architecture: /{printf \"%s ${ARCHS}\\n\", \$1; deleting=1; next}
    /^Source: /{printf \"${BINARY}\"; print; next}
    /^Binary: /{deleting=1; next}
    /^Changes:/{
        field=\$0
        while ((getline < \"${DESCFILE}\") > 0) {
            print
        }
        printf \"%s\\n\", field
        next
    }
    /^Format: /{ printf \"%s ${FORMATS}\\n\", \$1; deleting=1; next}
    /^(Checksums-.*|Files|Description):/{ deleting=1; next }
    { print }' \
    ${OUTPUT} ${REDIR1}"

# Voodoo magic to get the merged file and checksum lists into the output
if test -n "${SHA1S}"; then
    eval "printf 'Checksums-Sha1:' ${REDIR2}"
    eval "echo '${SHA1S}' | sed -e 's/^/ /' ${REDIR2}"
fi
if test -n "${SHA256S}"; then
    eval "printf 'Checksums-Sha256:' ${REDIR2}"
    eval "echo '${SHA256S}' | sed -e 's/^/ /' ${REDIR2}"
fi
eval "printf 'Files:' ${REDIR2}"
eval "echo '${FILES}' | sed -e 's/^/ /' ${REDIR2}"

if test ${DELETE} = 1; then
    rm "$@"
fi

exit 0
