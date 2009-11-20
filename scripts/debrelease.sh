#! /bin/bash

# debrelease: a devscripts wrapper around dupload/dput which calls
#             dupload/dput with the correct .changes file as parameter.
#             All command line options are passed onto dupload.
#
# Written and copyright 1999-2003 by Julian Gilbey <jdg@debian.org> 
# Based on the original 'release' script by
#  Christoph Lameter <clameter@debian.org>
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

set -e

PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

usage () {
    echo \
"Usage: $PROGNAME [debrelease options] [dupload/dput options]
  Run dupload on the newly created changes file.
  Debrelease options:
    --dupload         Use dupload to upload files (default)
    --dput            Use dput to upload files
    -a<arch>          Search for .changes file made for Debian build <arch>
    -t<target>        Search for .changes file made for GNU <target> arch
    -S                Search for source-only .changes file instead of arch one
    --multi           Search for multiarch .changes file made by dpkg-cross
    --debs-dir DIR    Look for the changes and debs files in DIR instead of
                      the parent of the current package directory
    --check-dirname-level N
                      How much to check directory names before cleaning trees:
                      N=0   never
                      N=1   only if program changes directory (default)
                      N=2   always
    --check-dirname-regex REGEX
                      What constitutes a matching directory name; REGEX is
                      a Perl regular expression; the string \`PACKAGE' will
                      be replaced by the package name; see manpage for details
                      (default: 'PACKAGE(-.*)?')
    --no-conf, --noconf
                      Don't read devscripts config files;
                      must be the first option given
    --help            Show this message
    --version         Show version and copyright information

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999-2003 by Julian Gilbey, all rights reserved.
Based on original code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

mustsetvar () {
    if [ "x$2" = x ]
    then
	echo >&2 "$PROGNAME: unable to determine $3"
	exit 1
    else
	# echo "$PROGNAME: $3 is $2"
	eval "$1=\"\$2\""
    fi
}

# Boilerplate: set config variables
DEFAULT_DEBRELEASE_UPLOADER=dupload
DEFAULT_DEBRELEASE_DEBS_DIR=..
DEFAULT_DEVSCRIPTS_CHECK_DIRNAME_LEVEL=1
DEFAULT_DEVSCRIPTS_CHECK_DIRNAME_REGEX='PACKAGE(-.*)?'
VARS="DEBRELEASE_UPLOADER DEBRELEASE_DEBS_DIR DEVSCRIPTS_CHECK_DIRNAME_LEVEL DEVSCRIPTS_CHECK_DIRNAME_REGEX"

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

	set | egrep "^(DEBRELEASE|DEVSCRIPTS)_")

    # check sanity
    case "$DEBRELEASE_UPLOADER" in
	dupload|dput) ;;
	*) DEBRELEASE_UPLOADER=dupload ;;
    esac

    # We do not replace this with a default directory to avoid accidentally
    # uploading a broken package
    DEBRELEASE_DEBS_DIR="`echo \"$DEBRELEASE_DEBS_DIR\" | sed -e 's%/\+%/%g; s%\(.\)/$%\1%;'`"
    if ! [ -d "$DEBRELEASE_DEBS_DIR" ]; then
	debsdir_warning="config file specified DEBRELEASE_DEBS_DIR directory $DEBRELEASE_DEBS_DIR does not exist!"
    fi

    case "$DEVSCRIPTS_CHECK_DIRNAME_LEVEL" in
	0|1|2) ;;
	*) DEVSCRIPTS_CHECK_DIRNAME_LEVEL=1 ;;
    esac

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


# synonyms
CHECK_DIRNAME_LEVEL="$DEVSCRIPTS_CHECK_DIRNAME_LEVEL"
CHECK_DIRNAME_REGEX="$DEVSCRIPTS_CHECK_DIRNAME_REGEX"


sourceonly=
multiarch=
debsdir="$DEBRELEASE_DEBS_DIR"

while [ $# -gt 0 ]
do
    case "$1" in
    -a*) targetarch="`echo \"$1\" | sed -e 's/^-a//'`" ;;
    -t*) targetgnusystem="`echo \"$1\" | sed -e 's/^-t//'`"
	 # dupload has a -t option
	 if [ -z "$targetgnusystem" ]; then break; fi ;;
    -S) sourceonly=source ;;
    --multi) multiarch=yes ;;
    --dupload) DEBRELEASE_UPLOADER=dupload ;;
    --dput) DEBRELEASE_UPLOADER=dput ;;
    # Delay checking of debsdir until we need it.  We need to make sure we're
    # in the package root directory first.
    --debs-dir=*)
	opt_debsdir="`echo \"$1\" | sed -e 's/^--debs-dir=//; s%/\+%/%g; s%\(.\)/$%\1%;'`"
	;;
    --debs-dir)
	shift
	opt_debsdir="`echo \"$1\" | sed -e 's%/\+%/%g; s%\(.\)/$%\1%;'`"
	;;
    --check-dirname-level=*)
	level="`echo \"$1\" | sed -e 's/^--check-dirname-level=//'`"
        case "$level" in
	0|1|2) CHECK_DIRNAME_LEVEL=$level ;;
	*) echo "$PROGNAME: unrecognised --check-dirname-level value (allowed are 0,1,2)" >&2
	   exit 1 ;;
        esac
	;;
    --check-dirname-level)
	shift
        case "$1" in
	0|1|2) CHECK_DIRNAME_LEVEL=$1 ;;
	*) echo "$PROGNAME: unrecognised --check-dirname-level value (allowed are 0,1,2)" >&2
	   exit 1 ;;
        esac
	;;
    --check-dirname-regex=*)
	regex="`echo \"$1\" | sed -e 's/^--check-dirname-level=//'`"
	if [ -z "$regex" ]; then
	    echo "$PROGNAME: missing --check-dirname-regex parameter" >&2
	    echo "try $PROGNAME --help for usage information" >&2
	    exit 1
	else
	    CHECK_DIRNAME_REGEX="$regex"
	fi
	;;
    --check-dirname-regex)
	shift;
	if [ -z "$1" ]; then
	    echo "$PROGNAME: missing --check-dirname-regex parameter" >&2
	    echo "try $PROGNAME --help for usage information" >&2
	    exit 1
	else
	    CHECK_DIRNAME_REGEX="$1"
	fi
	;;
    --no-conf|--noconf)
	echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
	exit 1 ;;
    --dopts) shift; break ;;  # This is an option for cvs-debrelease,
                              # so we accept it here too, even though we don't
                              # advertise it
    --help) usage; exit 0 ;;
    --version) version; exit 0 ;;
    *) break ;;  # a dupload/dput option, so stop parsing here
    esac
    shift
