#!/bin/sh

# http://bugs.debian.org/687450
exit -- 2 # BASHISM
exit 255
exit 256 # BASHISM
exit -1 # BASHISM
