#! /bin/bash -e
#
# deb-reversion -- a script to bump a .deb file's version number.
#
# The programme has been published under the terms of the Artistic Licence.
# Please see http://www.opensource.org/licenses/artistic-license.php for more
# information.
#
# deb-reversion (c) 2004-5 by martin f. krafft <madduck@debian.org>
# contributors: Goswin von Brederlow, Filippo Giunchedi
#
# TODO: 
#   - add debugging output.
#   - allow to be used on dpkg-source and dpkg-deb unpacked source packages.
#   - export $VERSTR
#   - allow calculation of specified version
#

PROGNAME=${0##*/}
PROGVERSION=0.1.19

blurb()
{
  cat <<EOF
$PROGNAME version $PROGVERSION -- a script to bump a .deb file's version number.
EOF
}

copyright()
{
  cat <<EOF
$PROGNAME is (c) 2004-5 by martin f. krafft <madduck@debian.org>.
This programme is part of devscripts ###VERSION###.

The programme has been published under the terms of the Artistic Licence.
Please see http://www.opensource.org/licenses/artistic-license.php for
more information. On Debian systems, you may find the text of the licence in
/usr/share/common-licenses/Artistic as well.
EOF
}

about()
{
  blurb
  echo
  copyright
} 

usage()
{
  cat <<EOF
Usage:
  $PROGNAME [options] file [log message]

  The script will increase the .deb file's version number, noting the change in
  the package's changelog file. The message written to the changelog may be
  customised. Unless a new version is provided, the script automatically
  calculates one that fits in well with the Debian versioning rules. The new
  .deb file will be placed in the current directory.

  The following options may be specified, using standard conventions:

    -v | --new-version          The new version to be used
    -c | --calculate-only       Only calculate the new version
                                (makes no sense with -v)
    -k | --hook                 Call the specified hook before repacking
    -D | --debug                Debug mode (passed to dpkg-deb)
    -V | --version              Display version information
    -h | --help                 Display this help text
EOF
}

DIR=$(pwd)
SHORTOPTS=hVv:ck:D
LONGOPTS=help,version,new-version:,calculate-only,hook:,debug
# mode will track whether we are reading options, a deb-name or the changelog
# entry
mode=opts

# Need to use eval to handle multiword hooks
TEMP=$(getopt -s bash -o $SHORTOPTS -l $LONGOPTS --n $PROGNAME -- "$@")
eval set -- $TEMP

while [ $# -gt 0 ]; do
  opt=$1
  shift

  if [ "$mode" = opts ]; then
    case $opt in
      -*) unset OPT_STATE;;
      *)
        case $OPT_STATE in
          SET_VERSION)
            VERSION=$opt
            continue;;
          SET_HOOK)
            HOOK=$opt
            continue;;
        esac
    esac
    
    case $opt in
      -h|--help) usage >&2; exit 0;;
      -v|--new-version) OPT_STATE=SET_VERSION;;
      -c|--calculate-only) CALCULATE=1;;
      -k|--hook) OPT_STATE=SET_HOOK;;
      -D|--debug) DPKGDEB_DEBUG=--debug;;
      -V|--version) about >&2; exit 0;;
      --) mode=debfile; continue;;
    esac
  elif [ "$mode" = debfile ]; then
    case $opt in
      /*.deb) DEB=$opt;;
       *.deb) DEB=${DIR}/$opt;;
       *) echo "$PROGNAME error: no .deb file has been specified." >&2
          usage
          exit -1;;
    esac
    mode=log
  else
    LOG="${LOG:+$LOG }$opt"
  fi    
done


if [ -z "$DEB" ]; then
  echo "$PROGNAME error: no .deb file has been specified." >&2
  usage
  exit -1
elif [ ! -f $DEB ]; then
  echo "$PROGNAME error: $.deb does not exist." >&2
  exit -2
fi

if [ -n "$VERSION" -a -n "$CALCULATE" ]; then
  echo "$PROGNAME error: the options -v and -c cannot be used together" >&2
  usage
  exit -1
fi

make_temp_dir()
{
  TMPDIR=$(mktemp -d /tmp/deb-reversion.XXXXXX)
  trap "rm -rf $TMPDIR" 0
  mkdir -p ${TMPDIR}/package
  TMPDIR=${TMPDIR}/package
}

extract_deb_file()
{
  dpkg-deb $DPKGDEB_DEBUG --extract $1 .
  dpkg-deb $DPKGDEB_DEBUG --control $1 DEBIAN
}

get_version()
{
  dpkg --info $1 | sed -ne 's,^[[:space:]]Version: ,,p'
}

bump_version()
{
  VERSTR='+0.local.'
  case $1 in
    *${VERSTR}[0-9]*)
      REV=${1##*${VERSTR}}
      echo ${1%${VERSTR}*}${VERSTR}$((++REV));;
    *-*)
      echo ${1}${VERSTR}1;;
    *) 
      echo ${1}-0${VERSTR}1;;
  esac
}

call_hook()
{
  export VERSION
  sh -c "$HOOK"
}

change_version()
{
  PACKAGE=$(sed -ne 's,^Package: ,,p' DEBIAN/control)
  VERSION=$1
  for i in changelog{,.Debian}.gz; do
    [ -f usr/share/doc/${PACKAGE}/$i ] \
      && LOGFILE=usr/share/doc/${PACKAGE}/$i
  done
  [ -z "$LOGFILE" ] && return 1
  mkdir -p debian
  zcat $LOGFILE > debian/changelog
  shift
  dch -v $VERSION -- $@
  call_hook
  gzip -9 -c debian/changelog >| $LOGFILE
  sed -i -e "s,^Version: .*,Version: $VERSION," DEBIAN/control
  rm -rf debian
}

repack_file()
{
  cd ..
  dpkg-deb -b package >/dev/null
  dpkg-name package.deb | sed -e 's,.*to `\(.*\).,\1,'
}

[ -z "$VERSION" ] && VERSION=$(bump_version $(get_version $DEB))

if [ -n "$CALCULATE" ]; then
  echo $VERSION
  exit 0
fi

if [ `id -u` -ne 0 ]; then
  echo "$PROGNAME error: need to run me as root or using fakeroot!" >&2
  exit -3
fi

make_temp_dir
cd $TMPDIR

extract_deb_file $DEB
change_version $VERSION $LOG
FILE=$(repack_file)

if [ -f $DIR/$FILE ]; then
    echo $DIR/$FILE exists, moving to $DIR/$FILE.orig . >&2
    mv -i $DIR/$FILE $DIR/$FILE.orig
fi

mv ../$FILE $DIR

echo version $VERSION of $PACKAGE is now available in $FILE . >&2
