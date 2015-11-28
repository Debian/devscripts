test:
	./test_annotate-output
	./test_checkbashisms
	./test_dd-list
	./test_debchange
	./test_debdiff
	./test_licensecheck
	./test_licensecheck_SL
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
	./test_licensecheck_SL --installed
	./test_uscan --installed
	./test_uscan_mangle --installed
	rm -rf uscan/gpg
	./test_mk-origtargz --installed

online-test:
	./test_uscan_online

.PHONY: test test-installed online-test
