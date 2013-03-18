# control.py - Represents a debian/control file
#
# Copyright (C) 2010, Benjamin Drung <bdrung@debian.org>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

"""This module implements facilities to deal with Debian control."""

import os
import sys

from devscripts.logger import Logger

try:
    import debian.deb822
except ImportError:
    Logger.error("Please install 'python3-debian' in order to use this utility.")
    sys.exit(1)

def _insert_after(paragraph, item_before, new_item, new_value):
    """Insert new_item into directly after item_before

       New items added to a dictionary are appended."""
    item_found = False
    for item in paragraph:
        if item_found:
            value = paragraph.pop(item)
            paragraph[item] = value
        if item == item_before:
            item_found = True
            paragraph[new_item] = new_value
    if not item_found:
        paragraph[new_item] = new_value

class Control(object):
    """Represents a debian/control file"""

    def __init__(self, filename):
        assert os.path.isfile(filename), "%s does not exist." % (filename)
        self.filename = filename
        sequence = open(filename)
        self.paragraphs = list()
        for paragraph in debian.deb822.Deb822.iter_paragraphs(sequence):
            self.paragraphs.append(paragraph)

    def get_maintainer(self):
        """Returns the value of the Maintainer field."""
        return self.paragraphs[0].get("Maintainer")

    def get_original_maintainer(self):
        """Returns the value of the XSBC-Original-Maintainer field."""
        return self.paragraphs[0].get("XSBC-Original-Maintainer")

    def save(self, filename=None):
        """Saves the control file."""
        if filename:
            self.filename = filename
        content = "\n".join([x.dump() for x in self.paragraphs])
        control_file = open(self.filename, "wb")
        control_file.write(content.encode("utf-8"))
        control_file.close()

    def set_maintainer(self, maintainer):
        """Sets the value of the Maintainer field."""
        self.paragraphs[0]["Maintainer"] = maintainer

    def set_original_maintainer(self, original_maintainer):
        """Sets the value of the XSBC-Original-Maintainer field."""
        if "XSBC-Original-Maintainer" in self.paragraphs[0]:
            self.paragraphs[0]["XSBC-Original-Maintainer"] = original_maintainer
        else:
            _insert_after(self.paragraphs[0], "Maintainer",
                          "XSBC-Original-Maintainer", original_maintainer)

    def strip_trailing_spaces(self):
        """Strips all trailing spaces from the control file."""
        for paragraph in self.paragraphs:
            for item in paragraph:
                lines = paragraph[item].split("\n")
                paragraph[item] = "\n".join([l.rstrip() for l in lines])
