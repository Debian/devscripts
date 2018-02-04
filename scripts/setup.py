#!/usr/bin/python3

import os
import re

from setuptools import setup

from devscripts.test import SCRIPTS


def get_version():
    # look/set what version we have
    changelog = "../debian/changelog"
    if os.path.exists(changelog):
        head = open(changelog, encoding="utf8").readline()
        match = re.compile(r".*\((.*)\).*").match(head)
        if match:
            return match.group(1)
    raise Exception("Failed to determine version from debian/changelog")


if __name__ == '__main__':
    setup(
        name='devscripts',
        version=get_version(),
        scripts=SCRIPTS,
        packages=['devscripts', 'devscripts/test'],
        test_suite='devscripts.test.discover',
    )
