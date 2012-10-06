#! /bin/bash -e

# cvs-debi:  Install current version of deb package
# cvs-debc:  List contents of current version of deb package
#
# Based on debi/debc; see them for copyright information
# Based on cvs-buildpackage, copyright 1997 Manoj Srivastava
# (CVS Id: cvs-buildpackage,v 1.58 2003/08/22 17:24:29 srivasta Exp)
# This code is copyright 2003, Julian Gilbey <jdg@debian.org>
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
# along with this program. If not, see <http://www.gnu.org/licenses/>.

PROGNAME=`basename $0 .sh`  # .sh for debugging purposes

usage () {
    if   [ "$PROGNAME" = cvs-debi ];  then usage_i
    elif [ "$PROGNAME" = cvs-debc ];  then usage_c
    else echo "Unrecognised invocation name: $PROGNAME" >&2; exit 1
    fi;
}

usage_i () {
    echo \
"Usage: $PROGNAME [options] [package ...]
  Install the .deb file(s) just created by cvs-buildpackage or cvs-debuild,
  as listed in the .changes file generated on that run.  If packages are
  listed, only install those specified binary packages from the .changes file.

  Note that unlike cvs-buildpackage, the only way to specify the
  source package name is with the -P option; you cannot simply have it
  as the last parameter.

  Also uses the cvs-buildpackage configuration files to determine the
  location of the build tree, as described in the manpage.

  Available options:
    -M<module>        CVS module name
    -P<package>       Package name
    -V<version>       Package version
    -T<tag>           CVS tag to use
    -R<root dir>      Root directory
    -W<work dir>      Working directory
    -x<prefix>        CVS default module prefix
    -a<arch>          Search for .changes file made for Debian build <arch>
    -t<target>        Search for .changes file made for GNU <target> arch
    --help            Show this message
    --version         Show version and copyright information
  Other cvs-buildpackage options will be silently ignored."
}

usage_c () {
    echo \
"Usage: $PROGNAME [options] [package ...]
  Display the contents of the .deb file(s) just created by
  cvs-buildpackage or cvs-debuild, as listed in the .changes file generated
  on that run.  If packages are listed, only display those specified binary
  packages from the .changes file.

  Note that unlike cvs-buildpackage, the only way to specify the
  source package name is with the -P option; you cannot simply have it
  as the last parameter.

  Also uses the cvs-buildpackage configuration files to determine the
  location of the build tree, as described in its manpage.

  Available options:
    -M<module>        CVS module name
    -P<package>       Package name
    -V<version>       Package version
    -T<tag>           CVS tag to use
    -R<root dir>      Root directory
    -W<work dir>      Working directory
    -x<prefix>        CVS default module prefix
    -a<arch>          Search for .changes file made for Debian build <arch>
    -t<target>        Search for .changes file made for GNU <target> arch
    --help            Show this message
    --version         Show version and copyright information
  Other cvs-buildpackage options will be silently ignored."
}

version () { echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2003, Julian Gilbey <jdg@debian.org>,
all rights reserved.
Based on original code by Christoph Lameter and Manoj Srivastava.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of
the GNU General Public License, version 2 or later."
}

setq() {
    # Variable Value Doc string
    if [ "x$2" = "x" ]; then
	echo >&2 "$progname: Unable to determine $3"
	exit 1;
    else
	if [ ! "x$Verbose" = "x" ]; then
	    echo "$progname: $3 is $2";
	fi
	eval "$1=\"\$2\"";
    fi
}

# Is cvs-buildpackage installed?
if ! command -v cvs-buildpackage >/dev/null 2>&1; then
    echo "$PROGNAME: need the cvs-buildpackage package installed to run this" >&2
    exit 1
fi

# Long term variables, which may be set in the cvsdeb config file or the
# environment:
# rootdir workdir (if all original sources are kept in one dir)

TEMPDIR=$(mktemp -dt cvs-debi.XXXXXXXX) || {
    echo "$PROGNAME: unable to create temporary directory" >&2
    echo "Aborting..." >&2
    exit 1
}
TEMPFILE=$TEMPDIR/cl-tmp
trap "rm -f $TEMPFILE; rmdir $TEMPDIR" 0 1 2 3 7 10 13 15

TAGOPT=

