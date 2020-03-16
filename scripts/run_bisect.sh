#!/bin/sh
#
# Copyright 2020 Johannes 'josch' Schauer <josch@debian.org>
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
# it accepts five or seven arguments:
#    1. dependencies
#    2. script name or shell snippet
#    3. mirror URL
#    4. suite
#    5. components
#    6. (optional) second mirror URL
#    7. (optional) package to upgrade
#
# It will create an ephemeral chroot using mmdebstrap using (3.) as mirror,
# (4.) as suite and 5. as components, install the dependencies given in (1.)
# and execute the script given in (2.).
# Its output is the exit code of the script as well as a file ./pkglist
# containing the output of "dpkg-query -W" inside the chroot.
#
# If not only five but seven arguments are given, then the second mirror URL
# (6.) will be added to the apt sources and the single package (7.) will be
# upgraded to its version from (6.).

set -exu

if [ $# -ne 5 ] && [ $# -ne 7 ]; then
	echo "usage: $0 depends script mirror1 suite components [mirror2 toupgrade]"
	exit 1
fi

depends=$1
script=$2
mirror1=$3
suite=$4
components=$5

if [ $# -eq 5 ]; then
	mmdebstrap \
		--verbose \
		--aptopt='Acquire::Check-Valid-Until "false"' \
		--variant=apt \
		--components="$components" \
		--include="$depends" \
		--customize-hook='chroot "$1" sh -c "dpkg-query -W > /pkglist"' \
		--customize-hook='download /pkglist ./pkglist' \
		--customize-hook='rm "$1"/pkglist' \
		--customize-hook='chroot "$1" dpkg -l' \
		--customize-hook="$script" \
		"$suite" \
		- \
		"$mirror1" \
		>/dev/null
elif [ $# -eq 7 ]; then
	mirror2=$6
	toupgrade=$7
	mmdebstrap \
		--verbose \
		--aptopt='Acquire::Check-Valid-Until "false"' \
		--variant=apt \
		--components="$components" \
		--include="$depends" \
		--customize-hook='echo "deb '"$mirror2 $suite $(echo "$components" | tr ',' ' ')"'" > "$1"/etc/apt/sources.list' \
		--customize-hook='chroot "$1" apt-get update' \
		--customize-hook='chroot "$1" env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get --yes install '"$toupgrade" \
		--customize-hook='chroot "$1" sh -c "dpkg-query -W > /pkglist"' \
		--customize-hook='download /pkglist ./pkglist' \
		--customize-hook='rm "$1"/pkglist' \
		--customize-hook='chroot "$1" dpkg -l' \
		--customize-hook="$script" \
		"$suite" \
		- \
		"$mirror1" \
		>/dev/null
fi
