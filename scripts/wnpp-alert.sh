#! /bin/bash -e

# wnpp-alert -- check for installed packages which have been orphaned
#               or put up for adoption

# This script is in the PUBLIC DOMAIN.
# Authors:
# Arthur Korn <arthur@korn.ch>

# Arthur wrote:
# Get a list of packages with bugnumbers. I tried with LDAP, but this
# is _much_ faster.
# And I (Julian) tried it with Perl's LWP, but this is _much_ faster
# (startup time is huge).  And even Perl with wget is slower by 50%....

PROGNAME=`basename $0`
CACHEDIR=~/.devscripts_cache
CACHEDDIFF="${CACHEDIR}/wnpp-diff"

usage () { echo \
"Usage: $PROGNAME [--help|-h|--version|-v]
  List all installed packages with Request for Adoption (RFA),
  Request for Help (RHF), or Orphaned (O) bugs against them,
  as determined from the WNPP website.
  http://www.debian.org/devel/wnpp"
}

version () { echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This script is in the PUBLIC DOMAIN.
Authors: Arthur Korn <arthur@korn.ch>
Modifications: Julian Gilbey <jdg@debian.org>"
}

wnppdiff () {
    if [ ! -f "$CACHEDDIFF" ]; then
        # First use
        comm -12 $WNPP_PACKAGES $INSTALLED | sed -e 's/+/\\+/g' | \
          xargs -i egrep '^[A-Z]+ [0-9]+ {} ' $WNPP | \
          tee $CACHEDDIFF
    else
        comm -12 $WNPP_PACKAGES $INSTALLED | sed -e 's/+/\\+/g' | \
          xargs -i egrep '^[A-Z]+ [0-9]+ {} ' $WNPP > $WNPP_DIFF
        sort -o $CACHEDDIFF $CACHEDDIFF
        sort -o $WNPP_DIFF $WNPP_DIFF
        comm -3 $CACHEDDIFF $WNPP_DIFF | \
          sed -e 's/\t/\+/g' -e 's/^\([^+]\)/-\1/g'
        mv $WNPP_DIFF $CACHEDDIFF
    fi
}

if [ "x$1" = "x--help" -o "x$1" = "x-h" ]; then usage; exit 0; fi
if [ "x$1" = "x--version" -o "x$1" = "x-v" ]; then version; exit 0; fi

if ! command -v wget >/dev/null 2>&1; then
    echo "$PROGNAME: need the wget package installed to run this" >&2
    exit 1
fi


# Let's abandon this directory from now on, these files are so small
# (see bug#309802)
if [ -d "$CACHEDIR" ]; then
    rm -f "$CACHEDIR"/orphaned "$CACHEDIR"/rfa_bypackage
fi

INSTALLED=`mktemp -t wnppalert-installed.XXXXXX`
trap "rm -f '$INSTALLED'" 0 1 2 3 7 10 13 15
WNPP=`mktemp -t wnppalert-wnpp.XXXXXX`
WNPPTMP=`mktemp -t wnppalert-wnpp.XXXXXX`
trap "rm -f '$INSTALLED' '$WNPP' '$WNPPTMP'" 0 1 2 3 7 10 13 15
WNPP_PACKAGES=`mktemp -t wnppalert-wnpp_packages.XXXXXX`
trap "rm -f '$INSTALLED' '$WNPP' '$WNPPTMP' '$WNPP_PACKAGES'" \
  0 1 2 3 7 10 13 15

if [ "x$1" = "x--diff" ] || [ "x$1" = "x-d" ]; then
    WNPP_DIFF=`mktemp -t wnppalert-wnpp_diff.XXXXXX`
    trap "rm -f '$INSTALLED' '$WNPP' '$WNPPTMP' '$WNPP_PACKAGES' '$WNPP_DIFF'" \
      0 1 2 3 7 10 13 15
fi

# Here's a really sly sed script.  Rather than first grepping for
# matching lines and then processing them, this attempts to sed
# every line; those which succeed execute the 'p' command, those
# which don't skip over it to the label 'd'
wget -q -O $WNPPTMP http://www.debian.org/devel/wnpp/orphaned || \
    { echo "wnpp-alert: wget http://www.debian.org/devel/wnpp/orphaned failed" >&2; exit 1; }
sed -ne 's/.*<li><a href="http:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/O \1 \2 -- \3/; T d; p; : d' $WNPPTMP > $WNPP

wget -q -O $WNPPTMP http://www.debian.org/devel/wnpp/rfa_bypackage || \
    { echo "wnpp-alert: wget http://www.debian.org/devel/wnpp/rfa_bypackage" >&2; exit 1; }
sed -ne 's/.*<li><a href="http:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFA \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

wget -q -O $WNPPTMP http://www.debian.org/devel/wnpp/help_requested || \
    { echo "wnpp-alert: wget http://www.debian.org/devel/wnpp/help_requested" >&2; exit 1; }
sed -ne 's/.*<li><a href="http:\/\/bugs.debian.org\/\([0-9]*\)">\([^:<]*\)[: ]*\([^<]*\)<\/a>.*/RFH \1 \2 -- \3/; T d; p; : d' $WNPPTMP >> $WNPP

cut -f3 -d' ' $WNPP | sort > $WNPP_PACKAGES

# A list of installed files.
# This shouldn't use knowledge of the internal /var/lib/dpkg/status
# format directly, but speed ...
# For the correct settings of -B# -A#, keep up-to-date with
# the dpkg source, defn of fieldinfos[] in lib/parse.c
# (and should match Devscripts/Packages.pm)

grep -B2 -A7 'Status: install ok installed' /var/lib/dpkg/status | \
grep '^\(Package\|Source\):' | \
cut -f2 -d' ' | \
sort -u \
> $INSTALLED

if [ "x$1" = "x--diff" -o "x$1" = "x-d" ]; then 
    if [ -d "$CACHEDIR" ]; then
        wnppdiff
        exit 0
    else
        echo "$PROGNAME: Unable to create diff; displaying full output" 
    fi
fi

comm -12 $WNPP_PACKAGES $INSTALLED | sed -e 's/+/\\+/g' | \
xargs -i egrep '^[A-Z]+ [0-9]+ {} ' $WNPP
