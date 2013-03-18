#!/usr/bin/python3

from setuptools import setup
import glob
import os
import re

# look/set what version we have
changelog = "../debian/changelog"
if os.path.exists(changelog):
    head = open(changelog, encoding="utf8").readline()
    match = re.compile(".*\((.*)\).*").match(head)
    if match:
        version = match.group(1)

scripts = ['suspicious-source',
           'wrap-and-sort',
          ]

if __name__ == '__main__':
    setup(name='devscripts',
          version=version,
          scripts=scripts,
          packages=['devscripts',
                    'devscripts/test',
                   ],
          test_suite='devscripts.test.discover',
    )
