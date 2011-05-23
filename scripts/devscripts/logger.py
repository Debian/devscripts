#
#   logger.py - A simple logging helper class
#
#   Copyright (C) 2010, Benjamin Drung <bdrung@debian.org>
#
#   Permission to use, copy, modify, and/or distribute this software
#   for any purpose with or without fee is hereby granted, provided
#   that the above copyright notice and this permission notice appear
#   in all copies.
#
#   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
#   WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
#   WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
#   AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
#   CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
#   LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
#   NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
#   CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

import os
import sys

def escape_arg(arg):
    "Shell-escpae arg, if necessary"
    if ' ' not in arg:
        return arg
    return '"%s"' % arg.replace('\\', r'\\').replace('"', r'\"')

class Logger(object):
    script_name = os.path.basename(sys.argv[0])
    verbose = False

    stdout = sys.stdout
    stderr = sys.stderr

    @classmethod
    def command(cls, cmd):
        if cls.verbose:
            print >> cls.stdout, "%s: I: %s" % (cls.script_name,
                                                " ".join(escape_arg(arg)
                                                         for arg in cmd))

    @classmethod
    def debug(cls, message, *args):
        if cls.verbose:
            print >> cls.stderr, "%s: D: %s" % (cls.script_name, message % args)

    @classmethod
    def error(cls, message, *args):
        print >> cls.stderr, "%s: Error: %s" % (cls.script_name, message % args)

    @classmethod
    def warn(cls, message, *args):
        print >> cls.stderr, "%s: Warning: %s" % (cls.script_name,
                                                  message % args)

    @classmethod
    def info(cls, message, *args):
        if cls.verbose:
            print >> cls.stdout, "%s: I: %s" % (cls.script_name, message % args)

    @classmethod
    def normal(cls, message, *args):
        print >> cls.stdout, "%s: %s" % (cls.script_name, message % args)

    @classmethod
    def set_verbosity(cls, verbose):
        cls.verbose = verbose
