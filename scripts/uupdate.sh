#!/bin/bash
#
# Upgrade an existing package
# Christoph Lameter, December 24, 1996
# Many modifications by Julian Gilbey <jdg@debian.org> January 1999 onwards

# Copyright 1999-2003, Julian Gilbey
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
# along with this program. If not, see <https://www.gnu.org/licenses/>.


# Command line syntax is one of:
# For a new archive:
#  uupdate [-v <Version>] [-r <gain-root-command>] [-u] <new upstream archive>
# or
#  uupdate [-r <gain-root-command>] [-u] <new upstream archive> <Version>
# For a patch file:
#  uupdate [-v <Version>] [-r <gain-root-command>] -p <patch>.gz
#
# In the first case, the new version number may be specified explicitly,
# either with the -v option before the archive name, or with a version
# number after the archive file name.  If both are given, the latter
# takes precedence.
#
# The -u option requests that the new .orig.tar.{gz|bz2} archive be the
# pristine source, although this only makes sense when the original
# archive itself is a tar.gz or tgz archive.
#
# Has to be called from within the source archive

PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

usage () {
    echo \
"Usage for a new archive:
  $PROGNAME [options] <new upstream archive> [<version>]
For a patch file:
  $PROGNAME [options] --patch|-p <patch>[.gz|.bz2|.lzma|.xz]
Options are:
   --upstream-version <version>, -v <version>
                      specify version number of upstream package
   --rootcmd <gain-root-command>, -r <gain-root-command>
                      which command to be used to become root
                      for package-building
   --pristine, -u     Source is pristine upstream source and should be
                      copied to <pkg>_<version>.orig.tar.{gz|bz2|lzma|xz}; not valid
                      for patches
   --no-symlink       Copy new upstream archive to new location
                      as <pkg>_<version>.orig.tar.{gz|bz2|lzma|xz} instead of making a
                      symlink
   --no-conf, --noconf
                      Don't read devscripts config files;
                      must be the first option given
   --verbose          Give verbose output

$PROGNAME [--help|--version]
  show this message or give version information.

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
Copyright 1999-2003, Julian Gilbey <jdg@debian.org>, all rights reserved.
Original code by Christoph Lameter.
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

# Match Pattern to extract a new version number from a given filename.
# I already had to fiddle with this a couple of times so I better put it up
# at front.  It is now written as a Perl regexp to make it nicer.  It only
# matches things like: file.3.4 and file2-3.2; it will die on names such
# as file3-2.7a, though.
MPATTERN='^(?:[a-zA-Z][a-zA-Z0-9]*(?:-|_|\.))+(\d+\.(?:\d+\.)*\d+)$'

STATUS=0

# Boilerplate: set config variables
DEFAULT_UUPDATE_ROOTCMD=
DEFAULT_UUPDATE_PRISTINE=yes
DEFAULT_UUPDATE_SYMLINK_ORIG=yes
VARS="UUPDATE_ROOTCMD UUPDATE_PRISTINE UUPDATE_SYMLINK_ORIG"
SUFFIX="1"

if which dpkg-vendor >/dev/null 2>&1; then
    case "$(dpkg-vendor --query Vendor 2>/dev/null)" in
	"Ubuntu")
	    SUFFIX="0ubuntu1"
	    ;;
    esac
fi

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

	set | egrep '^(UUPDATE|DEVSCRIPTS)_')

    # check sanity
    case "$UUPDATE_PRISTINE" in
	yes|no) ;;
	*) UUPDATE_PRISTINE=yes ;;
    esac

    case "$UUPDATE_SYMLINK_ORIG" in
	yes|no) ;;
	*) UUPDATE_SYMLINK_ORIG=yes ;;
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


TEMP=$(getopt -s bash -o v:p:r:ubs \
        --long upstream-version:,patch:,rootcmd: \
	--long pristine,no-pristine,nopristine \
	--long symlink,no-symlink,nosymlink \
	--long no-conf,noconf \
	--long verbose \
	--long help,version -n "$PROGNAME" -- "$@") || (usage >&2; exit 1)

eval set -- $TEMP

