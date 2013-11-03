
include ../Makefile.common
DESTDIR =

define \n


endef

VERSION_FILE = ../version
VERSION := $(shell cat $(VERSION_FILE))

PL_FILES := $(wildcard *.pl)
SH_FILES = $(wildcard *.sh)
LIBS = libvfork.so.0
CPPFLAGS := $(shell dpkg-buildflags --get CPPFLAGS)
CFLAGS := $(shell dpkg-buildflags --get CFLAGS)
CFLAGS += -std=c99
LDFLAGS := $(shell dpkg-buildflags --get LDFLAGS)
CWRAPPERS = debpkg-wrapper
SCRIPTS = $(patsubst %.pl,%,$(PL_FILES)) $(patsubst %.sh,%,$(SH_FILES))
COMPL_FILES := $(wildcard *.bash_completion)
COMPLETION = $(patsubst %.bash_completion,devscripts.%,$(COMPL_FILES))

GEN_MAN1S += devscripts.1 mk-origtargz.1

all: $(SCRIPTS) $(GEN_MAN1S) $(LIBS) $(CWRAPPERS) $(COMPLETION)

$(VERSION_FILE):
	$(MAKE) -C .. version

%: %.sh

debchange: debchange.pl $(VERSION_FILE)
	cp $< $@
	sed -i "s/###VERSION###/$(VERSION)/" $@
ifeq ($(shell dpkg-vendor --query Vendor),Ubuntu)
# On Ubuntu always default to targeting the release that it's built on,
# not the current devel release, since its primary use on stable releases
# will be for preparing PPA uploads.
	sed -i 's/get_ubuntu_devel_distro()/"$(shell lsb_release -cs)"/' $@
endif
	perl -I.. -c $@

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
%.1: %.pod
	podchecker $<
	pod2man --utf8 --center=" " --release="Debian Utilities" $< > $@
%.1: %.dbk
	xsltproc --nonet -o $@ \
	  /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/docbook.xsl $<

# There is a slight chance this gets called twice, once here from here and once
# from ../po4a/Makefile. Treat files with care.
PID := $(shell echo $$$$-$$PPID)
devscripts.1: devscripts.1.in
	cat $< > $@.$(PID)
	perl ../debian/genmanpage.pl >> $@.$(PID)
	mv $@.$(PID) $@

devscripts.%: %.bash_completion
	cp $< $@

libvfork.o: libvfork.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -fPIC -D_REENTRANT -c $<
libvfork.so.0: libvfork.o
	$(CC) $(LDFLAGS) -shared $< -lc -Wl,-soname -Wl,libvfork.so.0 -o $@

clean:
	python3 setup.py clean -a
	find -name '*.pyc' -delete
	find -name __pycache__ -delete
	rm -rf devscripts.egg-info
	rm -f $(SCRIPTS) $(patsubst %,%.tmp,$(SCRIPTS)) \
		$(GEN_MAN1S) $(SCRIPT_LIBS) $(CWRAPPERS) \
		libvfork.o libvfork.so.0 $(COMPLETION)

test:
	$(foreach python,$(shell py3versions -r ../debian/control),$(python) setup.py test$(\n))

install: all
	python3 setup.py install --root="$(DESTDIR)" --no-compile --install-layout=deb
	install -dD $(DESTDIR)$(BINDIR) $(DESTDIR)$(PKGLIBDIR)
	cp $(SCRIPTS) $(DESTDIR)$(BINDIR)
	ln -sf edit-patch $(DESTDIR)$(BINDIR)/add-patch
	cp $(LIBS) $(DESTDIR)$(PKGLIBDIR)
	install -dD $(DESTDIR)$(SYSCONFDIR)/bash_completion.d
	cp $(COMPLETION) $(DESTDIR)$(SYSCONFDIR)/bash_completion.d
	# Special treatment for debpkg
	install -dD $(DESTDIR)$(PERLMOD_DIR)
	mv $(DESTDIR)$(BINDIR)/debpkg $(DESTDIR)$(PERLMOD_DIR)
	cp debpkg-wrapper $(DESTDIR)$(BINDIR)/debpkg

.PHONY: test
