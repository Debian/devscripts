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
    """Shell-escpae arg, if necessary.
    Fairly simplistic, doesn't escape anything except whitespace.
    """
    if ' ' not in arg:
        return arg
    return '"%s"' % arg.replace('\\', r'\\').replace('"', r'\"')


class Logger(object):
    script_name = os.path.basename(sys.argv[0])
    verbose = False

    stdout = sys.stdout
    stderr = sys.stderr

    @classmethod
    def _print(cls, format_, message, args=None, stderr=False):
        if args:
            message = message % args
        stream = cls.stderr if stderr else cls.stdout
        stream.write((format_ + "\n") % (cls.script_name, message))

    @classmethod
    def command(cls, cmd):
        if cls.verbose:
            cls._print("%s: I: %s", " ".join(escape_arg(arg) for arg in cmd))

    @classmethod
    def debug(cls, message, *args):
        if cls.verbose:
            cls._print("%s: D: %s", message, args, stderr=True)

    @classmethod
    def error(cls, message, *args):
        cls._print("%s: Error: %s", message, args, stderr=True)

    @classmethod
    def warn(cls, message, *args):
        cls._print("%s: Warning: %s", message, args, stderr=True)

    @classmethod
    def info(cls, message, *args):
        if cls.verbose:
            cls._print("%s: I: %s", message, args)

    @classmethod
    def normal(cls, message, *args):
        cls._print("%s: %s", message, args)

    @classmethod
    def set_verbosity(cls, verbose):
        cls.verbose = verbose
