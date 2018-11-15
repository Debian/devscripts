#!/bin/bash

# wnpp-check -- check for software being packaged or requested

# This script is in the PUBLIC DOMAIN.
# Authors:
# David Paleino <d.paleino@gmail.com>
#
# Adapted from wnpp-alert, by Arthur Korn <arthur@korn.ch>

set -e

CURLORWGET=""
GETCOMMAND=""
EXACT=0
PROGNAME=${0##*/}

usage () { echo \
"Usage: $PROGNAME <package name> [...]
  -h,--help          Show this help message
  -v,--version       Show a version message

  Check whether a package is listed as being packaged (ITPed) or has an
  outstanding request for packaging (RFP) on the WNPP website
  https://www.debian.org/devel/wnpp/"
}

version () { echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This script is in the PUBLIC DOMAIN.
Authors: David Paleino <d.paleino@gmail.com>
Adapted from wnpp-alert, by Arthur Korn <arthur@korn.ch>,
with modifications by Julian Gilbey <jdg@debian.org>"
}

TEMP=$(getopt -n "$PROGNAME" -o 'hve' \
	      -l 'help,version,exact' \
	      -- "$@") || (rc=$?; usage >&2; exit $rc)

eval set -- "$TEMP"

while true
do
    case "$1" in
	-h|--help) usage; exit 0 ;;
	-v|--version) version; exit 0 ;;
	-e|--exact) EXACT=1 ;;
	--) shift; break ;;
    esac
    shift
done

if [ -z "$1" ]; then
    usage
    exit 1
fi

PACKAGES="$@"

if command -v wget >/dev/null 2>&1; then
    CURLORWGET="wget"
    GETCOMMAND="wget -q -O"
elif command -v curl >/dev/null 2>&1; then
    CURLORWGET="curl"
    GETCOMMAND="curl -qfs -o"
else
    echo "$PROGNAME: need either the wget or curl package installed to run this" >&2
    exit 1
fi

WNPP=$(mktemp --tmpdir wnppcheck-wnpp.XXXXXX)
WNPPTMP=$(mktemp --tmpdir wnppcheck-wnpp.XXXXXX)
WNPP_PACKAGES=$(mktemp --tmpdir wnppcheck-wnpp_packages.XXXXXX)
trap 'rm -f "$WNPP" "$WNPPTMP" "$WNPP_PACKAGES"' EXIT

# Here's a really sly sed script.  Rather than first grepping for
# matching lines and then processing them, this attempts to sed
# every line; those which succeed execute the 'p' command, those
# which don't skip over it to the label 'd'

$GETCOMMAND $WNPPTMP http://www.debian.org/devel/wnpp/being_packaged || \
    { echo "$PROGNAME: $CURLORWGET http://www.debian.org/devel/wnpp/being_packaged failed." >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/ITP \1 \2 -- \3/; T d; p; : d' $WNPPTMP > $WNPP

$GETCOMMAND $WNPPTMP http://www.debian.org/devel/wnpp/requested || \
    { echo "$PROGNAME: $CURLORWGET http://www.debian.org/devel/wnpp/requested failed." >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFP \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

awk -F' ' '{print "("$1" - #"$2") http://bugs.debian.org/"$2" "$3}' $WNPP | sort -k 5 > $WNPP_PACKAGES

FOUND=0
for pkg in $PACKAGES
do
    if [ $EXACT != 1 ]; then
	grep $pkg $WNPP_PACKAGES && FOUND=1
    else
	grep " $pkg$" $WNPP_PACKAGES && FOUND=1
    fi
done

exit $FOUND
