#!/usr/bin/perl -w
# vim:sw=4:sta:

#   dget - Download Debian source and binary packages
#   Copyright (C) 2005-07 Christoph Berg <myon@debian.org>
#   Modifications Copyright (C) 2005-06 Julian Gilbey <jdg@debian.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

# 2005-10-04 cb: initial release
# 2005-12-11 cb: -x option, update documentation
# 2005-12-31 cb: -b, -q options, use getopt
# 2006-01-10 cb: support new binnmu version scheme
# 2006-11-12 cb: also look in other places in the local filesystem (e.g. pbuilder result dir)
# Later modifications: see debian/changelog

use strict;
use IO::File;
use Digest::MD5;
use Getopt::Long;
use File::Basename;

# global variables

my $progname = basename($0,'.pl');  # the '.pl' is for when we're debugging
my $found_dsc;
my $wget;
my $opt;
my $backup_dir = "backup";
my @dget_path = ("/var/cache/apt/archives");
my $modified_conf_msg;

# use curl if installed, wget otherwise
if (system("command -v curl >/dev/null 2>&1") == 0) {
    $wget = "curl";
} elsif (system("command -v wget >/dev/null 2>&1") == 0) {
    $wget = "wget";
} else {
    die "$progname: can't find either curl or wget; you need at least one of these\ninstalled to run me!\n";
}

# functions

sub usage {
    print <<"EOT";
Usage: $progname [options] URL
       $progname [options] package[=version]

Downloads Debian packages, either from the specified URL (first form),
or using the mirror configured in /etc/apt/sources.list (second form).

   -b, --backup    Move files that would be overwritten to ./backup
   -q, --quiet     Suppress wget/curl output
   -x, --extract   Run dpkg-source -x on downloaded source (first form only)
   --build         Build package with dpkg-buildpackage after download
   --path DIR      Check these directories in addition to the apt archive;
                   if DIR='' then clear current list (may be used multiple
                   times)
   --insecure      Do not check SSL certificates when downloading
   --no-cache      Disable server-side HTTP cache
   --no-conf       Don\'t read devscripts config files;
                   must be the first option given
   -h, --help      This message
   -V, --version   Version information

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOT
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 2005-07 by Christoph Berg <myon\@debian.org>.
Modifications copyright 2005-06 by Julian Gilbey <jdg\@debian.org>.
All rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}


sub wget {
    my ($file, $url) = @_;

    # schemes not supported by all backends
    if ($url =~ m!^(file|copy)://(/.+)!) {
	if ($1 eq "copy" or not link($2, $file)) {
	    system "cp -a $2 $file";
	    return $? >> 8;
	}
	return;
    }

    my @cmd = ($wget);
    # curl does not follow document moved headers, and does not exit
    # with a non-zero error code by default if a document is not found
    push @cmd, "-f", "-L" if $wget eq "curl";
    push @cmd, ($wget eq "wget" ? "-nv" : ("-s", "-S")) if $opt->{'quiet'};
    push @cmd, ($wget eq "wget" ? "--no-check-certificate" : "--insecure") if $opt->{'insecure'};
    push @cmd, ($wget eq "wget" ? "--no-chache" : ("--header", "Pragma: no-cache")) if $opt->{'no-cache'};
    push @cmd, ($wget eq "wget" ? "-O" : "-o");
    system @cmd, $file, $url;
    return $? >> 8;
}

sub backup_or_unlink {
    my $file = shift;
    return unless -e $file;
    if ($opt->{'backup'}) {
	unless (-d $backup_dir) {
	    mkdir $backup_dir or die "mkdir $backup_dir: $!";
	}
	rename $file, "$backup_dir/$file" or die "rename $file $backup_dir/$file: $!";
    } else {
	unlink $file or die "unlink $file: $!";
    }
}

