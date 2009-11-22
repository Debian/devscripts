#! /bin/bash

# who-uploads sourcepkg [ sourcepkg ... ]
# Tells you who made the latest uploads of a source package.
# NB: I'm encoded in UTF-8!!

# Written and copyright 2006 by Julian Gilbey <jdg@debian.org> 
# Based on an original script
# copyright 2006 Adeodato Simó <dato@net.com.org.es>
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

usage () {
    echo \
"Usage: $PROGNAME [options] package ...
  Display the most recent three uploaders of each package.
  Packages should be source packages, not binary packages.

  Options:
    -M, --max-uploads=N
                      Display at most the N most recent uploads (default: 3)
    --keyring KEYRING Add KEYRING as a GPG keyring for Debian Developers'
                      keys in addition to /usr/share/keyrings/debian-keyring.*
                      and /usr/share/keyrings/debian-maintainers.gpg;
                      this option may be given multiple times
    --no-default-keyrings
                      Do not use the default keyrings
    --no-conf, --noconf
                      Don't read devscripts config files;
                      must be the first option given
    --date            Display the date of the upload
    --no-date, --nodate
                      Don't display the date of the upload (default)
    --help            Show this message
    --version         Show version and copyright information

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2006 by Julian Gilbey <jdg@debian.org>,
all rights reserved.
Based on original code copyright 2006 Adeodato Simó <dato@net.com.org.es>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}


# Boilerplate: set config variables
DEFAULT_WHOUPLOADS_KEYRINGS=/usr/share/keyrings/debian-keyring.gpg:/usr/share/keyrings/debian-keyring.pgp:/usr/share/keyrings/debian-maintainers.gpg
DEFAULT_WHOUPLOADS_MAXUPLOADS=3
DEFAULT_WHOUPLOADS_DATE=no
VARS="WHOUPLOADS_KEYRINGS WHOUPLOADS_MAXUPLOADS WHOUPLOADS_DATE"

if [ "$1" = "--no-conf" -o "$1" = "--noconf" ]; then
    shift
    MODIFIED_CONF_MSG="$MODIFIED_CONF_MSG
  (no configuration files read)"

    # set defaults
    for var in $VARS; do
	eval "$var=\$DEFAULT_$var"
    done
else
    # Run in a subshell for protection against accidental errors
    # in the config files
    eval $(
	set +e
	for var in $VARS; do
	    eval "$var=\$DEFAULT_$var"
	done

	for file in /etc/devscripts.conf ~/.devscripts
	  do
	  [ -r $file ] && . $file
	done

	set | grep "^WHOUPLOADS_")

    # check sanity
    if [ "$WHOUPLOADS_MAXUPLOADS" != \
	    "$(echo \"$WHOUPLOADS_MAXUPLOADS\" | tr -cd 0-9)" ]; then
	WHOUPLOADS_MAXUPLOADS=3
    fi

    WHOUPLOADS_DATE="$(echo "$WHOUPLOADS_DATE" | tr A-Z a-z)"
    if [ "$WHOUPLOADS_DATE" != "yes" ] && [ "$WHOUPLOADS_DATE" != "no" ]; then
	WHOUPLOADS_DATE=no
    fi

    # don't check WHOUPLOADS_KEYRINGS here

    # set config message
    MODIFIED_CONF=''
    for var in $VARS; do
	eval "if [ \"\$$var\" != \"\$DEFAULT_$var\" ]; then
	    MODIFIED_CONF_MSG=\"\$MODIFIED_CONF_MSG
  $var=\$$var\";
	MODIFIED_CONF=yes;
	fi"
    done

    if [ -z "$MODIFIED_CONF" ]; then
	MODIFIED_CONF_MSG="$MODIFIED_CONF_MSG
  (none)"
    fi
fi

MAXUPLOADS=$WHOUPLOADS_MAXUPLOADS
WANT_DATE=$WHOUPLOADS_DATE

OIFS="$IFS"
IFS=:
declare -a GPG_DEFAULT_KEYRINGS

for keyring in $WHOUPLOADS_KEYRINGS; do
    if [ -f "$keyring" ]; then
	GPG_DEFAULT_KEYRINGS=("${GPG_DEFAULT_KEYRINGS[@]}" "--keyring" "$keyring")
    elif [ -n "$keyring" ]; then
	echo "Could not find keyring $keyring, skipping it" >&2
    fi