done

# Look for .changes file via debian/changelog
CHDIR=
until [ -f debian/changelog ]; do
    CHDIR=yes
    cd ..
    if [ `pwd` = "/" ]; then
	echo "$PROGNAME: cannot find debian/changelog anywhere!" >&2
	echo "Are you in the source code tree?" >&2
	exit 1
    fi
done

# Use svn-buildpackage's directory if there is one and debsdir wasn't already
# specified on the command-line.  This can override DEBRELEASE_DEBS_DIR.
if [ -e ".svn/deb-layout" ]; then
    buildArea="$(sed -ne '/^buildArea=/{s/^buildArea=//; s%/\+%/%g; s%\(.\)/$%\1%; p; q}' .svn/deb-layout)"
    if [ -n "$buildArea" -a -d "$buildArea" -a -z "$opt_debsdir" ]; then
	debsdir="$buildArea"
    fi
fi

# check sanity of debdir
if ! [ -d "$debsdir" ]; then
    if [ -n "$debsdir_warning" ]; then
	echo "$PROGNAME: $debsdir_warning" >&2
	exit 1
    else
	echo "$PROGNAME: could not find directory $debsdir!" >&2
	exit 1
    fi
fi

mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" \
    "source package"
mustsetvar version "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" \
    "source version"

if [ $CHECK_DIRNAME_LEVEL -eq 2 -o \
    \( $CHECK_DIRNAME_LEVEL -eq 1 -a "$CHDIR" = yes \) ]; then
    if ! perl -MFile::Basename -w \
	-e "\$pkg='$package'; \$re='$CHECK_DIRNAME_REGEX';" \
	-e '$re =~ s/PACKAGE/\\Q$pkg\\E/g; $pwd=`pwd`; chomp $pwd;' \
	-e 'if ($re =~ m%/%) { eval "exit (\$pwd =~ /^$re\$/ ? 0:1);"; }' \
	-e 'else { eval "exit (basename(\$pwd) =~ /^$re\$/ ? 0:1);"; }'
    then
	echo >&2 <<EOF
$progname: found debian/changelog for package $PACKAGE in the directory
  $pwd
but this directory name does not match the package name according to the
regex  $check_dirname_regex.

To run $progname on this package, see the --check-dirname-level and
--check-dirname-regex options; run $progname --help for more info.
EOF
	exit 1
    fi
fi


if [ "x$sourceonly" = "xsource" ]; then
    arch=source
else
    mustsetvar arch "`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`" "build architecture"
fi

sversion=`echo "$version" | perl -pe 's/^\d+://'`
pva="${package}_${sversion}_${arch}"
pvs="${package}_${sversion}_source"
changes="$debsdir/$pva.changes"
schanges="$debsdir/$pvs.changes"
mchanges=$(ls "$debsdir/${package}_${sversion}_*+*.changes" "$debsdir/${package}_${sversion}_multi.changes" 2>/dev/null | head -1)

if [ -n "$multiarch" ]; then
    if [ -z "$mchanges" -o ! -r "$mchanges" ]; then
	echo "$PROGNAME: could not find/read any multiarch .changes file with name" >&2
	echo "$debsdir/${package}_${sversion}_*.changes" >&2
	exit 1
    fi
    changes=$mchanges
elif [ "$arch" = source ]; then
    if [ -r "$schanges" ]; then
	changes=$schanges
    else
	echo "$PROGNAME: could not find/read changes file $schanges!" >&2
	exit 1
    fi
else
    if [ ! -r "$changes" ]; then
	if [ -r "$mchanges" ]; then
	    changes=$mchanges
	    echo "$PROGNAME: could only find a multiarch changes file:" >&2
	    echo "  $mchanges" >&2
	    echo -n "Should I upload this file? (y/n) " >&2
	    read ans
	    case ans in
		y*) ;;
		*) exit 1 ;;
	    esac
	else
	    echo "$PROGNAME: could not read changes file $changes!" >&2
	    exit 1
	fi
    fi
fi

exec $DEBRELEASE_UPLOADER "$@" "$changes"

echo "$PROGNAME: failed to exec $DEBRELEASE_UPLOADER!" >&2
echo "Aborting...." >&2
exit 1
