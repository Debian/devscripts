# Simplified Makefile for devscripts

include Makefile.common

DESTDIR =

PERL_MODULES = Devscripts
EXAMPLES = conf.default
MANS_fr_DIR = po4a/fr
GEN_MAN1S_fr = $(patsubst %,$(MANS_fr_DIR)/%,$(GEN_MAN1S))
MAN1S_fr = $(subst $(MANS_fr_DIR)/,,$(wildcard $(MANS_fr_DIR)/*.1))

all: version scripts $(EXAMPLES) translated_manpages

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
	# These may or may not have been successfully made; we don't stop
	# building the rest of the package in such a case
	for i in $(GEN_MAN1S_fr); do \
	    $(MAKE) $$i || true; \
	done
	touch translated_manpages

clean_translated_manpages:
	# Update the POT/POs and remove the translated man pages
	$(MAKE) -C po4a/ clean
	rm -f translated_manpages

clean: clean_scripts clean_translated_manpages
	rm -f version conf.default $(GEN_MAN1S_fr)

install: all install_scripts
	cp -a $(PERL_MODULES) $(DESTDIR)$(PERLMOD_DIR)
	cp $(EXAMPLES) $(DESTDIR)$(EXAMPLES_DIR)

scripts:
	$(MAKE) -C scripts/
clean_scripts:
	$(MAKE) -C scripts/ clean
install_scripts:
	$(MAKE) -C scripts/ install DESTDIR=$(DESTDIR)