done
IFS="${OIFS:- 	}"

declare -a GPG_KEYRINGS

# Command-line options
TEMP=$(getopt -s bash -o 'h' \
	--long max-uploads:,keyring:,no-default-keyrings \
	--long no-conf,noconf \
	--long date,nodate,no-date \
	--long help,version \
	--options M: \
	-n "$PROGNAME" -- "$@")
if [ $? != 0 ] ; then exit 1 ; fi

eval set -- $TEMP

# Process Parameters
while [ "$1" ]; do
    case $1 in
    --max-uploads|-M)
	shift
	if [ "$1" = "$(echo \"$1\" | tr -cd 0-9)" ]; then
	    MAXUPLOADS=$1
	fi
	;;
    --keyring)
	shift
	if [ -f "$1" ]; then
	    GPG_KEYRINGS=("${GPG_KEYRINGS[@]}" "--keyring" "$1")
	else
	    echo "Could not find keyring $1, skipping" >&2
	fi
	;;
    --no-default-keyrings)
	GPG_DEFAULT_KEYRINGS=( ) ;;
    --no-conf|--noconf)
	echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
	exit 1 ;;
    --date) WANT_DATE=yes ;;
    --no-date|--nodate) WANT_DATE=no ;;
    --help|-h) usage; exit 0 ;;
    --version) version; exit 0 ;;
    --)	shift; break ;;
    *) echo "$PROGNAME: bug in option parser, sorry!" >&2 ; exit 1 ;;
    esac
    shift
done

# Some useful abbreviations for gpg options
GPG_NO_KEYRING="--no-options --no-auto-check-trustdb --no-default-keyring --keyring /dev/null"
GPG_OPTIONS="--no-options --no-auto-check-trustdb --no-default-keyring"

# Now actually get the reports :)

for package; do
    echo "Uploads for $package:"

    prefix=$(echo $package | sed -re 's/^((lib)?.).*$/\1/')
    pkgurl="http://packages.qa.debian.org/${prefix}/${package}.html"
    baseurl="http://packages.qa.debian.org/${prefix}/"

    # only grab the actual "Accepted" news announcements; hopefully this
    # won't pick up many false positives
    WGETOPTS="-q -O - --timeout=30 "
    count=0
    for news in $(wget $WGETOPTS $pkgurl |
                  sed -ne 's%^.*<a href="\('$package'/news/[0-9A-Z]*\.html\)">Accepted .*%\1%p'); do
	HTML_TEXT=$(wget $WGETOPTS "$baseurl$news")
	GPG_TEXT=$(echo "$HTML_TEXT" |
	           sed -ne 's/^<pre>//; /-----BEGIN PGP SIGNED MESSAGE-----/,/-----END PGP SIGNATURE-----/p')

	test -n "$GPG_TEXT" || continue

	VERSION=$(echo "$GPG_TEXT" | awk '/^Version/ { print $2; exit }')
	DISTRO=$(echo "$GPG_TEXT" | awk '/^Distribution/ { print $2; exit }')
	if [ "$WANT_DATE" = "yes" ]; then
	    DATE=$(echo "$HTML_TEXT" |  sed -ne 's%<li><em>Date</em>: \(.*\)</li>%\1%p')
	fi

	GPG_ID=$(echo "$GPG_TEXT" | LC_ALL=C gpg $GPG_NO_KEYRING --verify 2>&1 |
	         sed -rne 's/.*ID ([0-9A-Z]+).*/\1/p')

	UPLOADER=$(gpg $GPG_OPTIONS \
	           "${GPG_DEFAULT_KEYRINGS[@]}" "${GPG_KEYRINGS[@]}" \
	           --list-key --with-colons $GPG_ID 2>/dev/null |
	           awk  -F: '/@debian\.org>/ { a = $10; exit} /^pub/ { a = $10 } END { print a }' )
	if [ -z "$UPLOADER" ]; then UPLOADER="<unrecognised public key ($GPG_ID)>"; fi

	output="$VERSION to $DISTRO: $UPLOADER" 
	[ "$WANT_DATE" = "yes" ] && output="$output on $DATE"
	echo $output | iconv -c -f UTF-8

	count=$(($count + 1))
	[ $count -eq $MAXUPLOADS ] && break
    done
    test $# -eq 1 || echo
done

exit 0
