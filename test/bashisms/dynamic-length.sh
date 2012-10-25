#!/bin/sh

len=1
f=foo

echo "${f:1}" # BASHISM
echo "${f:$len}" # BASHISM
echo "${f:$len$len}" # BASHISM
echo "${f:${len}}" # BASHISM
