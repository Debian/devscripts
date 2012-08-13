#! /bin/bash
# this script was downloaded from:
# http://jeroen.a-eskwadraat.nl/sw/annotate
# and is part of devscripts ###VERSION###

# Executes a program annotating the output linewise with time and stream
# Version 1.2

# Copyright 2003, 2004 Jeroen van Wolffelaar <jeroen@wolffelaar.nl>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

progname=$(basename $0)

addtime ()
{
	while read line; do
		echo "`date ${FMT}` $1: $line"
	done
}

usage ()
{
	echo \
"Usage: $progname [options] program [args ...]
  Run program and annotate STDOUT/STDERR with a timestamp.

  Options:
   +FORMAT    - Controls the timestamp format as per date(1)
   -h, --help - Show this message"
}

FMT="+%H:%M:%S"
while [ "$1" ]; do
	case "$1" in
	+*)
		FMT="$1"
		shift
		;;
	-h|-help|--help)
		usage
		exit 0
		;;
	*)
		break
		;;
	esac
done

if [ $# -lt 1 ]; then
	usage
	exit 1
fi

cleanup() { __st=$?; rm -rf "$tmp"; exit $__st; }
trap cleanup 0
trap 'exit $?' 1 2 13 15

tmp=$(mktemp -d --tmpdir annotate.XXXXXX) || exit 1
OUT=$tmp/out
ERR=$tmp/err

mkfifo $OUT $ERR || exit 1

addtime O < $OUT &
addtime E < $ERR &

echo "`date ${FMT}` I: Started $@"
"$@" > $OUT 2> $ERR ; EXIT=$?
rm -f $OUT $ERR
wait

echo "`date ${FMT}` I: Finished with exitcode $EXIT"

exit $EXIT
