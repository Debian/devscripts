#!/bin/sh

case "foo" in
    foo)
	echo once
	;& # BASHISM
    moo)
	echo twice
	;;& # BASHISM
    foo)
	echo foo again
	;;
esac
