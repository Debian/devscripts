#!/bin/sh

foo="
echo -e nothing wrong here
#crap"

echo -e BASHISM

foo="\
#crap"

echo -e BASHISM

case foo in
    *\'*)
	echo -e BASHISM
	;;
esac
#'
echo -e BASHISM

case foo in
    *\\"*")
	echo -e BASHISM
	;;
    *\\\"*)
	echo -e BASHISM
	;;
    *\"*)
	echo -e BASHISM
	;;
esac
#"
echo -e BASHISM

foo='\'
echo -e BASHISM
