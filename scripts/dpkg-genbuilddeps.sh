#!/bin/bash
set -e

PROGNAME=`basename $0`

if [ $# -gt 0 ]; then
    case $1 in
	-h|--help)
	    cat <<EOF
Usage: $PROGNAME [options] [<arg> ...]
Build package and generate build dependencies.
All args are passed to dpkg-buildpackage.
Options:
   -h, --help     This help
   -v, --version  Report version and exit
EOF
	    exit 1
	    ;;
	-v|--version)
	    echo "$PROGNAME wrapper for dpkg-depcheck:"
	    dpkg-depcheck --version
	    exit 1
	    ;;
    esac
fi

if ! [ -x debian/rules ]; then
    echo "$PROGNAME must be run in the source package directory" >&2
    exit 1
fi

if ! dpkg -L build-essential >/dev/null 2>&1
then
    echo "You must have the build-essential package installed to use $PROGNAME" >&2
    echo "You can try running the dpkg-depcheck program directly as:" >&2
    echo "dpkg-depcheck --all dpkg-buildpackage -us -uc -b -rfakeroot $*" >&2
    exit 1
fi

echo "Warning: if this program hangs, kill it and read the manpage!" >&2
dpkg-depcheck -b dpkg-buildpackage -us -uc -b "$@"
