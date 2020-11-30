
OUR_TESTS= \
	perl \
	annotate-output \
	checkbashisms \
	dd-list \
	debchange \
	debdiff \
	debrepro \
	debsign \
	mergechanges \
	mk-origtargz \
	package_lifecycle \
	sadt \
	uscan \
	uscan_ftp \
	uscan_git \
	uscan_svn \
	uscan_mangle \
	uscan_group \
	perltidy \

# Tests that must run as root, and alter the state of the system by
# adding/removing packages
DESTRUCTIVE_TESTS = \
	debi \

# unset some variables that might affect tests
undefine DEB_CHECK_COMMAND

test: $(foreach i,$(OUR_TESTS),test_$(i).test)

destructive-test: $(foreach i,$(DESTRUCTIVE_TESTS),test_$(i).test)

%.test: %
	./$<

test-installed: $(foreach i,$(OUR_TESTS),test_$(i).test_installed)

destructive-test-installed: $(foreach i,$(DESTRUCTIVE_TESTS),test_$(i).test_installed)

%.test_installed: %
	./$< --installed

online-test:
	./test_uscan_online

.PHONY: test test-installed online-test destructive-test
