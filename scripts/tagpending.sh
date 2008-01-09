#! /bin/bash -e
# tagpending by Joshua Kwan
# Purpose: tag all bugs pending which are not so already
# 
# Copyright 2004 Joshua Kwan <joshk@triplehelix.org>
# Changes copyright 2004-07 by their respective authors.
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
    -t, --to <version>	Use changelog information from all versions strictly
                        later than <version> (mimics dpkg-parsechangelog's -v option.)
    -w, --wnpp		For each potentially not owned bug, check whether it is filed
    			against wnpp and, if so, tag it. This allows e.g. ITA or ITPs
			to be tagged.
    -h, --help          This usage screen.
    -V, --version       Display the version and copyright information

  This script will read debian/changelog and tag all open bugs not already
  tagged pending as such.  Requires wget to be installed to query BTS.
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
WNPP=0

BTS_BASE_URL="http://bugs.debian.org/cgi-bin/pkgreport.cgi"
TAGS="<h3>Tags:"
WNPP_MATCH="Package: <a [^>]*href=\"\\(\\/cgi-bin\\/\\)\\?pkgreport.cgi?pkg=wnpp\">wnpp<\/a>;"

while [ -n "$1" ]; do
  case "$1" in
    -n|--noact) DRY=1; shift ;;
    -s|--silent) SILENT=1; shift ;;
    -f|--force) USE_WGET=0; shift ;;
    -V|--version) version; exit 0 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -c|--confirm) CONFIRM=1; shift ;;
    -t|--to) shift; TO="-v$1"; shift;;
    -w|--wnpp) WNPP=1; shift ;;
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

parsed=$(dpkg-parsechangelog $TO)

srcpkg=$(echo "$parsed" | awk '/^Source: / { print $2 }' | perl -ne 'use URI::Escape; chomp; print uri_escape($_);')

changelog_closes=$(echo "$parsed"| awk -F: '/^Closes: / { print $2 }' | \
  xargs -n1 echo)

if [ "$USE_WGET" = "1" ]; then
    bts_pending=$(wget -q -O - "$BTS_BASE_URL?which=src;data=$srcpkg;archive=no;pend-exc=done;tag=pending" | \
	sed -ne 's/.*<a href="\(\(\/cgi-bin\/\)\?bugreport.cgi?bug=\|\/\)\([0-9]*\).*/\3/; T; p')
    bts_open=$(wget -q -O - "$BTS_BASE_URL?which=src;data=$srcpkg;archive=no;pend-exc=done" | \
	sed -ne 's/.*<a href="\(\(\/cgi-bin\/\)\?bugreport.cgi?bug=\|\/\)\([0-9]*\).*/\3/; T; p')
fi

to_be_checked=$(printf '%s\n%s\n' "$changelog_closes" "$bts_pending" | sort -g | uniq)

# Now remove the ones tagged in the BTS but no longer in the changelog.
to_be_tagged=""
wnpp_to_be_tagged=""
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
      if [ "$WNPP" = "1" ]; then
        wnpp_tags=$( (wget -q -O- http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=$bug; \
          echo $TAGS) | sed -ne "/$WNPP_MATCH/,/^$TAGS/ {/^$TAGS/p}" )

        if [ -n "$wnpp_tags" ]; then
          if ! echo "$wnpp_tags" | grep -q "pending"; then
            if [ "$VERBOSE" = "1" ]; then
              echo "wnpp needs tag"
            fi
            wnpp_to_be_tagged="$wnpp_to_be_tagged $bug"
          else
            if [ "$VERBOSE" = "1" ]; then
              echo "wnpp already marked pending"
            fi
          fi
        else
          msg="is closed or does not belong to this package (check bug no. or force)"
          if [ "$VERBOSE" = "1" ]; then
            echo "$msg"
          else
            echo "Warning: #$bug $msg."
          fi
        fi
      else
        msg="is closed or does not belong to this package (check bug no. or force)"
        if [ "$VERBOSE" = "1" ]; then
          echo "$msg"
        else
	  echo "Warning: #$bug $msg."
        fi
      fi
    fi
    else
      if [ "$VERBOSE" = "1" ]; then
    	echo "already marked pending"
    fi
  fi
done

if [ -z "$to_be_tagged" ] && [ -z "$wnpp_to_be_tagged" ]; then
  if [ "$SILENT" = 0 -o "$DRY" = 1 ]; then
    echo "tagpending info: Nothing to do, exiting."
  fi
  exit 0
fi

# Could use dh_listpackages, but no guarantee that it's installed.
src_packages=$(awk '/Package: / { print $2 } /Source: / { print $2 }' debian/control | sort | uniq)

bugs_info() {
  if [ "$1" = "wnpp" ]; then
    bugs=$wnpp_to_be_tagged
    if [ -z "$bugs" ]; then
      return
    fi
  else
    bugs=$to_be_tagged
  fi

  msg="tagpending info: "

  if [ "$DRY" = 1 ]; then
    msg="$msg would tag"
  else
    msg="$msg tagging"
  fi

  msg="$msg these"

  if [ "$1" = "wnpp" ]; then
    msg="$msg wnpp"
  fi

  msg="$msg bugs pending"

  if [ "$CONFIRM" = 1 ] && [ "$1" != "wnpp" ]; then
    msg="$msg and confirmed"
  fi
  msg="$msg:"

  for bug in $bugs; do
    msg="$msg $bug"
  done
  echo $msg | fold -w 78 -s
}

if [ "$DRY" = 1 ]; then
  bugs_info
  bugs_info wnpp

  exit 0
else
  if [ "$SILENT" = 0 ]; then
    bugs_info
    if [ "$WNPP" = 1 ]; then    
      bugs_info wnpp
    fi
  fi

  if [ -n "$to_be_tagged" ]; then
    BTS_ARGS="package $src_packages"

    for bug in $to_be_tagged; do
      BTS_ARGS="$BTS_ARGS . tag $bug + pending"

      if [ "$CONFIRM" = 1 ]; then
        BTS_ARGS="$BTS_ARGS confirmed"
      fi
    done
  fi

  if [ -n "$wnpp_to_be_tagged" ]; then
    if [ -n "$BTS_ARGS" ]; then
      BTS_ARGS="$BTS_ARGS ."
    fi
    BTS_ARGS="$BTS_ARGS package wnpp"

    for bug in $wnpp_to_be_tagged; do
      BTS_ARGS="$BTS_ARGS . tag $bug + pending"
    done
  fi

  eval bts ${BTS_ARGS}
fi

exit 0
