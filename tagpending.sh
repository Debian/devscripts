#!/bin/sh
# tagpending by Joshua Kwan
# licensed under GPL v2
#
# Purpose: tag all bugs pending which are not so already

set -e

usage() {
  cat <<EOF
Usage: tagpending [options]
  Options:
    -n                  Only simulate what would happen during this run, and
                        print the message that would get sent to the BTS.
    -h, --help          This usage screen.
    -v, --version       Display the version and copyright information

  This script will read debian/changelog and tag all bugs not already tagged
  pending as such, by using the LDAP interface to the bug tracking system.
  Requires ldap-utils to be installed.
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

while [ -n "$1" ]; do
  case "$1" in
    -n) DRY=1; shift ;;
    --version | -v) version; exit 0 ;;
    --help | -h) usage; exit 0 ;;
    *) echo "tagpending error: unrecognized option $1" >&2; echo; help; exit 1 ;;
  esac
done

if ! which ldapsearch >/dev/null 2>&1; then
  echo "tagpending error: Sorry, this package needs ldap-utils installed to function." >&2
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

changelog_closes=$(echo "$parsed"| awk -F: '/^Closes: / { print $2 }' | xargs -n1 echo)

bts_pending=$(ldapsearch -h bugs.debian.org -p 10101 -x -b dc=current,dc=bugs,dc=debian,dc=org "(&(debbugsSourcePackage=$srcpkg)(!(debbugsState=done))(debbugsTag=pending))" | awk '/debbugsID: / { print $2 }' | xargs -n1 echo)

# XXX if there's a bug not closed in the changelog, but only in the BTS,
# it will get retagged
to_be_tagged=$(printf '%s\n%s\n' "$changelog_closes" "$bts_pending" | sort | uniq -u)

if [ -z "$to_be_tagged" ]; then
  echo "tagpending info: Nothing to do, exiting."
  exit 0
fi

# Could use dh_listpackages, but no guarantee that it's installed.
src_packages=$(awk '/Package: / { printf $2 " "}' debian/control)

( 
  IFS="
"
  echo "package $src_packages"  

  for bug in $to_be_tagged; do
    echo "tag $bug + pending"
  done

  echo thanks
) | mail -s 'Tag bugs pending' control@bugs.debian.org
