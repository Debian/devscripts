#!/bin/sh

printf -v some_var "this is a BASHISM"

printf "the use of %q is bad\n" "BASHISMS" >/dev/null

printf "this is another BASHISM: %b" "\n" >/dev/null

printf "%q leading the string is bad\n" "BASHISMS" >/dev/null