# Process Parameters
while [ "$1" ]; do
    case $1 in
    --upstream-version|-v)
	shift; NEW_VERSION="$1" ;;
    --patch|-p)
	shift; PATCH="$1" ;;
    --rootcmd|-r)
	shift; UUPDATE_ROOTCMD="$1" ;;
    --pristine|-u)
	UUPDATE_PRISTINE=yes ;;
    --no-pristine|--nopristine)
	UUPDATE_PRISTINE=no ;;
    --symlink|-s)
	UUPDATE_SYMLINK_ORIG=yes ;;
    --no-symlink|--nosymlink)
	UUPDATE_SYMLINK_ORIG=no ;;
    --no-conf|--noconf)
	echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
	exit 1 ;;
    --verbose)
	UUPDATE_VERBOSE=yes ;;
    --help) usage; exit 0 ;;
    --version) version; exit 0 ;;
    --)	shift; break ;;
    *) echo "$PROGNAME: bug in option parser, sorry!" >&2 ; exit 1 ;;
    esac
    shift
done

if [ -n "$PATCH" ]; then
    if [ $# -ne 0 ]; then
        echo "$PROGNAME: additional archive name/version number is not allowed with --patch" >&2
	echo "Run $PROGNAME --help for usage information" >&2
        exit 1
    fi
else
    case $# in
    0) echo "$PROGNAME: no archive given" >&2 ; exit 1 ;;
    1) ARCHIVE="$1" ;;
    2) ARCHIVE="$1"; NEW_VERSION="$2" ;;
    *) echo "$PROGNAME: too many non-option arguments" >&2
       echo "Run $PROGNAME --help for usage information" >&2
       exit 1 ;;
    esac
fi

# Get Parameters from current source archive

if [ ! -f debian/changelog ]; then
    echo "$PROGNAME: cannot find debian/changelog." >&2
    echo "Are you in the top directory of the source tree?" >&2
    exit 1
fi

# Figure out package info we need
mustsetvar PACKAGE "`dpkg-parsechangelog -SSource`" "source package"
mustsetvar VERSION "`dpkg-parsechangelog -SVersion`" "source version"

# Get epoch and upstream version
eval `echo "$VERSION" | perl -ne '/^(?:(\d+):)?(.*)/; print "SVERSION=$2\nEPOCH=$1\n";'`

if [ -n "$UUPDATE_VERBOSE" ]; then
    echo "PATCH       = \"$PATCH\" is the name of the patch file" >&2
    echo "ARCHIVE     = \"$ARCHIVE\" is the name of the next tarball" >&2
    echo "NEW_VERSION = \"$NEW_VERSION\" is the next pristine tarball version" >&2
    echo "PACKAGE     = \"$PACKAGE\" is in the top of debian/changelog" >&2
    echo "VERSION     = \"$VERSION\" is in the top of debian/changelog" >&2
    echo "EPOCH       = \"$EPOCH\" is epoch part of \$VERSION" >&2
    echo "SVERSION    = \"$SVERSION\" is w/o-epoch part of \$VERSION" >&2
fi

UVERSION=`expr "$SVERSION" : '\(.*\)-[0-9a-zA-Z.+~]*$'`
if [ -z "$UVERSION" ]; then
    echo "$PROGNAME: a native Debian package cannot take upstream updates" >&2
    exit 1
fi

if [ -n "$UUPDATE_VERBOSE" ]; then
    echo "UVERSION    = \"$UVERSION\" the upstream portion w/o-epoch of \$VERSION" >&2
fi

# Save pwd before we goes walkabout
OPWD=`pwd`

