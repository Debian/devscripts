#!/bin/sh

cat << -EOF1- 1>&2
CLEAN
-EOF1-

cat << -EOF2 1>&2
CLEAN
-EOF2

cat <<-EOF3 1>&2
CLEAN
	EOF3

cat <<- EOF4 1>&2
CLEAN
	EOF4

foo=bar

cat << '-EOF1-' 1>&2
CLEAN $foo
-EOF1-

cat << '-EOF2' 1>&2
CLEAN $foo
-EOF2

cat <<-'EOF3' 1>&2
CLEAN $foo
	EOF3

cat <<- 'EOF4' 1>&2
CLEAN $foo
	EOF4
