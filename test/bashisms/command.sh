#!/bin/sh

command test
command -p test
command -v test
command -V test
command -p test
command -p -v test
command -pv test
command -p -v -a test # BASHISM
command -p -a -v test # BASHISM
command -pa test # BASHISM
command -ap test # BASHISM
command -p -a test # BASHISM
command -pV -a test # BASHISM
command -p test
