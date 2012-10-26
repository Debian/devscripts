#!/bin/sh

foo() {
    :
}

_all_good () {
    :
}

_all_good101_ ( ) {
    :
}

function BASHISM() {
    :
}

function BASHISM {
    :
}

function BASHISM {
    echo foo
} &>/dev/null # BASHISM

,() { # BASHISM
    :
}

function foo:bar:BASHISM { # BASHISMS
    :
}

function foo-bar-BASHISM() { # BASHISMS
    :
}

foo-bar-BASHISM ( ) {
    :
}

_ () {
    :
}

function _ { #BASHISM
    :
}

=() { #BASHISM
    :
}

function BASHISM=() { #BASHISMS
    :
}

function BASHISM= { #BASHISMS
    :
}

# This doesn't work:
#foo=() {
#    :
#}
