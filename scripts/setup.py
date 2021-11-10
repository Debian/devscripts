#!/usr/bin/python3

import os
import re
from distutils.command.clean import clean as BaseCleanCommand

from setuptools import setup

from devscripts.test import SCRIPTS


def get_version():
    # look/set what version we have
    changelog = "../debian/changelog"
    if os.path.exists(changelog):
        with open(changelog, encoding="utf8") as f:
            head = f.readline()
        match = re.compile(r".*\((.*)\).*").match(head)
        if match:
            version = match.group(1)
        path = os.path.join("devscripts", "__init__.py")
        with open(path, "w", encoding="utf8") as f:
            f.write("version = '{}'\n".format(version))
        return version
    raise Exception("Failed to determine version from debian/changelog")


class MyCleanCommand(BaseCleanCommand):
    def run(self):
        super().run()
        version_file_py = os.path.join("devscripts", "__init__.py")
        if os.path.exists(version_file_py):
            os.unlink(version_file_py)


if __name__ == '__main__':
    setup(
        name='devscripts',
        version=get_version(),
        scripts=SCRIPTS,
        packages=['devscripts', 'devscripts/test'],
        test_suite='devscripts.test',
        cmdclass={'clean': MyCleanCommand},
    )
