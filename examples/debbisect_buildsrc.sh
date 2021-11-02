#!/bin/sh
#
# use this script to build a source package with debbisect like this:
#
#    $ DEBIAN_BISECT_SRCPKG=mysrc ./debbisect --cache=./cache "two years ago" yesterday /usr/share/doc/devscripts/examples/debbisect_buildsrc.sh
#
# copy this script and edit it if you want to customize it

set -eu

mmdebstrap --variant=apt unstable \
--aptopt='Apt::Key::gpgvcommand "/usr/share/debuerreotype/scripts/.gpgv-ignore-expiration.sh"' \
--aptopt='Acquire::Check-Valid-Until "false"' \
--customize-hook='chroot "$1" apt-get --yes build-dep '"$DEBIAN_BISECT_SRCPKG" \
--customize-hook="chroot \"\$1\" dpkg-query --showformat '\${binary:Package}=\${Version}\n' --show" \
--customize-hook='chroot "$1" apt-get source --build '"$DEBIAN_BISECT_SRCPKG" \
/dev/null $DEBIAN_BISECT_MIRROR "deb-src $DEBIAN_BISECT_MIRROR unstable main"
