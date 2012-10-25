#!/usr/bin/make -f

foo:
	if [ "$$(< $(DEBIAN)/foo md5sum)" != "$$(cat $(DEBIAN)/foo.md5)" ] ; then \
	    echo moo; \
	fi