# some files both are in .dsc and .changes, download only once
my %seen;
sub get_file {
    my ($dir, $file, $md5sum) = @_;
    return if $seen{$file};

    if ($md5sum eq "unlink") {
	backup_or_unlink($file);
    }

    # check the existing file's md5sum
    if (-e $file) {
	my $md5 = Digest::MD5->new;
	my $fh5 = new IO::File($file) or die "$file: $!";
	my $md5sum_new = Digest::MD5->new->addfile($fh5)->hexdigest();
	close $fh5;
	if (not $md5sum or ($md5sum_new eq $md5sum)) {
	    print "$progname: using existing $file\n";
	} else {
	    print "$progname: removing $file (md5sum does not match)\n";
	    backup_or_unlink($file);
	}
    }

    # look for the file in other local directories
    unless (-e $file) {
	foreach my $path (@dget_path) {
	    next unless -e "$path/$file";

	    my $md5 = Digest::MD5->new;
	    my $fh5 = new IO::File("$path/$file") or die "$path/$file: $!";
	    my $md5sum_new = Digest::MD5->new->addfile($fh5)->hexdigest();
	    close $fh5;

	    if ($md5sum_new eq $md5sum) {
		if (link "$path/$file", $file) {
		    print "$progname: using $path/$file (hardlink)\n";
		} else {
		    print "$progname: using $path/$file (copy)\n";
		    system "cp -a $path/$file $file";
		}
		last;
	    }
	}
    }

    # finally get it from the web
    unless (-e $file) {
	print "$progname: retrieving $dir/$file\n";
	if (wget($file, "$dir/$file")) {
	    warn "$progname: $wget $file $dir/$file failed\n";
	    unlink $file;
	}
    }

    # try apt-get if it is still not there
    if (not -e $file and $file =~ m!^([a-z0-9.+-]{2,})_[^/]+\.(?:diff\.gz|tar\.gz)$!) {
	my $cmd = "apt-get source --print-uris $1";
	my $apt = new IO::File("$cmd |") or die "$cmd: $!";
	while(<$apt>) {
	    if (/'(\S+)'\s+\S+\s+\d+\s+([\da-f]+)/i and $2 eq $md5sum) {
		if (wget($file, $1)) {
		    warn "$progname: $wget $file $1 failed\n";
		    unlink $file;
		}
	    }
	}
	close $apt;
    }

    # still not there, return
    unless (-e $file) {
	return 0;
    }

    if ($file =~ /\.(?:changes|dsc)$/) {
	parse_file($dir, $file);
    }
    if ($file =~ /\.dsc$/) {
	$found_dsc = $file;
    }

    $seen{$file} = 1;
    return 1;
}

sub parse_file {
    my ($dir, $file) = @_;

    my $fh = new IO::File($file);
    open $fh, $file or die "$file: $!";
    while (<$fh>) {
	if (/^ ([0-9a-f]{32}) (?:\S+ )*(\S+)$/) {
	    get_file($dir, $2, $1) or return;
	}
    }
    close $fh;
}

sub quote_version {
    my $version = shift;
    $version = quotemeta($version);
    $version =~ s/^([^:]+:)/(?:$1)?/; # Epochs are not part of the filename
    $version =~ s/-([^.-]+)$/-$1(?:\\+b\\d+|\.0\.\\d+)?/; # BinNMU: -x -> -x.0.1 -x+by
    $version =~ s/-([^.-]+\.[^.-]+)$/-$1(?:\\+b\\d+|\.\\d+)?/; # -x.y -> -x.y.1 -x.y+bz
    return $version;
}

