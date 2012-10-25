#!/bin/sh

trap foo ERR # BASHISM
trap foo RETURN # BASHISM
trap foo DEBUG # BASHISM

trap "echo BASHISM" ERR
trap "echo BASHISM" RETURN
trap "echo BASHISM" DEBUG

foo() {
    echo ": dummy function"
}

trap $(foo BASHISM) ERR
trap "$(foo BASHISM)" RETURN
trap "echo $foo BASHISM" DEBUG
