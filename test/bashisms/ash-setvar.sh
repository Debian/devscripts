#!/bin/sh

setvar foo bar # BASHISM
[ bar = "$foo" ]
