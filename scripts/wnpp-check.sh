#!/bin/bash

# wnpp-check -- check for software being packaged or requested

# This script is in the PUBLIC DOMAIN.
# Authors:
# David Paleino <d.paleino@gmail.com>
#
# Adapted from wnpp-alert, by Arthur Korn <arthur@korn.ch>

set -e

PACKAGES="$@"
CURLORWGET=""
GETCOMMAND=""

usage () { echo \
"Usage: ${0##*/} <package name> [...]
  -h,--help          Show this help message
  -v,--version       Show a version message

  Check whether a package is listed as being packaged (ITPed) or has an
  outstanding request for packaging (RFP) on the WNPP website
  http://www.debian.org/devel/wnpp/"
}

version () { echo \
"This is ${0##*/}, from the Debian devscripts package, version ###VERSION###
This script is in the PUBLIC DOMAIN.
Authors: David Paleino <d.paleino@gmail.com>
Adapted from wnpp-alert, by Arthur Korn <arthur@korn.ch>,
with modifications by Julian Gilbey <jdg@debian.org>"
}

if [ "x$1" = "x--help" -o "x$1" = "x-h" ]; then usage; exit 0; fi
if [ "x$1" = "x--version" -o "x$1" = "x-v" ]; then version; exit 0; fi
if [ "x$1" = "x" ]; then usage; exit 1; fi

if command -v wget >/dev/null 2>&1; then
    CURLORWGET="wget"
    GETCOMMAND="wget -q -O"
elif command -v curl >/dev/null 2>&1; then
    CURLORWGET="curl"
    GETCOMMAND="curl -qfs -o"
else
    echo "${0##*/}: need either the wget or curl package installed to run this" >&2
    exit 1
fi

WNPP=`mktemp -t wnppcheck-wnpp.XXXXXX`
WNPPTMP=`mktemp -t wnppcheck-wnpp.XXXXXX`
trap "rm -f '$WNPP' '$WNPPTMP'" 0 1 2 3 7 10 13 15
WNPP_PACKAGES=`mktemp -t wnppcheck-wnpp_packages.XXXXXX`
trap "rm -f '$WNPP' '$WNPPTMP' '$WNPP_PACKAGES'" \
  0 1 2 3 7 10 13 15

# Here's a really sly sed script.  Rather than first grepping for
# matching lines and then processing them, this attempts to sed
# every line; those which succeed execute the 'p' command, those
# which don't skip over it to the label 'd'

$GETCOMMAND $WNPPTMP http://www.debian.org/devel/wnpp/being_packaged || \
    { echo "${0##*/}: $CURLORWGET http://www.debian.org/devel/wnpp/being_packaged failed." >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/ITP \1 \2 -- \3/; T d; p; : d' $WNPPTMP > $WNPP

$GETCOMMAND $WNPPTMP http://www.debian.org/devel/wnpp/requested || \
    { echo "${0##*/}: $CURLORWGET http://www.debian.org/devel/wnpp/requested failed." >&2; exit 1; }
sed -ne 's/.*<li><a href="https\?:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFP \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

awk -F' ' '{print "("$1" - #"$2") http://bugs.debian.org/"$2" "$3}' $WNPP | sort -k 5 > $WNPP_PACKAGES

FOUND=0
for pkg in $PACKAGES
do
    grep $pkg $WNPP_PACKAGES && FOUND=1
done

exit $FOUND
