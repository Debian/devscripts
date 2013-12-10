# Copyright James McCoy <jamessan@debian.org> 2013.
# Modifications copyright 2002 Julian Gilbey <jdg@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

package Devscripts::Compression;

use Dpkg::Compression;
use Exporter qw(import);

our @EXPORT = (@Dpkg::Compression::EXPORT, qw(compression_get_file_extension_regex));

eval {
    Dpkg::Compression->VERSION(1.02);
    1;
} or do {
    # Ensure we have compression_get_file_extension_regex, regardless of the
    # version of Dpkg::Compression to ease backporting.
    *{'Devscripts::Compression::compression_get_file_extension_regex'} = sub
    {
	return $compression_re_file_ext;
    };
};

1;
