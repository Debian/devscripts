#! /bin/bash -e
# tagpending by Joshua Kwan
# Purpose: tag all bugs pending which are not so already
# 
# Copyright 2004 Joshua Kwan <joshk@triplehelix.org>
# Changes copyright 2004-07 by their respective authors.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 (only) of the GNU General Public
# License as published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

usage() {
  cat <<EOF
Usage: tagpending [options]
  Options:
    -n, --noact         Only simulate what would happen during this run, and
                        print the message that would get sent to the BTS.
    -s, --silent        Silent mode
    -v, --verbose       Verbose mode: List bugs checked/tagged. 
                        NOTE: Verbose and silent mode can't be used together.
    -f, --force         Do not query the BTS, (re-)tag all bug reports (force).
    -c, --confirm       Tag bugs as confirmed as well as pending
    -h, --help          This usage screen.
    -V, --version       Display the version and copyright information

  This script will read debian/changelog and tag all bugs not already tagged
  pending as such.  Requires wget to be installed to query BTS.
EOF
}

version() {
  cat <<EOF
This is tagpending, from the Debian devscripts package, version ###VERSION###
This code is (C) 2004 by Joshua Kwan, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

# Defaults
USE_WGET=1
DRY=0
SILENT=0
VERBOSE=0
CONFIRM=0

BTS_BASE_URL="http://bugs.debian.org/cgi-bin/pkgreport.cgi"

while [ -n "$1" ]; do
  case "$1" in
    -n|--noact) DRY=1; shift ;;
    -s|--silent) SILENT=1; shift ;;
    -f|--force) USE_WGET=0; shift ;;
    -V|--version) version; exit 0 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -c|--confirm) CONFIRM=1; shift ;;
    --help | -h) usage; exit 0 ;;
    *)
      echo "tagpending error: unrecognized option $1" >&2
      echo
      usage
      exit 1
    ;;
  esac
done

if [ "$VERBOSE" = "1" ] && [ "$SILENT" = "1" ]; then
    echo "tagpending error: --silent and --verbose contradict each other" >&2
    echo
    usage
    exit 1
fi

if [ "$USE_WGET" = "1" ]  &&  ! command -v wget >/dev/null 2>&1; then
  echo "tagpending error: Sorry, either use the -f option or install the wget package." >&2
  exit 1
fi

for file in debian/changelog debian/control; do
  if [ ! -f "$file" ]; then
    echo "tagpending error: $file does not exist!" >&2
    exit 1
  fi
done

parsed=$(dpkg-parsechangelog)

srcpkg=$(echo "$parsed" | awk '/^Source: / { print $2 }')

changelog_closes=$(echo "$parsed"| awk -F: '/^Closes: / { print $2 }' | \
  xargs -n1 echo)

if [ "$USE_WGET" = "1" ]; then
    bts_pending=$(wget -q -O - "$BTS_BASE_URL?which=src;data=$srcpkg;archive=no;pend-exc=done;include=pending" | \
	sed -ne 's/.*<a href="bugreport.cgi?bug=\([0-9]*\).*/\1/; T; p')
    bts_open=$(wget -q -O - "$BTS_BASE_URL?which=src;data=$srcpkg;archive=no;pend-exc=done" | \
	sed -ne 's/.*<a href="bugreport.cgi?bug=\([0-9]*\).*/\1/; T; p')
fi

to_be_checked=$(printf '%s\n%s\n' "$changelog_closes" "$bts_pending" | sort | uniq -u)

# Now remove the ones tagged in the BTS but no longer in the changelog.
to_be_tagged=""
for bug in $to_be_checked; do
  if [ "$VERBOSE" = "1" ]; then
  	echo -n "Checking bug #$bug: "
  fi
  if ! echo "$bts_pending" | grep -q "^${bug}$"; then
    if echo "$bts_open" | grep -q "^${bug}$" || [ "$USE_WGET" = "0" ] ; then
      if [ "$VERBOSE" = "1" ]; then
	  echo "needs tag"
      fi
      to_be_tagged="$to_be_tagged $bug"
    else
      msg="does not belong to this package (check bug no. or force)"
      if [ "$VERBOSE" = "1" ]; then
	echo "$msg"
      else
	echo "Warning: #$bug $msg."
      fi
    fi
  else
    if [ "$VERBOSE" = "1" ]; then
    	echo "already marked pending"
    fi
  fi
done

if [ -z "$to_be_tagged" ]; then
  if [ "$SILENT" = 0 -o "$DRY" = 1 ]; then
    echo "tagpending info: Nothing to do, exiting."
  fi
  exit 0
fi

# Could use dh_listpackages, but no guarantee that it's installed.
src_packages=$(awk '/Package: / { print $2 } /Source: / { print $2 }' debian/control | sort | uniq)

bugs_info() {
  msg="tagpending info: "

  if [ "$DRY" = 1 ]; then
    msg="$msg would tag"
  else
    msg="$msg tagging"
  fi

  msg="$msg these bugs pending"

  if [ "$CONFIRM" = 1 ]; then
    msg="$msg and confirmed"
  fi
  msg="$msg:"

  for bug in $to_be_tagged; do
    msg="$msg $bug"
  done
  echo $msg | fold -w 78 -s
}

if [ "$DRY" = 1 ]; then
  bugs_info

  exit 0
else
  if [ "$SILENT" = 0 ]; then
    bugs_info
  fi

  BTS_ARGS="package $src_packages"

  for bug in $to_be_tagged; do
    BTS_ARGS="$BTS_ARGS . tag $bug + pending "

    if [ "$CONFIRM" = 1 ]; then
      BTS_ARGS="$BTS_ARGS confirmed"
    fi
  done

  eval bts ${BTS_ARGS}
fi

exit 0
