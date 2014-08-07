#!/bin/bash
#
# deb-reversion -- a script to bump a .deb file's version number.
#
# Copyright © martin f. krafft <madduck@madduck.net>
# with contributions by: Goswin von Brederlow, Filippo Giunchedi
# Released under the terms of the Artistic License 2.0
#
# TODO:
#   - add debugging output.
#   - allow to be used on dpkg-source and dpkg-deb unpacked source packages.
#
set -eu

PROGNAME=${0##*/}
PROGVERSION=0.9.1
VERSTR='LOCAL.'

versioninfo() {
  echo "$PROGNAME $PROGVERSION"
  echo "$PROGNAME is copyright © martin f. krafft"
  echo "Released under the terms of the Artistic License 2.0"
  echo "This programme is part of devscripts ###VERSION###."
}

usage()
{
  cat <<-_eousage
	Usage: $PROGNAME [options] .deb-file [log message]
	       $PROGNAME -o <version> -c

	Increase the .deb file's version number, noting the change in the
	changelog with the specified log message.  You should run this
	program either as root or under fakeroot.

	Options:
	_eousage
  cat <<-_eooptions | column -s\& -t
	-v ver|--new-version=ver & use this as new version number
	-o old|--old-version=ver & calculate new version number based on this old one
	-c|--calculate-only & only calculate (and print) the augmented version
	-s str|--string=str & append this string instead of '$VERSTR' to
	                    & calculate new version number
	-k script|--hook=script & call this script before repacking
	-D|--debug & call dpkg-deb in debug mode
	-b|--force-bad-version & passed through to dch
	-h|--help & show this output
	-V|--version & show version information
	_eooptions
}

write()
{
  local PREFIX; PREFIX="$1"; shift
  echo "${PREFIX}: $PROGNAME: $@" >&2
}

err()
{
  write E "$@"
}

CURDIR="$(pwd)"
SHORTOPTS=hVo:v:ck:Ds:b
LONGOPTS=help,version,old-version:new-version:,calculate-only,hook:,debug,string:,force-bad-version
eval set -- "$(getopt -s bash -o $SHORTOPTS -l $LONGOPTS -n $PROGNAME -- "$@")"

CALCULATE=0
DPKGDEB_DEBUG=
DEB=
DCH_OPTIONS=
for opt in "$@"; do
  case "${OPT_STATE:-}" in
    SET_OLD_VERSION) OLD_VERSION="$opt";;
    SET_NEW_VERSION) NEW_VERSION="$opt";;
    SET_STRING) VERSTR="$opt";;
    SET_HOOK) HOOK="$opt";;
    *) :;;
  esac
  [ -n "${OPT_STATE:-}" ] && unset OPT_STATE && continue

  case $opt in
    -v|--new-version) OPT_STATE=SET_NEW_VERSION;;
    -o|--old-version) OPT_STATE=SET_OLD_VERSION;;
    -c|--calculate-only|--print-only) CALCULATE=1;;
    -s|--string) OPT_STATE=SET_STRING;;
    -k|--hook) OPT_STATE=SET_HOOK;;
    -D|--debug) DPKGDEB_DEBUG=--debug;;
    -b|--force-bad-version) DCH_OPTIONS="${DCH_OPTIONS} -b";;
    -h|--help) usage; exit 0;;
    -V|--version) versioninfo; exit 0;;
    --) :;;
    *)
      if [ -f "$opt" ]; then
        if [ -n "$DEB" ]; then
          err "multiple .deb files specified: ${DEB##*/} and $opt"
          exit 1
        else
          case "$opt" in
            /*.deb|/*.udeb) DEB="$opt";;
             *.deb| *.udeb) DEB="${CURDIR}/$opt";;
            *)
              err "not a .deb file: $opt";
              exit 2
              ;;
          esac
        fi
      else
        LOG="${LOG:+$LOG }$opt"
      fi
      ;;
  esac
done

if [ $CALCULATE -eq 0 ] || [ -z "${OLD_VERSION:-}" ]; then
  if [ -z "$DEB" ]; then
    err no .deb file specified.
    exit 3
  fi
fi

if [ -n "${NEW_VERSION:-}" ] && [ $CALCULATE -eq 1 ]; then
  echo "$PROGNAME error: the options -v and -c cannot be used together" >&2
  usage
  exit 4
fi

make_temp_dir()
{
  TMPDIR=$(mktemp -d --tmpdir deb-reversion.XXXXXX)
  trap "rm -rf $TMPDIR" 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
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
  case "$1" in
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
  [ -z "${HOOK:-}" ] && return 0
  export VERSION
  sh -c "$HOOK"
}

change_version()
{
  PACKAGE=$(sed -ne 's,^Package: ,,p' DEBIAN/control)
  VERSION=$1

  # changelog massaging is only needed in the deb (not-udeb) case:
  if [ "$DEB_TYPE" = "deb" ]; then
    LOGFILE=
    for i in changelog{,.Debian}.gz; do
      [ -f usr/share/doc/${PACKAGE}/$i ] \
        && LOGFILE=usr/share/doc/${PACKAGE}/$i
    done
    [ -z "$LOGFILE" ] && { echo "changelog file not found"; return 1; }
    mkdir -p debian
    zcat $LOGFILE > debian/changelog
    shift
    dch $DCH_OPTIONS -v $VERSION -- $@
    call_hook
    gzip -9 -c debian/changelog >| $LOGFILE
  else
    call_hook
  fi

  sed -i -e "s,^Version: .*,Version: $VERSION," DEBIAN/control
  rm -rf debian
}

repack_file()
{
  cd ..
  dpkg-deb -b package >/dev/null
  debfile=$(dpkg-name package.deb | sed -e "s,.*['\`]\(.*\).,\1,")
  # if Package-Type: udeb is absent, dpkg-name can't rename into *.udeb,
  # so we're left to an extra rename afterwards:
  if [ "$DEB_TYPE" = udeb ]; then
    udebfile=${debfile%%.deb}.udeb
    mv $debfile $udebfile
    echo $udebfile
  else
    echo $debfile
  fi
}

[ -z "${OLD_VERSION:-}" ] && OLD_VERSION="$(get_version $DEB)"
[ -z "${NEW_VERSION:-}" ] && NEW_VERSION="$(bump_version $OLD_VERSION)"

if [ $CALCULATE -eq 1 ]; then
  echo $NEW_VERSION
  exit 0
fi

if [ $(id -u) -ne 0 ]; then
  err need root rights.
  exit 5
fi

make_temp_dir
cd "$TMPDIR"

DEB_TYPE=$(echo "$DEB"|sed 's/.*[.]//')
extract_deb_file "$DEB"
change_version "$NEW_VERSION" "${LOG:-Bumped version with $PROGNAME}"
FILE="$(repack_file)"

if [ -f "$CURDIR/$FILE" ]; then
    echo "$CURDIR/$FILE exists, moving to $CURDIR/$FILE.orig ." >&2
    mv -i "$CURDIR/$FILE" "$CURDIR/$FILE.orig"
fi

mv "../$FILE" "$CURDIR"

echo "version $VERSION of $PACKAGE is now available in $FILE ." >&2