if [ "$PATCH" ]; then
    if [ "$ARCHIVE" ]; then
	echo "$PROGNAME: you can only specify a patch or a source code archive, not both!" >&2
	exit 1
    fi
    # do the patching
    X="${PATCH##*/}"
    case "$PATCH" in
	/*)
	    if [ ! -r "$PATCH" ]; then
		echo "$PROGNAME: cannot read patch file $PATCH!  Aborting." >&2
		exit 1
	    fi
	    case "$PATCH" in
		*.gz)  CATPATCH="zcat $PATCH"; X=${X%.gz};;
		*.bz2) CATPATCH="bzcat $PATCH"; X=${X%.bz2};;
		*.lzma) CATPATCH="xz -F lzma -dc $PATCH"; X=${X%.lzma};;
		*.xz) CATPATCH="xzcat $PATCH"; X=${X%.xz};;
		*)     CATPATCH="cat $PATCH";;
	    esac
	    ;;
	*)
	    if [ ! -r "$OPWD/$PATCH" -a ! -r "../$PATCH" ]; then
		echo "$PROGNAME: cannot read patch file $PATCH!  Aborting." >&2
		exit 1
	    fi
	    case "$PATCH" in
		*.gz)
		    if [ -r "$OPWD/$PATCH" ]; then
			CATPATCH="zcat $OPWD/$PATCH"
		    else
			CATPATCH="zcat ../$PATCH"
		    fi
		    X=${X%.gz}
		    ;;
		*.bz2)
		    if [ -r "$OPWD/$PATCH" ]; then
			CATPATCH="bzcat $OPWD/$PATCH"
		    else
			CATPATCH="bzcat ../$PATCH"
		    fi
		    X=${X%.bz2}
		    ;;
		*.lzma)
		    if [ -r "$OPWD/$PATCH" ]; then
			CATPATCH="xz -F lzma -dc $OPWD/$PATCH"
		    else
			CATPATCH="xz -F lzma -dc ../$PATCH"
		    fi
		    X=${X%.lzma}
		    ;;
		*.xz)
		    if [ -r "$OPWD/$PATCH" ]; then
			CATPATCH="xzcat $OPWD/$PATCH"
		    else
			CATPATCH="xzcat ../$PATCH"
		    fi
		    X=${X%.xz}
		    ;;
		*)
		    if [ -r "$OPWD/$PATCH" ]; then
			CATPATCH="cat $OPWD/$PATCH"
		    else
			CATPATCH="cat ../$PATCH"
		    fi
		    ;;
	    esac
	    ;;
    esac
    if [ "$NEW_VERSION" = "" ]; then
	# Figure out the new version; we may have to remove a trailing ".diff"
	NEW_VERSION=`echo "$X" |
		perl -ne 's/\.diff$//; /'"$MPATTERN"'/ && print $1'`
	if [ -z "$NEW_VERSION" ]; then
	    echo "$PROGNAME: new version number not recognized from given filename" >&2
	    echo "Please run $PROGNAME with the -v option" >&2
	    exit 1
	fi

	if [ -n "$EPOCH" ]; then
	    echo "New Release will be $EPOCH:$NEW_VERSION-$SUFFIX."
	else
	    echo "New Release will be $NEW_VERSION-$SUFFIX."
	fi
    fi

    # Strip epoch number
    SNEW_VERSION=`echo "$NEW_VERSION" | perl -pe 's/^\d+://'`
    if [ $SNEW_VERSION = $NEW_VERSION -a -n "$EPOCH" ]; then
	NEW_VERSION="$EPOCH:$NEW_VERSION"
    fi

    # Sanity check
    if dpkg --compare-versions "$NEW_VERSION-$SUFFIX" le "$VERSION"; then
	echo "$PROGNAME: new version $NEW_VERSION-$SUFFIX <= current version $VERSION; aborting!" >&2
	exit 1
    fi

    if [ -e "../$PACKAGE-$SNEW_VERSION" ]; then
	echo "$PROGNAME: $PACKAGE-$SNEW_VERSION already exists in the parent directory!" >&2
	echo "Aborting...." >&2
	exit 1
    fi
    if [ -e "../$PACKAGE-$SNEW_VERSION.orig" ]; then
	echo "$PROGNAME: $PACKAGE-$SNEW_VERSION.orig already exists in the parent directory!" >&2
	echo "Aborting...." >&2
	exit 1
    fi

    # Is the old version a .tar.gz or .tar.bz2 file?
    if [ -r "../${PACKAGE}_$UVERSION.orig.tar.gz" ]; then
	OLDARCHIVE="${PACKAGE}_$UVERSION.orig.tar.gz"
	OLDARCHIVETYPE=gz
    elif [ -r "../${PACKAGE}_$UVERSION.orig.tar.bz2" ]; then
	OLDARCHIVE="${PACKAGE}_$UVERSION.orig.tar.bz2"
	OLDARCHIVETYPE=bz2
    elif [ -r "../${PACKAGE}_$UVERSION.orig.tar.lzma" ]; then
	OLDARCHIVE="${PACKAGE}_$UVERSION.orig.tar.lzma"
	OLDARCHIVETYPE=lzma
    elif [ -r "../${PACKAGE}_$UVERSION.orig.tar.xz" ]; then
	OLDARCHIVE="${PACKAGE}_$UVERSION.orig.tar.xz"
	OLDARCHIVETYPE=xz
    else
	echo "$PROGNAME: can't find/read ${PACKAGE}_$UVERSION.orig.tar.{gz|bz2|lzma|xz}" >&2
	echo "in the parent directory!" >&2
	echo "Aborting...." >&2
	exit 1
    fi

    # Clean package
    if [ -n "$UUPDATE_ROOTCMD" ]; then
	debuild -r"$UUPDATE_ROOTCMD" clean || {
	    echo "$PROGNAME: couldn't run  debuild -r$UUPDATE_ROOTCMD clean" >&2
	    echo "successfully.  Why not?" >&2
	    echo "Aborting...." >&2
	    exit 1
	}
    else debuild clean || {
	    echo "$PROGNAME: couldn't run  debuild -r$UUPDATE_ROOTCMD clean" >&2
	    echo "successfully.  Why not?" >&2
	    echo "Aborting...." >&2
	    exit 1
	}
    fi

    cd ..
    rm -rf $PACKAGE-$UVERSION.orig

    # Unpacking .orig.tar.gz is not quite trivial any longer ;-)
    TEMP_DIR=$(mktemp -d uupdate.XXXXXXXX) || {
	echo "$PROGNAME: can't create temporary directory;" >&2
	echo "aborting..." >&2
	exit 1
    }
    cd $TEMP_DIR
    if [ "$OLDARCHIVETYPE" = gz ]; then
	tar zxf ../$OLDARCHIVE || {
	    echo "$PROGNAME: can't untar $OLDARCHIVE;" >&2
	    echo "aborting..." >&2
	    exit 1
	}
    elif [ "$OLDARCHIVETYPE" = bz2 ]; then
	tar --bzip2 -xf ../$OLDARCHIVE || {
	    echo "$PROGNAME: can't untar $OLDARCHIVE;" >&2
	    echo "aborting..." >&2
	    exit 1
	}
    elif [ "$OLDARCHIVETYPE" = lzma ]; then
	tar --lzma -xf ../$OLDARCHIVE || {
	    echo "$PROGNAME: can't untar $OLDARCHIVE;" >&2
	    echo "aborting..." >&2
	    exit 1
	}
    elif [ "$OLDARCHIVETYPE" = xz ]; then
	tar --xz -xf ../$OLDARCHIVE || {
	    echo "$PROGNAME: can't untar $OLDARCHIVE;" >&2
	    echo "aborting..." >&2
	    exit 1
	}
    else
	echo "$PROGNAME: internal error: unknown OLDARCHIVETYPE: $OLDARCHIVETYPE" >&2
	exit 1
    fi

    if [ `ls | wc -l` -eq 1 ] && [ -d "`ls`" ]; then
	mv "`ls`" ../${PACKAGE}-$UVERSION.orig
    else
	mkdir ../$PACKAGE-$UVERSION.orig
	mv * ../$PACKAGE-$UVERSION.orig
    fi
    cd ..
    rm -rf $TEMP_DIR

    cd $PACKAGE-$UVERSION.orig
    if ! $CATPATCH > /dev/null; then
	echo "$PROGNAME: can't run $CATPATCH;" >&2
	echo "aborting..." >&2
	exit 1
    fi
    if $CATPATCH | patch -sp1; then
	cd ..
	mv $PACKAGE-$UVERSION.orig $PACKAGE-$SNEW_VERSION.orig
	echo "-- Originals could be successfully patched"
	cp -a $PACKAGE-$UVERSION $PACKAGE-$SNEW_VERSION
	cd $PACKAGE-$SNEW_VERSION
	if $CATPATCH | patch -sp1; then
	    echo "Success. The supplied diffs worked fine on the Debian sources."
	else
	    echo "$PROGNAME: the diffs supplied did not apply cleanly!" >&2
	    X=$(find . -name "*.rej" -printf "../$PACKAGE-$SNEW_VERSION/%P\n")
	    if [ -n "$X" ]; then
		echo "Rejected diffs are in $X" >&2
	    fi
	    STATUS=1
	fi
	chmod a+x debian/rules
	debchange -v "$NEW_VERSION-$SUFFIX" "New upstream release"
	echo "Remember: Your current directory is the OLD sourcearchive!"
	echo "Do a \"cd ../$PACKAGE-$SNEW_VERSION\" to see the new package"
	exit
    else
	echo "$PROGNAME: patch failed to apply to original sources $UVERSION" >&2
	cd ..
	rm -rf $PACKAGE-$UVERSION.orig
	exit 1
    fi
else
# This is an original sourcearchive
    if [ "$ARCHIVE" = "" ]; then
	echo "$PROGNAME: upstream source archive not specified" >&2
	exit 1
    fi
    case "$ARCHIVE" in
	/*)
	    if [ ! -r "$ARCHIVE" ]; then
		echo "$PROGNAME: cannot read archive file $ARCHIVE!  Aborting." >&2
		exit 1
	    fi
	    ARCHIVE_PATH="$ARCHIVE"
	    ;;
	*)
	    if [ "$ARCHIVE" = "../${ARCHIVE#../}" -a -r "$ARCHIVE" ]; then
		ARCHIVE_PATH="$ARCHIVE"
	    elif [ -r "../$ARCHIVE" ]; then
		ARCHIVE_PATH="../$ARCHIVE"
	    elif [ -r "$OPWD/$ARCHIVE" ]; then
		ARCHIVE_PATH="$OPWD/$ARCHIVE"
	    else
		echo "$PROGNAME: cannot read archive file $ARCHIVE!  Aborting." >&2
		exit 1
	    fi

	    ;;
    esac

    # Figure out the type of archive
    X="${ARCHIVE%%/}"
    X="${X##*/}"
    if [ ! -d "$ARCHIVE_PATH" ]; then
	case "$X" in
	    *.orig.tar.gz)  X="${X%.orig.tar.gz}";  UNPACK="tar zxf";
	                    TYPE=gz ;;
	    *.orig.tar.bz2) X="${X%.orig.tar.bz2}"; UNPACK="tar --bzip -xf";
	                    TYPE=bz2 ;;
	    *.orig.tar.lzma) X="${X%.orig.tar.lzma}"; UNPACK="tar --lzma -xf";
	                    TYPE=lzma ;;
	    *.orig.tar.xz) X="${X%.orig.tar.xz}"; UNPACK="tar --xz -xf";
	                    TYPE=xz ;;
	    *.tar.gz)  X="${X%.tar.gz}";  UNPACK="tar zxf"; TYPE=gz ;;
	    *.tar.bz2) X="${X%.tar.bz2}"; UNPACK="tar --bzip -xf"; TYPE=bz2 ;;
	    *.tar.lzma) X="${X%.tar.lzma}"; UNPACK="tar --lzma -xf"; TYPE=lzma ;;
	    *.tar.xz)  X="${X%.tar.xz}";  UNPACK="tar --xz -xf"; TYPE=xz ;;
	    *.tar.Z)   X="${X%.tar.Z}";   UNPACK="tar zxf"; TYPE="" ;;
	    *.tgz)     X="${X%.tgz}";     UNPACK="tar zxf"; TYPE=gz ;;
	    *.tar)     X="${X%.tar}";     UNPACK="tar xf";  TYPE="" ;;
	    *.zip)     X="${X%.zip}";     UNPACK="unzip";   TYPE="" ;;
	    *.7z)      X="${X%.7z}";      UNPACK="7z x";    TYPE="" ;;
	    *)
		echo "$PROGNAME: sorry: Unknown archive type" >&2
		exit 1
	esac
    fi

    if [ "$NEW_VERSION" = "" ]; then
	# Figure out the new version
	NEW_VERSION=`echo "$X" | perl -ne "/$MPATTERN/"' && print $1'`
	if [ -z "$NEW_VERSION" ]; then
	    echo "$PROGNAME: new version number not recognized from given filename" >&2
	    echo "Please run $PROGNAME with the -v option" >&2
	    exit 1
	fi
    fi
    if [ -n "$EPOCH" ]; then
	echo "New Release will be $EPOCH:$NEW_VERSION-$SUFFIX."
    else
	echo "New Release will be $NEW_VERSION-$SUFFIX."
    fi

    # Strip epoch number
    SNEW_VERSION=`echo "$NEW_VERSION" | perl -pe 's/^\d+://'`
    if [ $SNEW_VERSION = $NEW_VERSION -a -n "$EPOCH" ]; then
	NEW_VERSION="$EPOCH:$NEW_VERSION"
    fi

    # Sanity check
    if dpkg --compare-versions "$NEW_VERSION-$SUFFIX" le "$VERSION"; then
	echo "$PROGNAME: new version $NEW_VERSION-$SUFFIX <= current version $VERSION; aborting!" >&2
	exit 1
    fi

    if [ -e "../$PACKAGE-$SNEW_VERSION.orig" ]; then
	echo "$PROGNAME: original source tree already exists as $PACKAGE-$SNEW_VERSION.orig!" >&2
	echo "Aborting...." >&2
	exit 1
    fi
    if [ -e "../$PACKAGE-$SNEW_VERSION" ]; then
	echo "$PROGNAME: source tree for new version already exists as $PACKAGE-$SNEW_VERSION!" >&2
	echo "Aborting...." >&2
	exit 1
    fi

    # Sanity checks
    if [ -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.gz" ] && \
	[ "$(md5sum "${ARCHIVE_PATH}" | cut -d" " -f1)" != \
	  "$(md5sum "../${PACKAGE}_$SNEW_VERSION.orig.tar.gz" | cut -d" " -f1)" ]
    then
	echo "$PROGNAME: a different ${PACKAGE}_$SNEW_VERSION.orig.tar.gz" >&2
	echo "already exists in the parent dir;" >&2
	echo "please check on the situation before trying $PROGNAME again." >&2
	exit 1
    elif [ -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.bz2" ] && \
	[ "$(md5sum "${ARCHIVE_PATH}" | cut -d" " -f1)" != \
	  "$(md5sum "../${PACKAGE}_$SNEW_VERSION.orig.tar.bz2" | cut -d" " -f1)" ]
    then
	echo "$PROGNAME: a different ${PACKAGE}_$SNEW_VERSION.orig.tar.bz2" >&2
	echo "already exists in the parent dir;" >&2
	echo "please check on the situation before trying $PROGNAME again." >&2
	exit 1
    elif [ -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.lzma" ] && \
	[ "$(md5sum "${ARCHIVE_PATH}" | cut -d" " -f1)" != \
	  "$(md5sum "../${PACKAGE}_$SNEW_VERSION.orig.tar.lzma" | cut -d" " -f1)" ]
    then
	echo "$PROGNAME: a different ${PACKAGE}_$SNEW_VERSION.orig.tar.lzma" >&2
	echo "already exists in the parent dir;" >&2
	echo "please check on the situation before trying $PROGNAME again." >&2
	exit 1
    elif [ -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.xz" ] && \
	[ "$(md5sum "${ARCHIVE_PATH}" | cut -d" " -f1)" != \
	  "$(md5sum "../${PACKAGE}_$SNEW_VERSION.orig.tar.xz" | cut -d" " -f1)" ]
    then
	echo "$PROGNAME: a different ${PACKAGE}_$SNEW_VERSION.orig.tar.xz" >&2
	echo "already exists in the parent dir;" >&2
	echo "please check on the situation before trying $PROGNAME again." >&2
	exit 1
    fi

    if [ $UUPDATE_PRISTINE = yes -a -n "$TYPE" -a \
	! -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.gz" -a \
	! -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.bz2" -a \
	! -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.lzma" -a \
	! -e "../${PACKAGE}_$SNEW_VERSION.orig.tar.xz" ]; then
	if [ "$UUPDATE_SYMLINK_ORIG" = yes ]; then
	    echo "Symlinking to pristine source from ${PACKAGE}_$SNEW_VERSION.orig.tar.$TYPE..."
	    case $ARCHIVE_PATH in
		/*)   LINKARCHIVE="$ARCHIVE" ;;
		../*) LINKARCHIVE="${ARCHIVE#../}" ;;
	    esac
	else
	    echo "Copying pristine source to ${PACKAGE}_$SNEW_VERSION.orig.tar.$TYPE..."
	fi

	case "$TYPE" in
	    gz)
		if [ "$UUPDATE_SYMLINK_ORIG" = yes ]; then
		    ln -s "$LINKARCHIVE" "../${PACKAGE}_$SNEW_VERSION.orig.tar.gz"
		else
		    cp "$ARCHIVE_PATH" "../${PACKAGE}_$SNEW_VERSION.orig.tar.gz"
		fi
		;;
	    bz2)
		if [ "$UUPDATE_SYMLINK_ORIG" = yes ]; then
		    ln -s "$LINKARCHIVE" "../${PACKAGE}_$SNEW_VERSION.orig.tar.bz2"
		else
		    cp "$ARCHIVE_PATH" "../${PACKAGE}_$SNEW_VERSION.orig.tar.bz2"
		fi
		;;
	    lzma)
		if [ "$UUPDATE_SYMLINK_ORIG" = yes ]; then
		    ln -s "$LINKARCHIVE" "../${PACKAGE}_$SNEW_VERSION.orig.tar.lzma"
		else
		    cp "$ARCHIVE_PATH" "../${PACKAGE}_$SNEW_VERSION.orig.tar.lzma"
		fi
		;;
	    xz)
		if [ "$UUPDATE_SYMLINK_ORIG" = yes ]; then
		    ln -s "$LINKARCHIVE" "../${PACKAGE}_$SNEW_VERSION.orig.tar.xz"
		else
		    cp "$ARCHIVE_PATH" "../${PACKAGE}_$SNEW_VERSION.orig.tar.xz"
		fi
		;;
	    *)
		echo "$PROGNAME: can't preserve pristine sources from non .tar.{gz|bz2|lzma|xz} upstream archive!" >&2
		echo "Continuing anyway..." >&2
		;;
	esac
    fi

    cd ..
    TEMP_DIR=$(mktemp -d uupdate.XXXXXXXX) || {
	echo "$PROGNAME: can't create temporary directory;" >&2
	echo "aborting..." >&2
	exit 1
    }
    cd $TEMP_DIR
    if [ ! -d "$ARCHIVE_PATH" ]; then
	echo "-- Untarring the new sourcecode archive $ARCHIVE"
	$UNPACK "$ARCHIVE_PATH" || {
	    echo "$PROGNAME: can't unpack: $UNPACK $ARCHIVE_PATH failed;" >&2
	    echo "aborting..." >&2
	    exit 1
	}
    else
	tar -C "$ARCHIVE_PATH/../" -c $X | tar x || {
	    echo "$PROGNAME: tar -C \"$ARCHIVE_PATH/../\" -c $X | tar x failed;" >&2
	    echo "aborting..." >&2
	    exit 1
	}
    fi

    cd ..
    if [ `ls $TEMP_DIR | wc -l` -eq 1 ]; then
	# The files are stored in the archive under a top directory, we presume
	mv $TEMP_DIR/* $PACKAGE-$SNEW_VERSION
    else
	# Otherwise, we put them into a new directory
	mkdir $PACKAGE-$SNEW_VERSION
	mv $TEMP_DIR/* $PACKAGE-$SNEW_VERSION
	if ls $TEMP_DIR/.[!.]* >/dev/null 2>&1 ; then
	    mv $TEMP_DIR/.[!.]* $PACKAGE-$SNEW_VERSION
	fi
    fi
    rm -rf $TEMP_DIR
    cp -a $PACKAGE-$SNEW_VERSION $PACKAGE-$SNEW_VERSION.orig
    cd $PACKAGE-$SNEW_VERSION

    if [ -r "../${PACKAGE}_$SVERSION.diff.gz" ]; then
	DIFF="../${PACKAGE}_$SVERSION.diff.gz"
	DIFFTYPE=diff
	DIFFCAT=zcat
    elif [ -r "../${PACKAGE}_$SVERSION.diff.bz2" ]; then
	DIFF="../${PACKAGE}_$SVERSION.diff.bz2"
	DIFFTYPE=diff
	DIFFCAT=bzcat
    elif [ -r "../${PACKAGE}_$SVERSION.diff.lzma" ]; then
	DIFF="../${PACKAGE}_$SVERSION.diff.lzma"
	DIFFTYPE=diff
	DIFFCAT="xz -F lzma -dc"
    elif [ -r "../${PACKAGE}_$SVERSION.diff.xz" ]; then
	DIFF="../${PACKAGE}_$SVERSION.diff.xz"
	DIFFTYPE=diff
	DIFFCAT=xzcat
    elif [ -r "../${PACKAGE}_$SVERSION.debian.tar.gz" ]; then
	DIFF="../${PACKAGE}_$SVERSION.debian.tar.gz"
	DIFFTYPE=tar
	DIFFUNPACK="tar zxf"
    elif [ -r "../${PACKAGE}_$SVERSION.debian.tar.bz2" ]; then
	DIFF="../${PACKAGE}_$SVERSION.debian.tar.bz2"
	DIFFTYPE=tar
	DIFFUNPACK="tar --bzip2 -xf"
    elif [ -r "../${PACKAGE}_$SVERSION.debian.tar.lzma" ]; then
	DIFF="../${PACKAGE}_$SVERSION.debian.tar.lzma"
	DIFFTYPE=tar
	DIFFUNPACK="tar --lzma -xf"
    elif [ -r "../${PACKAGE}_$SVERSION.debian.tar.xz" ]; then
	DIFF="../${PACKAGE}_$SVERSION.debian.tar.xz"
	DIFFTYPE=tar
	DIFFUNPACK="tar --xz -xf"
    fi

    if [ "$DIFFTYPE" = diff ]; then
	# Check that any files added in diff do not now exist in
	# upstream version
	FILES=$($DIFFCAT $DIFF |
	        perl -nwe 'BEGIN { $status=""; }
	                   chomp;
	                   if (/^--- /) { $status = "-$."; }
	                   if (/^\+\+\+ (.*)/ and $status eq ("-" . ($.-1))) {
	                       $file = $1;
	                       $file =~ s%^[^/]+/%%;
	                       $status = "+$.";
	                   }
	                   if (/^@@ -([^ ]+) /) {
	                       if ($1 eq "0,0" and $status eq ("+" . ($.-1))) {
	                           print "$file\n";
	                       }
	                   }')

	# Note that debian/changelog is usually in FILES, so FILES is
	# usually non-null; however, if the upstream ships its own debian/
	# directory, this may not be true, so must check for empty $FILES.
	# Check anyway, even though it's not strictly necessary in bash.
	if [ -n "$FILES" ]; then
	    for file in $FILES; do
		if [ -e "$file" ]; then
		    echo "$PROGNAME warning: file $file was added in old diff, but is now in the upstream source." >&2
		    echo "Please check that the diff is applied correctly." >&2
		    echo "(This program will use the pristine upstream version and save the old .diff.gz" >&2
		    echo "version as $file.debdiff .)" >&2

		    if [ -e "$file.upstream" -o -e "$file.debdiff" ]; then
			FILEEXISTERR=1
		    fi
		fi
	    done

	    if [ -n "$FILEEXISTERR" ]; then
		echo "$PROGNAME: please apply the diff by hand and take care with this." >&2
		exit 1
	    fi

	    # Shift any files that are in the upstream tarball that are also in
	    # the old diff out of the way so the diff is more likely to apply
	    # cleanly, and remember the fact that we moved it
	    for file in $FILES; do
		if [ -e "$file" ]; then
		    mv $file $file.upstream
		    MOVEDFILES=("${MOVEDFILES[@]}" "$file")
		fi
	    done
	fi

	# Remove all existing symlinks before applying the patch.  We'll
	# restore them afterwards, but this avoids patch following symlinks,
	# which may point outside of the source tree
	declare -a LINKS
	while IFS= read -d '' -r link; do
	    LINKS+=("$link")
	done < <(find -type l -printf '%l\0%p\0' -delete)

	if $DIFFCAT $DIFF | patch -sNp1 ; then
	    echo "Success!  The diffs from version $VERSION worked fine."
	else
	    echo "$PROGNAME: the diffs from version $VERSION did not apply cleanly!" >&2
	    X=$(find . -name "*.rej")
	    if [ -n "$X" ]; then
		echo "Rejected diffs are in $X" >&2
	    fi
	    STATUS=1
	fi

	# Reinstate symlinks, warning for any which fail
	for (( i=0; $i < ${#LINKS[@]}; i=$(($i+2)) )); do
	    target="${LINKS[$i]}"
	    link="${LINKS[$(($i+1))]}"
	    if ! ln -s -T "$target" "$link"; then
		echo "$PROGNAME: warning: Unable to restore the '$link' -> '$target' symlink." >&2
		STATUS=1
	    fi
	done

	for file in "${MOVEDFILES[@]}"; do
	    if [ -e "$file.upstream" ]; then
		mv $file $file.debdiff
		mv $file.upstream $file
	    fi
	done

    elif [ "$DIFFTYPE" = tar ]; then
	if [ -d debian ]; then
	    echo "$PROGNAME warning: using a debian.tar.{gz|bz2|lzma|xz} file in old Debian source," >&2
	    echo "but upstream also contains a debian/ directory!" >&2
	    if [ -e "debian.upstream" ]; then
		echo "Please apply the diff by hand and take care with this." >&2
		exit 1
	    fi
	    echo "This program will move the upstream directory out of the way" >&2
	    echo "to debian.upstream/ and use the Debian version" >&2
	    mv debian debian.upstream
	fi
	if [ -n "$UUPDATE_VERBOSE" ]; then
	    echo "-- Use ${DIFF} to create the new debian/ directory." >&2
	fi
	if $DIFFUNPACK $DIFF; then
	    echo "Unpacking the debian/ directory from version $VERSION worked fine."
	else
	    echo "$PROGNAME: failed to unpack the debian/ directory from version $VERSION!" >&2
	    exit 1
	fi
    else
	echo "$PROGNAME: could not find {diff|debian.tar}.{gz|bz2|lzma|xz} from version $VERSION to apply!" >&2
	exit 1
    fi
    if [ -f debian/rules ]; then
	chmod a+x debian/rules
    fi
    if [ -n "$UUPDATE_VERBOSE" ]; then
	echo "-- New upstream release=$NEW_VERSION-$SUFFIX" >&2
    fi
    debchange -v "$NEW_VERSION-$SUFFIX" "New upstream release"
    echo "Remember: Your current directory is the OLD sourcearchive!"
    echo "Do a \"cd ../$PACKAGE-$SNEW_VERSION\" to see the new package"
fi

if [ $STATUS -ne 0 ]; then
    echo "(Did you see the warnings above?)" >&2
fi

exit $STATUS
