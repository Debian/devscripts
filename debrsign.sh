#! /bin/bash

# This program is used to REMOTELY sign a .dsc and .changes file
# pair in the form needed for a legal Debian upload.  It is based on
# dpkg-buildpackage and debsign (which is also part of the devscripts
# package).
#
# In order for this program to work, debsign must be installed
# on the REMOTE machine which will be used to sign your package.
# You should run this program from within the package directory on
# the build machine.
#
# Usage: debrsign [options] [user@]remotehost [changes or dsc file]
# You may also provide the following options, which will be passed
# on to signchanges:
#  -m<maintainer>  Sign using key of <maintainer>
#  -k<key>     The PGP/GPG key ID to use; overrides -m
#  -p<type>    <type> is either pgp or gpg to specify which to use
#  -spgp,-sgpg The program takes arguments like pgp or gpg respectively
#  -S          Source-only .changes file
#  -a<arch>    Debian architecture
#  -t<type>    GNU machine type
#  --help, --version

# Debian GNU/Linux debrsign.
# Copyright 1999 Mike Goldman, all rights reserved
# Modifications copyright 1999 Julian Gilbey <jdg@debian.org>,
# all rights reserved.
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

# Abort if anything goes wrong
set -e

PROGNAME=`basename $0`

usage () {
    echo \
"Usage: debrsign [options] [username@]remotehost [changes or dsc]
  Options:
    -sgpg, -spgp    Sign takes options like GPG, PGP respectively
    -pgpg, -ppgp    Sign using GPG, PGP respectively
    -e<maintainer>  Sign using key of <maintainer> (takes precedence over -m)
    -m<maintainer>  The same as -e
    -k<keyid>       The key to use for signing
    -S              Use changes file made for source-only upload
    -a<arch>        Use changes file made for Debian target architecture <arch>
    -t<target>      Use changes file made for GNU target architecture <target>
    --help          Show this message
    --version       Show version and copyright information
  If a changes or dscfile is specified, it is signed, otherwise
  debian/changelog is parsed to find the changes file.  The signing
  is performed on remotehost using ssh and debsign."
}

version () {
    echo \
"This is debrsign, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999 by Mike Goldman and Julian Gilbey,
all rights reserved.  This program comes with ABSOLUTELY NO WARRANTY.
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

withecho () {
    echo " $@"
    "$@"
}

# --- main script

# For partial security, even though we know it doesn't work :(
# I guess maintainers will have to be careful, and there's no way around
# this in a shell script.
unset IFS
PATH=/usr/local/bin:/usr/bin:/bin
umask `perl -e 'printf "%03o\n", umask | 022'`

# Don't need to read config files here, as nothing significant is set
# by command line parameters.

signargs=
while [ $# != 0 ]
do
    value="`echo x\"$1\" | sed -e 's/^x-.//'`"
    case "$1" in
	-S)	sourceonly="true" ;;
	-a*)	targetarch="$value" ;;
	-t*)	targetgnusystem="$value" ;;
	--help)	usage; exit 0 ;;
	--version)
		version; exit 0 ;;
	-*)	signargs="$signargs '$1'" ;;
	*)	break ;;
    esac
    shift
done

# Command line parameters are remote host (mandatory) and changes file
# name (optional).  If there is no changes file name, we must be at the
# top level of a source tree and will figure out its name from
# debian/changelog
case $# in
    2)	remotehost="$1"
	case "$2" in
	    *.dsc)
		changes=
		dsc=$2
		;;
	    *.changes)
		changes=$2
		dsc=`echo $changes | \
		    perl -pe 's/\.changes$/.dsc/; s/(.*)_(.*)_(.*)\.dsc/\1_\2.dsc/'`
		;;
	    *)	echo "$PROGNAME: Only a .changes or .dsc file is allowed as second argument!" >&2
		exit 1 ;;
	esac
	;;

    1)	remotehost="$1"
	# We have to parse debian/changelog to find the current version
	if [ ! -r debian/changelog ]; then
	    echo "$PROGNAME: Must be run from top of source dir or a .changes file given as arg" >&2
	    exit 1
	fi

	mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" \
	    "source package"
	mustsetvar version "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" \
	    "source version"

	if [ "x$sourceonly" = x ]
	then
	    mustsetvar arch "`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`" "build architecture"
	else
	    arch=source
	fi

	sversion=`echo "$version" | perl -pe 's/^\d+://'`
	pv="${package}_${sversion}"
	pva="${package}_${sversion}${arch:+_${arch}}"
	dsc="../$pv.dsc"
	changes="../$pva.changes"
	;;

    *)	echo "Usage: $PROGNAME [options] [user@]remotehost [.changes or .dsc file]" >&2
	exit 1 ;;
esac

if [ "x$remotehost" == "x" ]
then
        echo "No [user@]remotehost specified!" >&2
        exit 1
fi

changesbase=`basename "$changes"`
dscbase=`basename "$dsc"`

if [ -n "$changes" ]
then
    if [ ! -f "$changes" -o ! -r "$changes" ]
    then
	echo "Can't find or can't read changes file $changes!" >&2
	exit 1
    fi

    # Is there a dsc file listed in the changes file?
    if grep -q "$dscbase" "$changes"
    then
	if [ ! -f "$dsc" -o ! -r "$dsc" ]
	then
	    echo "Can't find or can't read dsc file $dsc!" >&2
	    exit 1
	fi

	# Now do the real work
	withecho scp "$changes" "$dsc" "$remotehost:\$HOME"
	withecho ssh -t "$remotehost" "debsign $signargs $changesbase"
	withecho scp "$remotehost:\$HOME/$changesbase" "$changes"
	withecho scp "$remotehost:\$HOME/$dscbase" "$dsc"
	withecho ssh "$remotehost" "rm -f $changesbase $dscbase"
    else
	withecho scp "$changes" "$remotehost:\$HOME"
	withecho ssh -t "$remotehost" "debsign $signargs $changesbase"
	withecho scp "$remotehost:\$HOME/$changesbase" "$changes"
	withecho ssh "$remotehost" "rm -f $changesbase"
    fi

    echo "Successfully signed changes file"
else
    if [ ! -f "$dsc" -o ! -r "$dsc" ]
    then
	echo "Can't find or can't read dsc file $dsc!" >&2
	exit 1
    fi

    withecho scp "$dsc" "$remotehost:\$HOME"
    withecho ssh -t "$remotehost" "debsign $signargs $dscbase"
    withecho scp "$remotehost:\$HOME/$dscbase" "$dsc"
    withecho ssh "$remotehost" "rm -f $dscbase"

    echo "Successfully signed dsc file"
fi
exit 0
