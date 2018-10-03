
OUR_TESTS= \
	annotate-output \
	checkbashisms \
	dd-list \
	debchange \
	debdiff \
	debrepro \
	debsign \
	mk-origtargz \
	package_lifecycle \
	sadt \
	uscan \
	uscan_ftp \
	uscan_git \
	uscan_mangle \
	perltidy \

test: $(foreach i,$(OUR_TESTS),test_$(i).test)

%.test: %
	./$<

test-installed: $(foreach i,$(OUR_TESTS),test_$(i).test_installed)

%.test_installed: %
	./$< --installed

online-test:
	./test_uscan_online

.PHONY: test test-installed online-test
