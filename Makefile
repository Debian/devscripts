# Simplified Makefile for devscripts

include Makefile.common

DESTDIR =

all: version make_scripts conf.default translated_manpages

version:
	rm -f version
	dpkg-parsechangelog -SVersion > version

conf.default: conf.default.in version
	rm -f $@ $@.tmp
	VERSION=`cat version` && sed -e "s/###VERSION###/$$VERSION/" $< \
	    > $@.tmp && mv $@.tmp $@

translated_manpages:
	$(MAKE) -C po4a/
	touch translated_manpages

clean_translated_manpages:
	# Update the POT/POs and remove the translated man pages
	$(MAKE) -C po4a/ clean
	rm -f translated_manpages

clean: clean_scripts clean_translated_manpages
	rm -f version conf.default make_scripts

online-test:
	$(MAKE) -C test/ online-test

test:
	$(MAKE) test_scripts
	$(MAKE) test_test

test-installed:
	$(MAKE) -C test/ $@

install: all install_scripts
	install -d "$(DESTDIR)$(PERLMOD_DIR)" \
	    "$(DESTDIR)$(DATA_DIR)" "$(DESTDIR)$(TEMPLATES_DIR)" \
	    "$(DESTDIR)$(DOCDIR)" "$(DESTDIR)$(MAN1DIR)"
	for f in lib/*; do cp -a "$$f" "$(DESTDIR)$(PERLMOD_DIR)"; done
	install -m0644 conf.default "$(DESTDIR)$(DATA_DIR)"
	install -m0644 templates/README.mk-build-deps "$(DESTDIR)$(TEMPLATES_DIR)"
	install -m0644 README "$(DESTDIR)$(DOCDIR)"
	install -m0644 doc/*.1 "$(DESTDIR)$(MAN1DIR)"
	ln -sf edit-patch.1 "$(DESTDIR)$(MAN1DIR)/add-patch.1"

test_test:
	$(MAKE) -C test/ test

make_scripts: version
	$(MAKE) -C scripts/
	touch $@
clean_scripts: clean_translated_manpages
	$(MAKE) -C scripts/ clean
test_scripts:
	$(MAKE) -C scripts/ test
install_scripts:
	$(MAKE) -C scripts/ install DESTDIR=$(DESTDIR)

.PHONY: online-test test test-installed
