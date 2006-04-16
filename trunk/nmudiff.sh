#! /bin/bash -e
# Copyright 2006 by Steinar H. Gunderson
# Licensed under the GPL version 2.

if ! command -v mutt >/dev/null 2>&1; then
    echo "nmudiff: requires mutt to be installed to run!" >&2
    exit 1
fi

SOURCE=$( dpkg-parsechangelog | grep ^Source: | cut -d" " -f2 )
VERSION=$( dpkg-parsechangelog | grep ^Version: | cut -d" " -f2 )
OLDVERSION=$( dpkg-parsechangelog -v~ \
  | sed -n "s/^ [^ .][^ ]* (\(.*\)).*$/\1/p" | head -2 | tail -1 )

VERSION_NO_EPOCH=$( echo "$VERSION" | sed "s/^[0-9]\+://" )
OLDVERSION_NO_EPOCH=$( echo "$OLDVERSION" | sed "s/^[0-9]\+://" )

debdiff ../${SOURCE}_${OLDVERSION_NO_EPOCH}.dsc \
  ../${SOURCE}_${VERSION_NO_EPOCH}.dsc \
  > ../${SOURCE}-${VERSION_NO_EPOCH}-nmu.diff
sensible-editor ../${SOURCE}-${VERSION_NO_EPOCH}-nmu.diff

TMPNAM=$( tempfile )
cat <<EOF >$TMPNAM
Package: $SOURCE
Version: $OLDVERSION
Severity: normal
Tags: patch

Hi,

Attached is the diff for my $SOURCE $VERSION NMU.
EOF

mutt -s "diff for $VERSION NMU" -i $TMPNAM \
  -a ../${SOURCE}-${VERSION_NO_EPOCH}-nmu.diff submit@bugs.debian.org
rm $TMPNAM

