include ../Makefile.common
GEN_TR_MAN1S := $(patsubst %.1,fr/%.fr.1,$(GEN_MAN1S))

all: translate $(GEN_TR_MAN1S)

translate:
	$(MAKE) -C ../scripts/ devscripts.1
	po4a --previous --no-backups devscripts-po4a.conf
	touch translate
clean:
# The po4a cleanup fails if devscripts.1 has already been cleaned up
	$(MAKE) -C ../scripts/ devscripts.1
	po4a --previous --rm-translations --no-backups devscripts-po4a.conf
	rm -f $(GEN_TR_MAN1S) translate ../scripts/devscripts.1

fr/%.fr.1: fr/%.fr.pl translate
	podchecker $<
	pod2man --utf8 --center=" " --release="Utilitaires Debian" $< > $@
fr/%.fr.1: fr/%.fr.dbk translate
	xsltproc --nonet -o $@ \
	  /usr/share/sgml/docbook/stylesheet/xsl/nwalsh/manpages/docbook.xsl $<
# xsltproc writes out to foo.1 even if you tell it to do otherwise, so we have
# to rename the file after it's generated
	mv fr/$*.1 $@
