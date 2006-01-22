#! /bin/sh

# who-uploads sourcepkg [ sourcepkg ... ]
# Tells you who made the latest $MAX_NEWS_ITEM uploads of a source
# package.

# (C) Adeodato Simó <dato@net.com.org.es>
# This file is licensed under the GPLv2.

# BUG: there can be other new items than uploads
# TODO: make it a command line option
MAX_NEWS_ITEM=3

GPG_NO_KEYRING="gpg --no-options --no-default-keyring --keyring /dev/null"
GPG_DEBIAN_KEYRING="gpg --no-options --no-default-keyring"

# Add path to the Debian keyrings here
# GPG_DEBIAN_KEYRING="$GPG_DEBIAN_KEYRING --keyring /usr/share/keyrings/debian-keyring.gpg"
# GPG_DEBIAN_KEYRING="$GPG_DEBIAN_KEYRING --keyring /usr/share/keyrings/debian-keyring.pgp"
GPG_DEBIAN_KEYRING="$GPG_DEBIAN_KEYRING --keyring /var/local/keyring/keyrings/debian-keyring.gpg"
GPG_DEBIAN_KEYRING="$GPG_DEBIAN_KEYRING --keyring /var/local/keyring/keyrings/debian-keyring.pgp"

for package; do
    echo $package

    prefix=`echo $package | sed -re 's/^((lib)?.).*$/\1/'`
    BASE_URL="http://packages.qa.debian.org/${prefix}/${package}/news"

    for n in `seq 1 "$MAX_NEWS_ITEM"`; do
    	GPG_TEXT=$(lynx -dump "${BASE_URL}/${n}.html" |
	           sed -ne '/-----BEGIN PGP SIGNED MESSAGE-----/,/-----END PGP SIGNATURE-----/p')

	test -n "$GPG_TEXT" || continue

	VERSION=$( echo "$GPG_TEXT" | awk '/^Version/ {print $2; exit}' )

	GPG_ID=$( echo "$GPG_TEXT" | $GPG_NO_KEYRING --verify 2>&1 |
	          perl -ne 'm/ID (\w+)/ && print "$1\n"' )

	UPLOADER=$( $GPG_DEBIAN_KEYRING --list-key --with-colons $GPG_ID |
	            awk  -F: '/@debian\.org>/ { a = $10; exit} /^pub/ { a = $10 } END { print a }' )

	echo $VERSION $UPLOADER
    done
    test $# -eq 1 || echo
done