# Command line; will bomb out if unrecognised options
TEMP=$(getopt -a -s bash \
       -o hC:EH:G:M:P:R:T:U:V:W:Ff:dcnr:x:Bp:Dk:a:Sv:m:e:i:I:t: \
       --long help,version,ctp,tC,sgpg,spgp,us,uc,op \
       --long si,sa,sd,ap,sp,su,sk,sr,sA,sP,sU,sK,sR,ss,sn \
       -n "$PROGNAME" -- "$@")
eval set -- $TEMP

while true ; do
    case "$1" in
        -h|--help)   usage;   exit 0  ; shift   ;;
        --version)   version; exit 0  ; shift   ;;
	-M) opt_cvsmodule="$2"        ; shift 2 ;;
	-P) opt_package="$2"          ; shift 2 ;;
	-R) opt_rootdir="$2"          ; shift 2 ;;
	-T) opt_tag="$2"              ; shift 2 ;;
	-V) opt_version="$2"          ; shift 2 ;;
	-W) opt_workdir="$2"          ; shift 2 ;;
	-x) opt_prefix="$2"           ; shift 2 ;;
        -a) targetarch="$2"           ; shift 2 ;;
        -t) if [ "$2" != "C" ]; then targetgnusystem="$2"; fi
	                              shift 2 ;;

	# everything else is silently ignored
	-[CHfGUr])                      shift 2 ;;
	-[FnE])                         shift   ;;
       --ctp|--op|--tC)                 shift   ;;
	-[dDBbS])                       shift   ;;
        -p)                             shift 2 ;;
       --us|--uc|--sgpg|--spgp)         shift   ;;
       --s[idapukrAPUKRns])             shift   ;;
       --ap)                            shift   ;;
        -[kvmeiI])                      shift 2 ;;

        --) shift ; break ;;
         *) echo >&2 "Internal error! ($1)"
            usage; exit 1 ;;
    esac
done

if [ "x$opt_cvsmodule" = "x" -a "x$opt_package" = "x" -a \
      ! -e 'debian/changelog' ] ; then
    echo >&2 "$progname should be run in the top working directory of"
    echo >&2 "a Debian Package, or an explicit package (or CVS module) name"
    echo >&2 "should be given."
    exit 1
fi

if [ "x$opt_tag" != "x" ]; then
    TAGOPT=-r$opt_tag
fi

# Command line, env variable, config file, or default
# This anomalous position is in case we need to check out the changelog
# below (anomalous since we have not loaded the config file yet)
if [ ! "x$opt_prefix" = "x" ]; then
    prefix="$opt_prefix"
elif [ ! "x$CVSDEB_PREFIX" = "x" ]; then
    prefix="$CVSDEB_PREFIX"
elif [ ! "x$conf_prefix" = "x" ]; then
    prefix="$conf_prefix"
else
    prefix=""
fi

# put a slash at the end of the prefix
if [ "X$prefix" != "X" ]; then
    prefix="$prefix/";
    prefix=`echo $prefix | sed 's://:/:g'`;
fi

if [ ! -f CVS/Root ]; then
    if [ "X$CVSROOT" = "X" ]; then
	echo "no CVS/Root file found, and CVSROOT var is empty" >&2
	exit 1
    fi
else
    CVSROOT=$(cat CVS/Root)
    export CVSROOT
fi

if [ "x$opt_package" = "x" ]; then
    # Get the official package name and version.
    if [ -f debian/changelog ]; then
	# Ok, changelog exists
	 setq "package" \
	    "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" \
		"source package"
	setq "version" \
	    "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" \
		"source version"
    elif [ "x$opt_cvsmodule" != "x" ]; then
	# Hmm. Well, see if we can checkout the changelog file
	rm -f $TEMPFILE
	cvs -q co -p $TAGOPT $opt_cvsmodule/debian/changelog > $TEMPFILE
        setq "package" \
	    "`dpkg-parsechangelog -l$TEMPFILE | sed -n 's/^Source: //p'`" \
          "source package"
        setq "version" \
          "`dpkg-parsechangelog -l$TEMPFILE | sed -n 's/^Version: //p'`" \
          "source version"
        rm -f "$TEMPFILE"
    else
	# Well. We don't know what this package is.
	echo >&2 " This does not appear be a Debian source tree, since"
	echo >&2 " theres is no debian/changelog, and there was no"
	echo >&2 " package name or cvs module given on the comand line"
	echo >&2 " it is hard to figure out what the package name "
	echo >&2 " should be. I give up."
	exit 1
    fi
