# test_logger.py - Test devscripts.logger.Logger.
#
# Copyright (C) 2012, Stefano Rivera <stefanor@debian.org>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

import StringIO
import sys

from devscripts.logger import Logger
from devscripts.test import unittest


class LoggerTestCase(unittest.TestCase):
    def setUp(self):
        Logger.stdout = StringIO.StringIO()
        Logger.stderr = StringIO.StringIO()
        self._script_name = Logger.script_name
        Logger.script_name = 'test'
        self._verbose = Logger.verbose

    def tearDown(self):
        Logger.stdout = sys.stdout
        Logger.stderr = sys.stderr
        Logger.script_name = self._script_name
        Logger.verbose = self._verbose

    def testCommand(self):
        Logger.command(('ls', 'a b'))
        self.assertEqual(Logger.stdout.getvalue(), '')
        Logger.set_verbosity(True)
        Logger.command(('ls', 'a b'))
        self.assertEqual(Logger.stdout.getvalue(), 'test: I: ls "a b"\n')
        self.assertEqual(Logger.stderr.getvalue(), '')

    def testNoArgs(self):
        Logger.normal('hello %s')
        self.assertEqual(Logger.stdout.getvalue(), 'test: hello %s\n')
        self.assertEqual(Logger.stderr.getvalue(), '')

    def testArgs(self):
        Logger.normal('hello %s', 'world')
        self.assertEqual(Logger.stdout.getvalue(), 'test: hello world\n')
        self.assertEqual(Logger.stderr.getvalue(), '')
