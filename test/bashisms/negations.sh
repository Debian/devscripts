#!/bin/sh

case "moo" in
    [^f]oo) # BASHISM
	echo hey
	;;
    [!f]oo)
	echo hey
	;;
esac

