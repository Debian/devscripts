# test_pylint.py - Run pylint in errors-only mode.
#
# Copyright (C) 2010, Stefano Rivera <stefanor@ubuntu.com>
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

import re
import subprocess
import unittest

from . import SCRIPTS

WHITELIST = [re.compile(': %s$' % x) for x in (
    # Wildcard import:
    r"No name '\w+Error' in module 'launchpadlib\.errors'",
    # https://www.logilab.org/ticket/51250:
    r"Module 'hashlib' has no '(md5|sha(1|224|256|384|512))' member",
    # mox:
    r"Instance of '.+' has no '(WithSideEffects|MultipleTimes|AndReturn)' "
    r"member",
)]


class PylintTestCase(unittest.TestCase):
    def test_pylint(self):
        "Test: Run pylint on Python source code"
        files = ['devscripts']
        for script in SCRIPTS:
            f = open(script, 'r', encoding='utf-8')
            if 'python' in f.readline():
                files.append(script)
            f.close()
        cmd = ['pylint3', '--rcfile=devscripts/test/pylint.conf', '-E',
               '--include-ids=y', '--'] + files
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, close_fds=True)

        out, err = process.communicate()
        if err != '':
            raise unittest.SkipTest('pylint crashed :/')

        filtered_out = []
        detected_in = ''
        # pylint: disable=E1103
        for line in out.splitlines():
            # pylint: enable=E1103
            if line.startswith('************* '):
                detected_in = line
                continue

            for reg_exp in WHITELIST:
                if reg_exp.search(line):
                    break
            else:
                filtered_out.append(detected_in)
                filtered_out.append(line)

        self.assertEqual(filtered_out, [],
                         "pylint found errors.\n"
                         "Filtered Output:\n" + '\n'.join(filtered_out))
