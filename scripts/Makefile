
include ../Makefile.common
DESTDIR =

define \n


endef

VERSION_FILE = ../version
VERSION := $(shell cat $(VERSION_FILE))

PL_FILES := $(wildcard *.pl)
SH_FILES = $(wildcard *.sh)
CPPFLAGS := $(shell dpkg-buildflags --get CPPFLAGS)
CFLAGS := $(shell dpkg-buildflags --get CFLAGS)
CFLAGS += -std=c99
LDFLAGS := $(shell dpkg-buildflags --get LDFLAGS)
CWRAPPERS = debpkg-wrapper
SCRIPTS = $(patsubst %.pl,%,$(PL_FILES)) $(patsubst %.sh,%,$(SH_FILES))
COMPL_FILES := $(wildcard *.bash_completion)
BC_BUILD_DIR:=bash_completion
COMPLETION = $(patsubst %.bash_completion,$(BC_BUILD_DIR)/%,$(COMPL_FILES))
COMPL_DIR := $(shell pkg-config --variable=completionsdir bash-completion)
PKGNAMES:=wnpp-alert wnpp-check mk-build-deps rmadison mass-bug debsnap dd-list build-rdeps who-uploads transition-check getbuildlog dcontrol grep-excuses rc-alert whodepends dget pts-subscribe pts-unsubscribe debcheckout
# also update the list in setup.py
PYTHON3_SCRIPTS:=debdiff-apply sadt suspicious-source wrap-and-sort reproducible-check

GEN_MAN1S += debrepro.1 devscripts.1 mk-origtargz.1 uscan.1 reproducible-check.1

all: $(SCRIPTS) $(GEN_MAN1S) $(CWRAPPERS) $(COMPLETION)

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
	perl -I ../lib -c $@

%.tmp: %.sh $(VERSION_FILE)
	sed -e "s/###VERSION###/$(VERSION)/" $<  > $@
	bash -n $@
%.tmp: %.pl $(VERSION_FILE)
	sed -e "s/###VERSION###/$(VERSION)/" $<  > $@
	perl -I ../lib -c $@
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

reproducible-check.1: reproducible-check
	help2man --no-info --no-discard-stderr ./reproducible-check >$@

$(BC_BUILD_DIR):
	mkdir $(BC_BUILD_DIR)

$(COMPLETION): $(BC_BUILD_DIR)/% : %.bash_completion $(BC_BUILD_DIR)
	cp $< $@

clean:
	python3 setup.py clean -a
	find -name '*.pyc' -delete
	find -name __pycache__ -delete
	rm -rf devscripts.egg-info $(BC_BUILD_DIR)
	rm -f $(SCRIPTS) $(patsubst %,%.tmp,$(SCRIPTS)) \
		$(GEN_MAN1S) $(SCRIPT_LIBS) $(CWRAPPERS)

test:
	python3 -m flake8 --max-line-length=99 $(PYTHON3_SCRIPTS)
	$(foreach python,$(shell py3versions -r ../debian/control),$(python) setup.py test$(\n))

install: all
	python3 setup.py install --root="$(DESTDIR)" --no-compile --install-layout=deb
	cp $(SCRIPTS) $(DESTDIR)$(BINDIR)
	ln -sf edit-patch $(DESTDIR)$(BINDIR)/add-patch
	install -d $(DESTDIR)$(COMPL_DIR)
	cp $(BC_BUILD_DIR)/* $(DESTDIR)$(COMPL_DIR)/
	for i in $(PKGNAMES); do                        \
	    ln -sf pkgnames $(DESTDIR)$(COMPL_DIR)/$$i;  \
	done
	ln -sf debchange $(DESTDIR)$(COMPL_DIR)/dch
	ln -sf debi $(DESTDIR)$(COMPL_DIR)/debc
	# Special treatment for debpkg
	install -d $(DESTDIR)$(DATA_DIR)
	mv $(DESTDIR)$(BINDIR)/debpkg $(DESTDIR)$(DATA_DIR)
	cp debpkg-wrapper $(DESTDIR)$(BINDIR)/debpkg

.PHONY: test
