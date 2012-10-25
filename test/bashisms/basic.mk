#!/usr/bin/make -f

# bug:
overrideSHELL := bash

test:
	-echo -e "foo BASHISM"
	@echo -e "bar BASHISM"
	@-echo -e "bar BASHISM" && false
	-@echo -e "bar BASHISM" && false
	true

dirs:
source diff:
source diff.gz::
source file-stamp:
caller %.so:
	:

foo: $(shell echo dir/BASHISM/{foo,bar})
	:
