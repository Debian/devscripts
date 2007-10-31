
include ../Makefile.common
DESTDIR =

VERSION_FILE = ../version
VERSION := $(shell cat $(VERSION_FILE))

PL_FILES := $(wildcard *.pl)
SH_FILES = $(wildcard *.sh)
LIBS = libvfork.so.0
CWRAPPERS = debpkg-wrapper
SCRIPTS = $(patsubst %.pl,%,$(PL_FILES)) $(patsubst %.sh,%,$(SH_FILES))

GEN_MAN1S = bts.1 debcommit.1 deb-reversion.1 dget.1 licensecheck.1 \
	mass-bug.1 rmadison.1 svnpath.1 debcheckout.1 desktop2menu.1

BINDIR = /usr/bin
LIBDIR = /usr/lib/devscripts
BIN_LIBDIR = /usr/lib/devscripts

all: $(SCRIPTS) $(GEN_MAN1S) $(LIBS) $(CWRAPPERS)

%: %.sh

%.tmp: %.sh $(VERSION_FILE)
	sed -e "s/###VERSION###/$(VERSION)/" $<  > $@
	bash -n $@
%.tmp: %.pl $(VERSION_FILE)
	sed -e "s/###VERSION###/$(VERSION)/" $<  > $@
	perl -I.. -c $@
%: %.tmp
	cp $< $@
	chmod +x $@

%.1: %.pl
	pod2man --center=" " --release="Debian Utilities" $< > $@
%.1: %.dbk
	xsltproc --nonet -o $@ \
	  /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/docbook.xsl $<

libvfork.o: libvfork.c
	$(CC) -fPIC -D_REENTRANT $(CFLAGS) -c $<
libvfork.so.0: libvfork.o
	$(CC) -shared $< -lc -Wl,-soname -Wl,libvfork.so.0 -o $@

clean:
	rm -f $(SCRIPTS) $(patsubst %,%.tmp,$(SCRIPTS)) \
		$(GEN_MAN1S) $(SCRIPT_LIBS) $(CWRAPPERS) \
		libvfork.o libvfork.so.0

install: all
	cp $(SCRIPTS) $(DESTDIR)$(BINDIR)
	cp $(LIBS) $(DESTDIR)$(LIBDIR)
	# Special treatment for debpkg
	mv $(DESTDIR)$(BINDIR)/debpkg $(DESTDIR)$(PERLMOD_DIR)
	cp debpkg-wrapper $(DESTDIR)$(BINDIR)/debpkg

