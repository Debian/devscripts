# Simplified Makefile for devscripts

PL_FILES = bts.pl checkbashisms.pl cvs-debuild.pl debchange.pl \
	debdiff.pl debi.pl debpkg.pl debuild.pl dpkg-depcheck.pl \
	dscverify.pl grep-excuses.pl plotchangelog.pl rc-alert.pl

SH_FILES = cvs-debi.sh cvs-debrelease.sh debclean.sh debrelease.sh \
	debrsign.sh debsign.sh dpkg-genbuilddeps.sh mergechanges.sh \
	uscan.sh uupdate.sh wnpp-alert.sh

LIBS = libvfork.so.0

PERL_MODULES = Devscripts

CWRAPPERS = debpkg-wrapper

SCRIPTS = $(PL_FILES:.pl=) $(SH_FILES:.sh=)
EXAMPLES = conf.default

MAN1S = $(SCRIPTS:=.1) debc.1 cvs-debc.1 devscripts.1
MAN1S_FR = debclean.fr.1
GEN_MAN1S = bts.1
MAN5S = devscripts.conf.5

BINDIR = /usr/bin
LIBDIR = /usr/lib/devscripts
EXAMPLES_DIR = /usr/share/devscripts
PERLMOD_DIR = /usr/share/devscripts
BIN_LIBDIR = /usr/lib/devscripts
MAN1DIR = /usr/share/man/man1
MAN1_FR_DIR = /usr/share/man/fr/man1
MAN5DIR = /usr/share/man/man5

all: $(SCRIPTS) $(GEN_MAN1S) $(EXAMPLES) $(LIBS) $(CWRAPPERS)

version:
	rm -f version
	dpkg-parsechangelog | perl -ne '/^Version: (.*)/ && print $$1' \
	    > version

%: %.sh version
	rm -f $@ $@.tmp
	VERSION=`cat version` && sed -e "s/###VERSION###/$$VERSION/" $< \
	    > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

%: %.pl version
	rm -f $@ $@.tmp
	VERSION=`cat version` && sed -e "s/###VERSION###/$$VERSION/" $< \
	    > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@

conf.default: conf.default.in version
	rm -f $@ $@.tmp
	VERSION=`cat version` && sed -e "s/###VERSION###/$$VERSION/" $< \
	    > $@.tmp && mv $@.tmp $@

bts.1: bts.pl
	pod2man --center=" " --release="Debian Utilities" $< > $@

libvfork.o: libvfork.c
	$(CC) -fPIC -D_REENTRANT $(CFLAGS) -c $<

libvfork.so.0: libvfork.o
	$(CC) -shared $< -ldl -lc -Wl,-soname -Wl,libvfork.so.0 -o $@

clean:
	rm -f version conf.default $(SCRIPTS) $(GEN_MAN1S) $(SCRIPT_LIBS) \
	    $(CWRAPPERS) libvfork.o libvfork.so.0

install: all
	mkdir -p $(DESTDIR)$(BINDIR)
	cp $(SCRIPTS) $(DESTDIR)$(BINDIR)
	cd $(DESTDIR)$(BINDIR) && ln -s debchange dch
	cd $(DESTDIR)$(BINDIR) && ln -s debi debc
	cd $(DESTDIR)$(BINDIR) && ln -s cvs-debi cvs-debc
	mkdir -p $(DESTDIR)$(LIBDIR)
	cp $(LIBS) $(DESTDIR)$(LIBDIR)
	mkdir -p $(DESTDIR)$(PERLMOD_DIR)
	cp -a $(PERL_MODULES) $(DESTDIR)$(PERLMOD_DIR)
	# Special treatment for debpkg
	mv $(DESTDIR)$(BINDIR)/debpkg $(DESTDIR)$(PERLMOD_DIR)
	cp debpkg-wrapper $(DESTDIR)$(BINDIR)/debpkg
	mkdir -p $(DESTDIR)$(MAN1DIR)
	cp $(MAN1S) $(DESTDIR)$(MAN1DIR)
	mkdir -p $(DESTDIR)$(MAN1_FR_DIR)
	for i in $(MAN1S_FR); do \
	    cp $$i $(DESTDIR)$(MAN1_FR_DIR)/$${i%.fr.1}.1; \
	done
	mkdir -p $(DESTDIR)$(MAN5DIR)
	cp $(MAN5S) $(DESTDIR)$(MAN5DIR)
	cd $(DESTDIR)$(MAN1DIR) && ln -s debchange.1 dch.1
	mkdir -p $(DESTDIR)$(EXAMPLES_DIR)
	cp $(EXAMPLES) $(DESTDIR)$(EXAMPLES_DIR)