# we reinvent "apt-get -d install" here, without requiring root
# (and we do not download dependencies)
sub apt_get {
    my ($package, $version) = @_;

    my $qpackage = quotemeta($package);
    my $qversion = quote_version($version) if $version;
    my @hosts;

    my $apt = new IO::File("LC_ALL=C apt-cache policy $package |") or die "$!";
    OUTER: while (<$apt>) {
	if (not $version and /^  Candidate: (.+)/) {
	    $version = $1;
	    $qversion = quote_version($version);
	}
	if ($qversion and /^ [ *]{3} ($qversion) 0/) {
	    while (<$apt>) {
		last OUTER unless /^  *(?:\d+) (\S+)/;
		push @hosts, $1;
	    }
	}
    }
    close $apt;
    unless ($version) {
	die "$progname: $package has no installation candidate\n";
    }
    unless (@hosts) {
	die "$progname: no hostnames in apt-cache policy $package for $version found\n";
    }

    $apt = new IO::File("LC_ALL=C apt-cache show $package |") or die "$!";
    my ($v, $p, $filename, $md5sum);
    while (<$apt>) {
	if (/^Package: $qpackage$/) {
	    $p = $package;
	}
	if (/^Version: $qversion$/) {
	    $v = $version;
	}
	if (/^Filename: (.*)/) {
	    $filename = $1;
	}
	if (/^MD5sum: (.*)/) {
	    $md5sum = $1;
	}
	if (/^Description:/) { # we assume this is the last field
	    if ($p and $v and $filename) {
		last;
	    }
	    undef $p;
	    undef $v;
	    undef $filename;
	    undef $md5sum;
	}
    }
    close $apt;

    unless ($filename) {
	die "$progname: no filename for $package ($version) found\n";
    }

    # find deb lines matching the hosts in the policy output
    $apt = new IO::File("/etc/apt/sources.list") or die "/etc/apt/sources.list: $!";
    my @repositories;
    my $host_re = '(?:' . (join '|', map { quotemeta; } @hosts) . ')';
    while (<$apt>) {
	if (/^\s*deb\s*($host_re\S+)/) {
	    push @repositories, $1;
	}
    }
    close $apt;
    unless (@repositories) {
	die "no repository found in /etc/apt/sources.list";
    }

    # try each repository in turn
    foreach my $repository (@repositories) {
	my ($dir, $file) = ($repository, $filename);
	if ($filename =~ /(.*)\/([^\/]*)$/) {
	    ($dir, $file) = ("$repository/$1", $2);
	}

	get_file($dir, $file, $md5sum) and return;
    }
    exit 1;
}

# main program

# Now start by reading configuration files and then command line
# The next stuff is boilerplate

my $dget_path;

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DGET_PATH' => '',
		       );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
	$shell_cmd .= "$var='$config_vars{$var}';\n";
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $dget_path = $config_vars{'DGET_PATH'};
}

# handle options
Getopt::Long::Configure('bundling');
GetOptions(
    "b|backup"   =>  \$opt->{'backup'},
    "q|quiet"    =>  \$opt->{'quiet'},
    "build"      =>  \$opt->{'build'},
    "x|extract"  =>  \$opt->{'unpack_source'},
    "insecure"   =>  \$opt->{'insecure'},
    "no-cache"   =>  \$opt->{'no-cache'},
    "noconf|no-conf"   =>  \$opt->{'no-conf'},
    "path=s"     =>  sub {
	if ($_[1] eq '') { $dget_path=''; } else { $dget_path .= ":$_[1]"; } },
    "h|help"     =>  \$opt->{'help'},
    "V|version"  =>  \$opt->{'version'},
)
    or die "$progname: unrecognised option. Run $progname --help for more details.\n";

if ($opt->{'help'}) { usage(); exit 0; }
if ($opt->{'version'}) { version(); exit 0; }
if ($opt->{'no-conf'}) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}

if ($dget_path) {
    foreach my $p (split /:/, $dget_path) {
	push @dget_path, $p if -d $p;
    }
}

if (! @ARGV) {
    die "Usage: $progname [options] URL|package[=version]\nRun $progname --help for more details.\n";
}

# handle arguments
for my $arg (@ARGV) {
    $found_dsc = "";

    if ($arg =~ /^((?:copy|file|ftp|http|rsh|rsync|ssh|www).*)\/([^\/]+\.\w+)$/) {
	get_file($1, $2, "unlink") or exit 1;
	if ($found_dsc and $opt->{'build'}) {
		my @output = `dpkg-source -x $found_dsc`;
		foreach (@output) {
			if ( /^dpkg-source: extracting .* in .*/ ) {
				/^dpkg-source: extracting .* in (.*)$/;
				chdir $1;
				system 'dpkg-buildpackage', '-b', '-us';
			}
		}
	}
	elsif ($found_dsc and $opt->{'unpack_source'}) {
	    system 'dpkg-source', '-x', $found_dsc;
	}

    } elsif ($arg =~ /^[a-z0-9.+-]{2,}$/) {
	apt_get($arg);

    } elsif ($arg =~ /^([a-z0-9.+-]{2,})=([a-zA-Z0-9.:~+-]+)$/) {
	apt_get($1, $2);

    } else {
	usage();
    }
}

