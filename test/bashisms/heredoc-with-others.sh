#!/bin/sh

cat << =EOF1
function CLEAN() {}
=EOF1

cat << :EOF2
function CLEAN() {}
:EOF2

cat << ,EOF3
function CLEAN() {}
,EOF3

cat << ?EOF4
function CLEAN() {}
?EOF4

cat << E$OF5
function CLEAN() {}
E$OF5

cat << $EOF6
function CLEAN() {}
$EOF6

cat << EOF_7
function CLEAN() {}
EOF_7

cat << EOF;:
function CLEAN() {}
EOF

cat << EOF{}9
function CLEAN() {}
EOF{}9

cat << EOF\ 10
function CLEAN() {}
EOF 10

cat << EOF\;11
function CLEAN() {}
EOF;11

cat << EOF\12
function CLEAN() {}
EOF12

cat << EOF\\13
function CLEAN() {}
EOF\13

cat << EOF\\1\\4
function CLEAN() {}
EOF\1\4

cat << \<EOF15\>
function CLEAN() {}
<EOF15>

cat << "E\OF16"
function CLEAN() {}
E\OF16

cat << 'E\OF17'
function CLEAN() {}
E\OF17

cat << EOF18|:
function CLEAN() {}
EOF18

cat << EOF19>/dev/null
echo -e CLEAN() {}
EOF19
