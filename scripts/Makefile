
include ../Makefile.common
DESTDIR =

VERSION_FILE = ../version
VERSION := $(shell cat $(VERSION_FILE))

PL_FILES := $(wildcard *.pl)
SH_FILES = $(wildcard *.sh)
LIBS = libvfork.so.0
CWRAPPERS = debpkg-wrapper
SCRIPTS = $(patsubst %.pl,%,$(PL_FILES)) $(patsubst %.sh,%,$(SH_FILES))
COMPL_FILES := $(wildcard *.bash_completion)
COMPLETION = $(patsubst %.bash_completion,devscripts.%,$(COMPL_FILES))

GEN_MAN1S += devscripts.1

BINDIR = /usr/bin
LIBDIR = /usr/lib/devscripts
BIN_LIBDIR = /usr/lib/devscripts

all: $(SCRIPTS) $(GEN_MAN1S) $(LIBS) $(CWRAPPERS) $(COMPLETION)

$(VERSION_FILE):
	@echo "You need to 'make' the toplevel directory first"
	@false

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
	podchecker $<
	pod2man --utf8 --center=" " --release="Debian Utilities" $< > $@
%.1: %.dbk
	xsltproc --nonet -o $@ \
	  /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/docbook.xsl $<

# There is a slight chance this gets called twice, once here from here and once
# from ../po4a/Makefile. Treat files with care.
PID := $(shell echo $$$$-$$PPID)
devscripts.1: devscripts.1.in
	cat $+ > $@.$(PID)
	perl ../debian/genmanpage.pl >> $@.$(PID)
	mv $@.$(PID) $@

devscripts.%: %.bash_completion
	cp $< $@

libvfork.o: libvfork.c
	$(CC) -fPIC -D_REENTRANT $(CFLAGS) -c $<
libvfork.so.0: libvfork.o
	$(CC) -shared $< -lc -Wl,-soname -Wl,libvfork.so.0 -o $@

clean:
	rm -f $(SCRIPTS) $(patsubst %,%.tmp,$(SCRIPTS)) \
		$(GEN_MAN1S) $(SCRIPT_LIBS) $(CWRAPPERS) \
		libvfork.o libvfork.so.0 $(COMPLETION)

install: all
	install -dD $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR)
	cp $(SCRIPTS) $(DESTDIR)$(BINDIR)
	ln -sf edit-patch $(DESTDIR)$(BINDIR)/add-patch
	cp $(LIBS) $(DESTDIR)$(LIBDIR)
	install -dD $(DESTDIR)/etc/bash_completion.d
	cp $(COMPLETION) $(DESTDIR)/etc/bash_completion.d
	# Special treatment for debpkg
	install -dD $(DESTDIR)$(PERLMOD_DIR)
	mv $(DESTDIR)$(BINDIR)/debpkg $(DESTDIR)$(PERLMOD_DIR)
	cp debpkg-wrapper $(DESTDIR)$(BINDIR)/debpkg
