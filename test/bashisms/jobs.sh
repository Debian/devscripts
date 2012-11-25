#!/bin/sh

# POSIX+UP:
jobs # BASHISM
jobs -l # BASHISM
jobs -p # BASHISM

# Non-POSIX at all:

sleep 10 &
j=$(jobs -p) # possible BASHISM (context changes because of subshell)
jobs -r # BASHISM
jobs -s # BASHISM
jobs -n # BASHISM
jobs -x # BASHISM