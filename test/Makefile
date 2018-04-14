
OUR_TESTS=						\
	annotate-output				\
	checkbashisms				\
	dd-list						\
	debchange					\
	package_lifecycle			\
	debdiff						\
	debsign					\
	uscan						\
	uscan_mangle				\
	uscan_ftp				\
	mk-origtargz				

test: $(foreach i,$(OUR_TESTS),test_$(i).test)

%.test: %
	./$<

test-installed: $(foreach i,$(OUR_TESTS),test_$(i).test_installed)

%.test_installed: %
	./$< --installed

online-test:
	./test_uscan_online

.PHONY: test test-installed online-test
