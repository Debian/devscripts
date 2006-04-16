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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA

addtime ()
{
	while read line; do
		echo "`date +%H:%M:%S` $1: $line"
	done
}

OUT=`mktemp /tmp/annotate.XXXXXX` || exit 1
ERR=`mktemp /tmp/annotate.XXXXXX` || exit 1

rm -f $OUT $ERR
mkfifo $OUT $ERR || exit 1

addtime O < $OUT &
addtime E < $ERR &

echo "`date +%H:%M:%S` I: Started $@"
"$@" > $OUT 2> $ERR ; EXIT=$?
rm -f $OUT $ERR
wait

echo "`date +%H:%M:%S` I: Finished with exitcode $EXIT"

exit $EXIT
