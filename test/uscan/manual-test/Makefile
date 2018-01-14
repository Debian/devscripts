TOPSRCDIR	:= $(abspath $(CURDIR)/../../..)
PATH		:= $(TOPSRCDIR)/scripts:$(PATH)
PERL5LIB	:= $(TOPSRCDIR)/lib
export PATH
export PERL5LIB
COMMAND		:= uscan --no-conf --debug
KEEP_THESE	:= $(wildcard _*)
TOSS_THESE	:= $(filter-out $(KEEP_THESE) Makefile, $(wildcard *))

all:
	$(MAKE) prep # always run first
	$(MAKE) test

# Single archive run
test-%:
	cd $*; $(COMMAND)
	touch $*/stamp

# Many single archive runs
test: $(patsubst %,test-%,$(KEEP_THESE))

# Multiple archive run at once
multi:
	$(COMMAND)

prep:
	$(MAKE) -C $(TOPSRCDIR)/scripts uscan mk-origtargz uupdate debchange
	$(MAKE) -C $(TOPSRCDIR)/scripts uscan.pl_check
	touch stamp

clean-%:
	-rm $*/stamp

clean: $(patsubst %,clean-%,$(KEEP_THESE))
	-rm -rf $(TOSS_THESE)
