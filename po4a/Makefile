include ../Makefile.common

LANGS = de fr pt

DESC_de/ = Debian-Hilfswerkzeuge
DESC_fr/ = Utilitaires Debian
DESC_pt/ = Utilitários Debian

GEN_TR_MAN1S := $(sort $(foreach lang,$(LANGS),$(patsubst %.1,$(lang)/%.$(lang).1,$(GEN_MAN1S))))

all: translate
# GEN_TR_MAN1S needs translate finished, serialize the calls
	@$(MAKE) transform
transform: $(GEN_TR_MAN1S)

translate: ../doc/devscripts.1
	po4a --previous --no-backups --keep=0 devscripts-po4a.conf
	touch $@

clean: ../doc/devscripts.1
	po4a --previous --rm-translations --no-backups devscripts-po4a.conf
	rm -f $(GEN_TR_MAN1S) translate
	rm -rf $(LANGS)

../doc/devscripts.1:
	# po4a translate and clean need ../doc/devscripts.1, rebuild it
	$(MAKE) -C ../doc devscripts.1

%.1:: %.pl translate
	-podchecker $<
	pod2man --utf8 --center=" " --release="$(DESC_$(dir $@))" $< > $@
%.1:: %.pod translate
	-podchecker $<
	pod2man --utf8 --center=" " --release="$(DESC_$(dir $@))" $< > $@
%.1:: %.dbk translate
	xsltproc --nonet \
	  /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/docbook.xsl $<
	# /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/other.xsl
	# (which is imported by the above stylesheet) insists in writing the output
	# to where it wants to.  we can only move the file ourselves.
	# ($* → de/deb-reversion.de)
	mv $(notdir $(basename $*)).1 $@
