#!/bin/bash
set -e

# Subscribe to the PTS for a specified package for a limited length of time

PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

usage () {
    echo \
"Usage: $PROGNAME [options] package
  Subscribe to the PTS (Package Tracking System) for the specified package
  for a limited length of time (30 days by default).

  If called as 'pts-unsubscribe', unsubscribe from the PTS for the specified
  package.

  Options:
    -u, --until UNTIL
                   When to unsubscribe; this is given as the command-line
                   argument to at (default: 'now + 30 days')

                   --until 0, --until forever  are synonyms for --forever

    --forever      Do not set an at job for unsubscribing

    --no-conf, --noconf
                   Don't read devscripts config files;
                   must be the first option given

    --help         Display this help message and exit

    --version      Display version information

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2006 by Julian Gilbey, all rights reserved.
Original public domain code by Raphael Hertzog.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

ACTION="subscribe"
if [ "$PROGNAME" = "pts-unsubscribe" ]; then
    ACTION="unsubscribe"
fi

# Boilerplate: set config variables
DEFAULT_PTS_UNTIL='now + 30 days'
VARS="PTS_UNTIL"

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

	set | egrep '^PTS_')

    # check sanity - nothing to do here (at will complain if it's illegal)

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

# Will bomb out if there are unrecognised options
TEMP=$(getopt -s bash -o "u:" \
	--long until:,forever \
	--long no-conf,noconf \
	--long help,version -n "$PROGNAME" -- "$@") || (usage >&2; exit 1)

eval set -- $TEMP

# Process Parameters
while [ "$1" ]; do
    case $1 in
    --until|-u)
	shift
	PTS_UNTIL="$1"
	;;
    --forever)
	PTS_UNTIL="forever" ;;
    --no-conf|--noconf)
	echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
	exit 1 ;;
    --help) usage; exit 0 ;;
    --version) version; exit 0 ;;
    --) shift; break ;;
    *) echo "$PROGNAME: bug in option parser, sorry!" >&2 ; exit 1 ;;
    esac
    shift
done

# Still going?
if [ $# -ne 1 ]; then
    echo "$PROGNAME takes precisely one non-option argument: the package name;" >&2
    echo "try $PROGNAME --help for usage information" >&2
    exit 1
fi

# Check for a "mail" command
if ! command -v mail >/dev/null 2>&1; then
    echo "$PROGNAME: Could not find the \"mail\" command; you must have the" >&2
    echo "bsd-mailx or mailutils package installed to run this script." >&2
    exit 1
fi

pkg=$1

if [ -z "$DEBEMAIL" ]; then
    if [ -z "$EMAIL" ]; then
	echo "$PROGNAME warning: \$DEBEMAIL is not set; attempting to $ACTION anyway" >&2
    else
	echo "$PROGNAME warning: \$DEBEMAIL is not set; using \$EMAIL instead" >&2
	DEBEMAIL=$EMAIL
    fi
fi
DEBEMAIL=$(echo $DEBEMAIL | sed -s 's/^.*[ 	]<\(.*\)>.*/\1/')

if [ "$ACTION" = "unsubscribe" ]; then
    echo "$ACTION $pkg $DEBEMAIL" | mail pts@qa.debian.org
else
    # Check for an "at" command
    if [ "$PTS_UNTIL" != forever -a "$PTS_UNTIL" != 0 ]; then
	if ! command -v at >/dev/null 2>&1; then
	    echo "$PROGNAME: Could not find the \"at\" command; you must have the" >&2
	    echo "\"at\" package installed to run this script." >&2
	    exit 1
	fi

	cd /
	TEMPFILE=$(mktemp --tmpdir pts-subscribe.tmp.XXXXXXXXXX) || { echo "$PROGNAME: Couldn't create tempfile!" >&2; exit 1; }
	trap 'rm -f "$TEMPFILE"' EXIT
	echo "echo 'unsubscribe $pkg $DEBEMAIL' | mail pts@qa.debian.org" | \
	    at $PTS_UNTIL 2>$TEMPFILE
	grep '^job ' $TEMPFILE | sed -e 's/^/Unsubscription will be sent by "at" as /'
    else
	echo "No unsubscription request will be sent"
    fi

    echo "$ACTION $pkg $DEBEMAIL" | mail pts@qa.debian.org
fi
