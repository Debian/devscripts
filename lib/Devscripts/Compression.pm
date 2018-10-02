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
# along with this program. If not, see <https://www.gnu.org/licenses/>.

package Devscripts::Compression;

use Dpkg::Compression qw(!compression_get_property);
use Dpkg::IPC;
use Exporter qw(import);

our @EXPORT = (
    @Dpkg::Compression::EXPORT,
    qw(compression_get_file_extension_regex compression_guess_from_file),
);

eval {
    Dpkg::Compression->VERSION(1.02);
    1;
} or do {
    # Ensure we have compression_get_file_extension_regex, regardless of the
    # version of Dpkg::Compression to ease backporting.
    *{'Devscripts::Compression::compression_get_file_extension_regex'} = sub {
        return $compression_re_file_ext;
    };
};

# This can potentially be moved to Dpkg::Compression

my %mime2comp = (
    "application/x-gzip"       => "gzip",
    "application/gzip"         => "gzip",
    "application/x-bzip2"      => "bzip2",
    "application/bzip2  "      => "bzip2",
    "application/x-xz"         => "xz",
    "application/xz"           => "xz",
    "application/zip"          => "zip",
    "application/x-compress"   => "compress",
    "application/java-archive" => "zip",
);

sub compression_guess_from_file {
    my $filename = shift;
    my $mimetype;
    spawn(
        exec => ['file', '--dereference', '--brief', '--mime-type', $filename],
        to_string  => \$mimetype,
        wait_child => 1
    );
    chomp($mimetype);
    if (exists $mime2comp{$mimetype}) {
        return $mime2comp{$mimetype};
    } else {
        return;
    }
}

# comp_prog and default_level aren't provided because a) they aren't needed in
# devscripts and b) the Dpkg::Compression API isn't rich enough to support
# these as compressors
my %comp_properties = (
    compress => {
        file_ext    => 'Z',
        decomp_prog => ['uncompress'],
    },
    zip => {
        file_ext    => 'zip',
        decomp_prog => ['unzip'],
    });

sub compression_get_property {
    my ($compression, $property) = @_;
    if (!exists $comp_properties{$compression}) {
        return Dpkg::Compression::compression_get_property($compression,
            $property);
    }

    if (exists $comp_properties{$compression}{$property}) {
        return $comp_properties{$compression}{$property};
    }
    return;
}

1;