else
    # The user knows best; package name is provided
    setq "package" "$opt_package" "source package"

    # Now, the version number
    if [ "x$opt_version" != "x" ]; then
	# All hail the user provided value
	setq "version" "$opt_version" "source package"
    elif [ -f debian/changelog ]; then
	# Fine, see what the changelog says
	setq "version" \
	    "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" \
		"source version"
    elif [ "x$opt_cvsmodule" != "x" ]; then
	# Hmm. The CVS module name is known, so lets us try exporting changelog
	rm -f $TEMPFILE
	cvs -q co -p $TAGOPT $opt_cvsmodule/debian/changelog > $TEMPFILE
        setq "version" \
          "`dpkg-parsechangelog -l$TEMPFILE | sed -n 's/^Version: //p'`" \
          "source version"
        rm -f "$TEMPFILE"
    else
	# Ok, try exporting the package name
	rm -f $TEMPFILE
	cvsmodule="${prefix}$package"
	cvs -q co -p $TAGOPT $cvsmodule/debian/changelog > $TEMPFILE
        setq "version" \
          "`dpkg-parsechangelog -l$TEMPFILE | sed -n 's/^Version: //p'`" \
          "source version"
        rm -f "$TEMPFILE"
    fi
fi

rm -f $TEMPFILE
rmdir $TEMPDIR
trap "" 0 1 2 3 7 10 13 15


non_epoch_version=$(echo -n "$version" | perl -pe 's/^\d+://')
upstream_version=$(echo -n "$non_epoch_version" | sed  -e 's/-[^-]*$//')
debian_version=$(echo -n $non_epoch_version |  perl -nle 'm/-([^-]*)$/ && print $1')

# The default
if [ "X$opt_rootdir" != "X" ]; then
    rootdir="$opt_rootdir"
else
    rootdir='/usr/local/src/Packages'
fi

if [ "X$opt_workdir" != "X" ]; then
    workdir="$opt_workdir"
else
    workdir="$rootdir/$package"
fi

# Load site defaults and over rides.
if [ -f /etc/cvsdeb.conf ]; then
    . /etc/cvsdeb.conf
fi

# Load user defaults and over rides.
if [ -f ~/.cvsdeb.conf ]; then
    . ~/.cvsdeb.conf
fi

# Command line, env variable, config file, or default
if [ ! "x$opt_rootdir" = "x" ]; then
    rootdir="$opt_rootdir"
elif [ ! "x$CVSDEB_ROOTDIR" = "x" ]; then
    rootdir="$CVSDEB_ROOTDIR"
elif [ ! "x$conf_rootdir" = "x" ]; then
    rootdir="$conf_rootdir"
fi

# Command line, env variable, config file, or default
if [ ! "x$opt_workdir" = "x" ]; then
    workdir="$opt_workdir"
elif [ ! "x$CVSDEB_WORKDIR" = "x" ]; then
    workdir="$CVSDEB_WORKDIR"
elif [ ! "x$conf_workdir" = "x" ]; then
    workdir="$conf_workdir"
else
    workdir="$rootdir/$package"
fi

if [ ! -d "$workdir" ]; then
    echo >&2 "The working directory, $workdir, does not exist. Aborting."
    if [ ! -d "$rootdir" ]; then
	echo >&2 "The root directory, $rootdir, does not exist either."
    fi
    exit 1;
fi

# The next part is based on debi

setq arch "`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`" "build architecture"

pva="${package}_${non_epoch_version}_${arch}"
changes="$pva.changes"

cd $workdir || {
    echo "Couldn't cd $workdir.  Aborting" >&2
    exit 1
}

if [ ! -r "$changes" ]; then
    echo "Can't read $workdir/$changes!  Have you built the package yet?" >&2
    exit 1
fi

# Just call debc/debi respectively, now that we have a changes file

SUBPROG=${PROGNAME#cvs-}

exec $SUBPROG --check-dirname-level 0 $changes "$@"
