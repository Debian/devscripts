
include ../Makefile.common

DESTDIR =

PL_FILES = bts.pl checkbashisms.pl cvs-debuild.pl dd-list.pl debchange.pl \
	debcommit.pl debdiff.pl debi.pl debpkg.pl debuild.pl dget.pl \
	dpkg-depcheck.pl dscverify.pl grep-excuses.pl mass-bug.pl \
	plotchangelog.pl rc-alert.pl rmadison.pl svnpath.pl

SH_FILES = annotate-output.sh archpath.sh cvs-debi.sh cvs-debrelease.sh \
	deb-reversion.sh debclean.sh debrelease.sh debrsign.sh debsign.sh \
	dpkg-genbuilddeps.sh mergechanges.sh nmudiff.sh pts-subscribe.sh \
	tagpending.sh uscan.sh uupdate.sh whodepends.sh who-uploads.sh \
	wnpp-alert.sh

LIBS = libvfork.so.0

CWRAPPERS = debpkg-wrapper

SCRIPTS = $(PL_FILES:.pl=) $(SH_FILES:.sh=)

GEN_MAN1S = bts.1 debcommit.1 deb-reversion.1 dget.1 mass-bug.1 \
	rmadison.1 svnpath.1

BINDIR = /usr/bin
LIBDIR = /usr/lib/devscripts
BIN_LIBDIR = /usr/lib/devscripts

all: $(SCRIPTS) $(GEN_MAN1S) $(LIBS) $(CWRAPPERS)

%: %.sh ../version
	if grep -q '^#! */bin/sh' $<; then \
	  echo "$< is a /bin/sh script, not a bash script!" >&2; \
	  exit 1; \
	fi
	rm -f $@ $@.tmp
	VERSION=`cat ../version` && sed -e "s/###VERSION###/$$VERSION/" $< \
	    > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@
	bash -n $@

%: %.pl ../version
	rm -f $@ $@.tmp
	VERSION=`cat ../version` && sed -e "s/###VERSION###/$$VERSION/" $< \
	    > $@.tmp && chmod +x $@.tmp && mv $@.tmp $@
	perl -c $@

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
	rm -f $(SCRIPTS) $(GEN_MAN1S) $(SCRIPT_LIBS) $(CWRAPPERS) \
		libvfork.o libvfork.so.0

install: all
	cp $(SCRIPTS) $(DESTDIR)$(BINDIR)
	cp $(LIBS) $(DESTDIR)$(LIBDIR)
	# Special treatment for debpkg
	mv $(DESTDIR)$(BINDIR)/debpkg $(DESTDIR)$(PERLMOD_DIR)
	cp debpkg-wrapper $(DESTDIR)$(BINDIR)/debpkg

