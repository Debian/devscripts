#!/bin/sh

echo foo; \
shopt something # BASHISM

echo foo; echo \
shopt something

cat <<EOF \
&>/dev/null #BASHISM
bar
moo
EOF

cat <<EOF
foo\
bar\
moo
EOF
