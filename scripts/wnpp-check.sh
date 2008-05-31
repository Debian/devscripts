#! /bin/bash -e

# wnpp-check -- check for software being packaged or requested

# This script is in the PUBLIC DOMAIN.
# Authors:
# David Paleino <d.paleino@gmail.com>
#
# Adapted from wnpp-alert, by Arthur Korn <arthur@korn.ch>

PROGNAME=`basename $0`
PACKAGES="$@"

usage () { echo \
"Usage: $PROGNAME <package name> [...]
  -h,--help          Show this help message
  -v,--version       Show a version message

  Check whether a package is listed as being packaged (ITPed) or has an
  outstanding request for packaging (RFP) on the WNPP website
  http://www.debian.org/devel/wnpp/"
}

version () { echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This script is in the PUBLIC DOMAIN.
Authors: David Paleino <d.paleino@gmail.com>
Adapted from wnpp-alert, by Arthur Korn <arthur@korn.ch>,
with modifications by Julian Gilbey <jdg@debian.org>"
}

if [ "x$1" = "x--help" -o "x$1" = "x-h" ]; then usage; exit 0; fi
if [ "x$1" = "x--version" -o "x$1" = "x-v" ]; then version; exit 0; fi
if [ "x$1" = "x" ]; then usage; exit 1; fi

if ! command -v wget >/dev/null 2>&1; then
    echo "$PROGNAME: need the wget package installed to run this" >&2
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

wget -q -O $WNPPTMP http://www.debian.org/devel/wnpp/being_packaged || \
    { echo "wnpp-check: wget http://www.debian.org/devel/wnpp/being_packaged failed" >&2; exit 1; }
sed -ne 's/.*<li><a href="http:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/ITP \1 \2 -- \3/; T d; p; : d' $WNPPTMP > $WNPP

wget -q -O $WNPPTMP http://www.debian.org/devel/wnpp/requested || \
    { echo "wnpp-check: wget http://www.debian.org/devel/wnpp/requested" >&2; exit 1; }
sed -ne 's/.*<li><a href="http:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFP \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

awk -F' ' '{print $3" ("$1" - #"$2")"}' $WNPP | sort > $WNPP_PACKAGES

FOUND=0
for pkg in $PACKAGES
do
    grep $pkg $WNPP_PACKAGES && FOUND=1
done

exit $FOUND
