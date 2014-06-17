test:
	./test_annotate-output
	./test_checkbashisms
	./test_dd-list
	./test_debchange
	./test_debdiff
	./test_licensecheck
	./test_uscan
	./test_mk-origtargz

test-installed:
	./test_annotate-output --installed
	./test_checkbashisms --installed
	./test_dd-list --installed
	./test_debchange --installed
	./test_debdiff --installed
	./test_licensecheck --installed
	./test_uscan --installed
	./test_mk-origtargz --installed

online-test:
	./test_uscan_online

.PHONY: test test-installed online-test
