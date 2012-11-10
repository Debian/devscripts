#!/bin/sh

foo=foo
bar=BAR

echo BASHISM: ${foo^f}
echo BASHISM: ${foo^^o}
echo BASHISM: ${bar,B}
echo BASHISM: ${bar,,R}

echo BASHISM: ${foo^}
echo BASHISM: ${foo^^}
echo BASHISM: ${bar,}
echo BASHISM: ${bar,,}

echo BASHISM: ${@^}
echo BASHISM: ${*^^}
echo BASHISM: ${@,}
echo BASHISM: ${*,,}
