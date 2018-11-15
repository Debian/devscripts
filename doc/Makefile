include ../Makefile.common

all: devscripts.1

clean:
	rm -f devscripts.1 devscripts.1.tmp.*

# There is a slight chance this gets called twice, once here from here and once
# from ../po4a/Makefile. Treat files with care.
PID := $(shell echo $$$$-$$PPID)
devscripts.1: devscripts.1.in ../README genmanpage.pl
	cat $< > $@.tmp.$(PID)
	cat ../README | \
		awk '/^- annotate-output/,/^  mailing lists./'|sed -e '/^[[:space:]]*$$/d' -e 's/^/ /g' | \
		perl genmanpage.pl \
		>> $@.tmp.$(PID)
	mv $@.tmp.$(PID) $@

install: install_man1 install_man5

install_man1: *.1 devscripts.1
	install -d "$(DESTDIR)$(MAN1DIR)"
	install -m0644 -t "$(DESTDIR)$(MAN1DIR)" $^
install_man5: *.5
	install -d "$(DESTDIR)$(MAN5DIR)"
	install -m0644 -t "$(DESTDIR)$(MAN5DIR)" $^