=pod

=head1 NAME

dget -- Download Debian source and binary packages

=head1 SYNOPSIS

=over

=item B<dget> [I<options>] I<URL>

=item B<dget> [I<options>] I<package>[=I<version>]

=back

=head1 DESCRIPTION

B<dget> downloads Debian packages.  In the first form, B<dget> fetches
the requested URL.  If this is a .dsc or .changes file, then B<dget>
acts as a source-package aware form of B<wget>: it also fetches any
files referenced in the .dsc/.changes file.  When the B<-x> option is
given, the downloaded source is also unpacked by B<dpkg-source>.

In the second form, B<dget> downloads a I<binary> package (i.e., a
I<.deb> file) from the Debian mirror configured in
/etc/apt/sources.list.  Unlike B<apt-get install -d>, it does not
require root privileges, writes to the current directory, and does not
download dependencies.  If a version number is specified, this version
of the package is requested.

Before downloading files listed in .dsc and .changes files, and before
downloading binary packages, B<dget> checks to see whether any of
these files already exist.  If they do, then their md5sums are
compared to avoid downloading them again unnecessarily.  B<dget> also
looks for matching files in I</var/cache/apt/archives> and directories
given by the B<--path> option or specified in the configuration files
(see below).  Finally, if downloading (.orig).tar.gz or .diff.gz files
fails, dget consults B<apt-get source --print-uris>.  Download backends
used are B<curl> and B<wget>, looked for in that order.

B<dget> was written to make it easier to retrieve source packages from
the web for sponsor uploads.  For checking the package with
B<debdiff>, the last binary version is available via B<dget>
I<package>, the last source version via B<apt-get source> I<package>.

=head1 OPTIONS

=over 4

=item B<-b>, B<--backup>

Move files that would be overwritten to I<./backup>.

=item B<-q>, B<--quiet>

Suppress B<wget>/B<curl> non-error output.

=item B<-x>, B<--extract>

Run B<dpkg-source -x> on the downloaded source package.  This can only
be used with the first method of calling B<dget>.

=item B<--build>

Run B<dpkg-buildpackage -b -uc> on the downloaded source package.

=item B<--path> DIR[:DIR...]

In addition to I</var/cache/apt/archives>, B<dget> uses the
colon-separated list given as argument to B<--path> to find files with
a matching md5sum.  For example: "--path
/srv/pbuilder/result:/home/cb/UploadQueue".  If DIR is empty (i.e.,
"S<--path ''>" is specified), then any previously listed directories
or directories specified in the configuration files will be ignored.
This option may be specified multiple times, and all of the
directories listed will be searched; hence, the above example could
have been written as: "--path /srv/pbuilder/result --path
/home/cb/UploadQueue".

=item B<--insecure>

Allow SSL connections to untrusted hosts.

=item B<--no-cache>

Bypass server-side HTTP caches by sending a B<Pragma: no-cache> header.

=item B<-h>, B<--help>

Show a help message.

=item B<-V>, B<--version>

Show version information.

=back

=head1 CONFIGURATION VARIABLES

The two configuration files F</etc/devscripts.conf> and
F<~/.devscripts> are sourced by a shell in that order to set
configuration variables.  Command line options can be used to override
configuration file settings.  Environment variable settings are
ignored for this purpose.  The currently recognised variable is:

=over 4

=item DGET_PATH

This can be set to a colon-separated list of directories in which to
search for files in addition to the default
I</var/cache/apt/archives>.  It has the same effect as the B<--path>
command line option.  It is not set by default.

=cut

=head1 BUGS

B<dget> I<package> should be implemented in B<apt-get install -d>.

=head1 AUTHOR

This program is Copyright (C) 2005-07 by Christoph Berg <myon@debian.org>.
Modifications are Copyright (C) 2005-06 by Julian Gilbey <jdg@debian.org>.

This program is licensed under the terms of the GPL, either version 2
of the License, or (at your option) any later version.

=head1 SEE ALSO

B<apt-get>(1), B<debdiff>(1), B<dpkg-source>(1), B<curl>(1), B<wget>(1).
