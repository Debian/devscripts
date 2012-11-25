#!/bin/sh

set -- foo bar moo

echo BASHISM: ${#@}
echo BASHISM: ${#*}

echo BASHISM: ${@%f*}
echo BASHISM: ${*%f*}
echo BASHISM: ${@%%f*}
echo BASHISM: ${*%%f*}

echo BASHISM: ${@#*o}
echo BASHISM: ${*#*o}
echo BASHISM: ${@##*o}
echo BASHISM: ${*##*o}

echo BASHISM: ${@/?/u}
echo BASHISM: ${*/?/u}
echo BASHISM: ${@/?/}
echo BASHISM: ${*/?/}

echo BASHISM: ${@:2}
echo BASHISM: ${*:2}
echo BASHISM: ${@:1:1}
echo BASHISM: ${*:1:1}
