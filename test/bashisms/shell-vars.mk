#!/usr/bin/make -f

foo:
	read foo bar | echo $$foo and $$bar
	echo my pid: $$$$
