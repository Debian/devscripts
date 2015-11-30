# libsoftware-license-perl to be newer than 0.103010-3
check_unstable = $(shell dpkg --compare-versions \
	`dpkg-query -W -f='$${Version}' libsoftware-license-perl` \
	gt '0.103010-3' ; \
	echo $$?)

test:
	./test_annotate-output
	./test_checkbashisms
	./test_dd-list
	./test_debchange
	./test_debdiff
	./test_licensecheck
	if [ $(check_unstable) = 0 ]; then \
	./test_licensecheck_SL ;\
	fi
	./test_uscan
	./test_uscan_mangle
	rm -rf uscan/gpg
	./test_mk-origtargz

test-installed:
	./test_annotate-output --installed
	./test_checkbashisms --installed
	./test_dd-list --installed
	./test_debchange --installed
	./test_debdiff --installed
	./test_licensecheck --installed
	if [ $(check_unstable) = 0 ]; then \
	./test_licensecheck_SL --installed ;\
	fi
	./test_uscan --installed
	./test_uscan_mangle --installed
	rm -rf uscan/gpg
	./test_mk-origtargz --installed

online-test:
	./test_uscan_online

.PHONY: test test-installed online-test
