#! /bin/bash -e
# tagpending by Joshua Kwan
# licensed under GPL v2
#
# Purpose: tag all bugs pending which are not so already

usage() {
  cat <<EOF
Usage: tagpending [options]
  Options:
    -n                  Only simulate what would happen during this run, and
                        print the message that would get sent to the BTS.
    -s                  Silent mode
    -f                  Do not query the BTS for already tagged bugs (force).
    -h, --help          This usage screen.
    -v, --version       Display the version and copyright information

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

while [ -n "$1" ]; do
  case "$1" in
    -n) DRY=1; shift ;;
    -s) SILENT=1; shift ;;
    -f) USE_WGET=0; shift ;;
    --version) version; exit 0 ;;
    --help | -h) usage; exit 0 ;;
    *)
      echo "tagpending error: unrecognized option $1" >&2
      echo
      usage
      exit 1
    ;;
  esac
done

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
    bts_pending=$(wget -q -O - "http://bugs.debian.org/cgi-bin/pkgreport.cgi?which=src&data=$srcpkg&archive=no&pend-exc=done&include=pending" | \
	sed -ne 's/.*<a href="bugreport.cgi?bug=\([0-9]*\).*/\1/; T; p')
fi

to_be_tagged=$(printf '%s\n%s\n' "$changelog_closes" "$bts_pending" | sort | uniq -u)

# Now remove the ones tagged in the BTS but no longer in the changelog.
to_be_tagged=$(for bug in $to_be_tagged; do
  if ! echo "$bts_pending" | grep -q "^${bug}$"; then
    echo "$bug"
  fi
done)

if [ -z "$to_be_tagged" ]; then
  if [ "$SILENT" = 0 -o "$DRY" = 1 ]; then
    echo "tagpending info: Nothing to do, exiting."
  fi
  exit 0
fi

# Could use dh_listpackages, but no guarantee that it's installed.
src_packages=$(awk '/Package: / { printf $2 " "} /Source: / { printf $2 " " }' debian/control)

IFS="
"

if [ "$DRY" = 1 ]; then
  msg="tagpending info: Would tag these bugs pending:"

  for bug in $to_be_tagged; do
    msg="$msg $bug"
  done
  echo $msg | fold -w 78 -s

  exit 0
else
  if [ "$SILENT" = 0 ]; then
    msg="tagpending info: tagging these bugs pending:"

    for bug in $to_be_tagged; do
      msg="$msg $bug"
    done
    echo $msg | fold -w 78 -s
  fi

  BTS_ARGS="package $src_packages"

  for bug in $to_be_tagged; do
    BTS_ARGS="$BTS_ARGS. tag $bug + pending "
  done

  eval bts ${BTS_ARGS}
fi

exit 0
