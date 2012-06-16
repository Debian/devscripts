# Simplified Makefile for devscripts

include Makefile.common

DESTDIR =

PERL_MODULES = Devscripts
EXAMPLES = conf.default README.mk-build-deps

PREFIX ?= /usr
DOCDIR ?= $(PREFIX)/share/doc/devscripts
MAN1DIR ?= $(PREFIX)/share/man/man1

all: version make_scripts $(EXAMPLES) translated_manpages

version:
	rm -f version
	dpkg-parsechangelog | perl -ne '/^Version: (.*)/ && print $$1' \
	    > version

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

test: test_test test_scripts

install: all install_scripts
	cp -a $(PERL_MODULES) $(DESTDIR)$(PERLMOD_DIR)
	cp $(EXAMPLES) $(DESTDIR)$(EXAMPLES_DIR)
	install -D README $(DESTDIR)$(DOCDIR)/README
	install -dD $(DESTDIR)$(MAN1DIR)
	cp doc/*.1 $(DESTDIR)$(MAN1DIR)
	ln -sf edit-patch.1 $(DESTDIR)$(MAN1DIR)/add-patch.1

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

.PHONY: online-test test
