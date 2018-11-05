include ../Makefile.common

all:

clean:

install: install_man1

install_man1: %.1
	install -d "$(DESTDIR)$(MAN1DIR)"
	install -m0644 -t "$(DESTDIR)$(MAN1DIR)" $*
