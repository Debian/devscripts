#!/bin/sh

foo() {
    return -- 1 # BASHISM
}

bar () {
    return 256 # BASHISM
}

moo () {
    return -1 # BASHISM
}
