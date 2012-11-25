#!/bin/sh

GLOBIGNORE="run-tests.sh:BASHISM"
echo *.sh | grep -q run-tests.sh || echo meh
