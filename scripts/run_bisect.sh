#!/bin/sh
#
# Copyright 2020 Johannes Schauer Marin Rodrigues <josch@debian.org>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# this script is part of debbisect and usually called by debbisect itself
#
# it accepts six or eight arguments:
#    1. dependencies
#    2. script name or shell snippet
#    3. mirror URL
#    4. architecture
#    5. suite
#    6. components
#    7. (optional) second mirror URL
#    8. (optional) package to upgrade
#
# It will create an ephemeral chroot using mmdebstrap using (3.) as mirror,
# (4.) as architecture, (5.) as suite and (6.) as components, install the
# dependencies given in (1.) and execute the script given in (2.).
# Its output is the exit code of the script as well as a file ./pkglist
# containing the output of "dpkg-query -W" inside the chroot.
#
# If not only six but eight arguments are given, then the second mirror URL
# (7.) will be added to the apt sources and the single package (8.) will be
# upgraded to its version from (7.).

set -exu

if [ $# -ne 6 ] && [ $# -ne 8 ]; then
	echo "usage: $0 depends script mirror1 architecture suite components [mirror2 toupgrade]"
	exit 1
fi

depends=$1
script=$2
mirror1=$3
architecture=$4
suite=$5
components=$6

if [ $# -eq 6 ]; then
	mmdebstrap \
		--verbose \
		--aptopt='Acquire::Check-Valid-Until "false"' \
		--variant=apt \
		--components="$components" \
		--include="$depends" \
		--architecture="$architecture" \
		--customize-hook='chroot "$1" sh -c "dpkg-query -W > /pkglist"' \
		--customize-hook='download /pkglist ./debbisect.'"$DEBIAN_BISECT_TIMESTAMP"'.pkglist' \
		--customize-hook='rm "$1"/pkglist' \
		--customize-hook='chroot "$1" dpkg -l' \
		--customize-hook="$script" \
		"$suite" \
		- \
		"$mirror1" \
		>/dev/null
elif [ $# -eq 8 ]; then
	mirror2=$7
	toupgrade=$8
	mmdebstrap \
		--verbose \
		--aptopt='Acquire::Check-Valid-Until "false"' \
		--variant=apt \
		--components="$components" \
		--include="$depends" \
		--architecture="$architecture" \
		--customize-hook='echo "deb '"$mirror2 $suite $(echo "$components" | tr ',' ' ')"'" > "$1"/etc/apt/sources.list' \
		--customize-hook='chroot "$1" apt-get update' \
		--customize-hook='chroot "$1" env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get --yes install --no-install-recommends '"$toupgrade" \
		--customize-hook='chroot "$1" sh -c "dpkg-query -W > /pkglist"' \
		--customize-hook='download /pkglist ./debbisect.'"$DEBIAN_BISECT_TIMESTAMP.$toupgrade"'.pkglist' \
		--customize-hook='rm "$1"/pkglist' \
		--customize-hook='chroot "$1" dpkg -l' \
		--customize-hook="$script" \
		"$suite" \
		- \
		"$mirror1" \
		>/dev/null
fi
