#! /usr/bin/perl -w

# Copyright Bill Allombert <ballombe@debian.org> 2001.
# Modifications copyright 2002-2005 Julian Gilbey <jdg@debian.org>

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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use 5.006_000;  # our() commands
use Cwd;
use File::Basename;
use Getopt::Long;

use lib '/usr/share/devscripts';
use Devscripts::Set;
use Devscripts::Packages;
use Devscripts::PackageDeps;

# Function prototypes
sub process_features ($$);
sub getusedfiles (@);
sub filterfiles (@);

# Global options
our %opts;

# libvfork is taken from dpkg-genbuilddeps, written by
# Ben Collins <bcollins@debian.org>
our $vforklib = "/usr/lib/devscripts/libvfork.so.0";

# A list of files that do not belong to a Debian package but are known
# to never create a dependency
our @known_files = ($vforklib, "/etc/ld.so.cache", "/etc/dpkg/shlibs.default",
		    "/etc/dpkg/dpkg.cfg", "/etc/devscripts.conf");

# This will be given information about features later on
our (%feature, %default_feature);

my $progname=basename($0);
my $modified_conf_msg;

sub usage ()
{
    my @ed=("disabled","enabled");
    print <<"EOF";
Usage:
  $progname [options] <command>
Run <command> and then output packages used to do this.
Options:
  Which packages to report:
    -a, --all              Report all packages used to run <command>
    -b, --build-depends    Do not report build-essential or essential packages
                           used or any of their (direct or indirect)
                           dependencies
    -d, --ignore-dev-deps  Do not show packages used which are direct
                           dependencies of -dev packages used
    -m, --min-deps         Output a minimal set of packages needed, taking
                           into account direct dependencies
    -m implies -d and both imply -b; -a gives additional dependency information
    if used in conjunction with -b, -d or -m

  -C, --C-locale           Run command with C locale
  --no-C-locale            Don\'t change locale
  -l, --list-files         Report list of files used in each package
  --no-list-files          Do not report list of files used in each package
  -o, --output=FILE        Output diagnostic to FILE instead of stdout
  -O, --strace-output=FILE Write strace output to FILE when tracing <command>
                           instead of a temporary file
  -I, --strace-input=FILE  Get strace output from FILE instead of tracing
                           <command>; strace must be run with -f -q for this
                           to work

  -f, --features=LIST      Enable or disabled features given in
                           comma-separated LIST as follows:
    +feature or feature      enable feature
    -feature                 disable feature

    Known features and default setting:
      warn-local             ($ed[$default_feature{'warn-local'}]) warn if files in /usr/local are used
      discard-check-version  ($ed[$default_feature{'discard-check-version'}]) discard execve with only
                             --version argument; this works around some
                             configure scripts that check for binaries they
                             don\'t use
      trace-local            ($ed[$default_feature{'trace-local'}]) also try to identify file
                             accesses in /usr/local
      catch-alternatives     ($ed[$default_feature{'catch-alternatives'}]) catch access to alternatives
      discard-sgml-catalogs  ($ed[$default_feature{'discard-sgml-catalogs'}]) discard access to SGML 
                             catalogs; some SGML tools read all the
                             registered catalogs at startup.

  --no-conf, --noconf        Don\'t read devscripts config files;
                             must be the first option given
  -h, --help                 Display this help and exit
  -v, --version              Output version information and exit

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}


sub version ()
{
    print <<'EOF';
This is $progname, from the Debian devscripts package, version ###VERSION###
Copyright Bill Allombert <ballombe@debian.org> 2001.
Modifications copyright 2002, 2003 Julian Gilbey <jdg@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}


# Main program

# Features:
# This are heuristics used to speed up the process.
# Since thay may be considered as "kludges" or worse "bugs"
# by some, they can be deactivated
# 0 disabled by default, 1 enabled by default.
%feature=(
	  "warn-local"=>1, "discard-check-version"=>1,
	  "trace-local"=>0, "catch-alternatives"=>1,
          "discard-sgml-catalogs"=>1,
	  );
%default_feature = %feature;

# First process configuration file options, then check for command-line
# options.  This is pretty much boilerplate.

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DPKG_DEPCHECK_OPTIONS' => '',
		       );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
	$shell_cmd .= qq[$var="$config_vars{$var}";\n];
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
    
    if ($config_vars{'DPKG_DEPCHECK_OPTIONS'} ne '') {
	unshift @ARGV, split(' ', $config_vars{'DPKG_DEPCHECK_OPTIONS'});
    }
}

# Default option:
$opts{"pkgs"} = 'all';
$opts{"allpkgs"} = 0;

Getopt::Long::Configure('bundling','require_order');
my $opts_ret =
    GetOptions("h|help" => sub { usage(); exit; },
	       "v|version" => sub { version(); exit; },
	       "a|all" => sub { $opts{"allpkgs"}=1; },
	       "b|build-depends" => sub { $opts{"pkgs"}='build'; },
	       "d|ignore-dev-deps" => sub { $opts{"pkgs"}='dev'; },
	       "m|min-deps" => sub { $opts{"pkgs"}='min'; },
	       "C|C-locale" => \$opts{"C"},
	       "no-C-locale|noC-locale" => sub { $opts{"C"}=0; },
	       "l|list-files" => \$opts{"l"},
	       "no-list-files|nolist-files" => sub { $opts{"l"}=0; },
	       "o|output=s" => \$opts{"o"},
	       "O|strace-output=s" => \$opts{"strace-output"},
	       "I|strace-input=s" => \$opts{"strace-input"},
	       "f|features=s" => \&process_features,
	       "no-conf" => \$opts{"noconf"},
	       "noconf" => \$opts{"noconf"},
	       );

if ($opts{"noconf"}) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}

if (! $opts_ret) {
    die "$progname: I didn't recognise some command-line option there;\nplease fix and try again.  (Use --help for more info.)\n";
}

if ($opts{"pkgs"} eq 'all') {
    $opts{"allpkgs"} = 0;
} else {
    # We don't initialise the packages database before doing this check,
    # as that takes quite some time
    unless (system('dpkg -L build-essential >/dev/null 2>&1') >> 8 == 0) {
	die "You must have the build-essential package installed or use the --all option\n";
    }
}


@ARGV > 0 or $opts{"strace-input"} or
    die "You need to specify a command!  Run $progname --help for more info\n";

# Run the command and trace it to see what's going on
my @usedfiles = getusedfiles(@ARGV);

if ($opts{"o"}) {
    $opts{"o"} =~ s%^(\s)%./$1%;
    open STDOUT,"> $opts{'o'}" or
	warn "Cannot open $opts{'o'} for writing: $!\nTrying to use stdout instead\n";
} else {
    # Visual space
    print "\n\n";
    print '-' x 70, "\n";
}

# Get each file once only, and drop any we are not interested in.
# Also, expand all symlinks so we get full pathnames of the real file accessed.
@usedfiles = filterfiles(@usedfiles);

# Forget about the few files we are expecting to see but can ignore
@usedfiles = SetMinus(\@usedfiles, \@known_files);

# For a message at the end
my $number_files_used = scalar @usedfiles;

# Initialise the packages database unless --all is given
my $packagedeps;

# @used_ess_files will contain those files used which are in essential packages
my @used_ess_files;

# Exclude essential and build-essential packages?
if ($opts{"pkgs"} ne 'all')
{
    $packagedeps = new Devscripts::PackageDeps ('/var/lib/dpkg/status');
    my @essential = PackagesMatch('^Essential: yes$');
    my @essential_packages =
	$packagedeps->full_dependencies('build-essential', @essential);
    my @essential_files = PackagesToFiles(@essential_packages);
    @used_ess_files = SetInter(\@usedfiles,\@essential_files);
    @usedfiles = SetMinus(\@usedfiles,\@used_ess_files);
}

# Now let's find out which packages are used...
my @ess_packages = FilesToPackages(@used_ess_files);
my @packages = FilesToPackages(@usedfiles);
my %dep_packages = ();  # packages which are depended upon by others

# ... and remove their files from the filelist
if ($opts{"l"}) {
    # Have to do it slowly :-(
    if ($opts{"allpkgs"}) {
	print "Files used in each of the needed build-essential or essential packages:\n";
	foreach my $pkg (sort @ess_packages) {
	    my @pkgfiles = PackagesToFiles($pkg);
	    print "Files used in (build-)essential package $pkg:\n  ",
	    join("\n  ", SetInter(\@used_ess_files, \@pkgfiles)), "\n";
	}
	print "\n";
    }
    print "Files used in each of the needed packages:\n";
    foreach my $pkg (sort @packages) {
	my @pkgfiles = PackagesToFiles($pkg);
	print "Files used in package $pkg:\n  ",
	    join("\n  ", SetInter(\@usedfiles, \@pkgfiles)), "\n";
	# We take care to note any files used which
	# do not appear in any package
	@usedfiles = SetMinus(\@usedfiles, \@pkgfiles);
    }
    print "\n";
} else {
    # We take care to note any files used which
    # do not appear in any package
    my @pkgfiles = PackagesToFiles(@packages);
    @usedfiles = SetMinus(\@usedfiles, \@pkgfiles);
}

if ($opts{"pkgs"} eq 'dev') {
    # We also remove any direct dependencies of '-dev' packages
    my %pkgs;
    @pkgs{@packages} = (1) x @packages;

    foreach my $pkg (@packages) {
	next unless $pkg =~ /-dev$/;
	my @deps = $packagedeps->dependencies($pkg);
	foreach my $dep (@deps) {
	    $dep = $$dep[0] if ref $dep;
	    if (exists $pkgs{$dep}) {
		$dep_packages{$dep} = $pkg;
		delete $pkgs{$dep};
	    }
	}
    }

    @packages = keys %pkgs;
}
elsif ($opts{"pkgs"} eq 'min') {
    # Do a mindep job on the package list
    my ($packages_ref,$dep_packages_ref) =
	$packagedeps->min_dependencies(@packages);
    @packages = @$packages_ref;
    %dep_packages = %$dep_packages_ref;
}

print "Summary: $number_files_used files considered.\n" if $opts{"l"};
# Ignore unrecognised /var/... files
@usedfiles = grep ! /^\/var\//, @usedfiles;
if (@usedfiles) {
    warn "The following files did not appear to belong to any package:\n";
    warn join("\n", @usedfiles) . "\n";
}

print "Packages ", ($opts{"pkgs"} eq 'all') ? "used" : "needed", ":\n  ";
print join("\n  ", @packages), "\n";

if ($opts{"allpkgs"}) {
    if (@ess_packages) {
	print "\n(Build-)Essential packages used:\n  ";
	print join("\n  ", @ess_packages), "\n";
    } else {
	print "\nNo (Build-)Essential packages used\n";
    }

    if (scalar keys %dep_packages) {
	print "\nOther packages used with depending packages listed:\n";
	foreach my $pkg (sort keys %dep_packages) {
	    print "  $pkg  <=  $dep_packages{$pkg}\n";
	}
    }
}

exit 0;


### Subroutines

# This sub is handed two arguments: f or feature, and the setting

sub process_features ($$)
{
    foreach (split(',', $_[1])) {
	my $state=1;
	m/^-/ and $state=0;
	s/^[-+]//;
	if (exists $feature{$_}) {
	    $feature{$_}=$state;
	} else {
	    die("Unknown feature $_\n");
	}
    }
}


# Get used files.  This runs the requested command (given as parameters
# to this sub) under strace and then parses the output, returning a list
# of all absolute filenames successfully opened or execve'd.

sub getusedfiles (@)
{
    my $file;
    if ($opts{"strace-input"}) {
	$file=$opts{"strace-input"};
    }
    else {
	my $old_preload = $ENV{'LD_PRELOAD'} || undef;
	my $old_locale = $ENV{'LC_ALL'} || undef;
	my $trace_preload = defined $old_preload ?
	    "$old_preload $vforklib" : $vforklib;
	$file = $opts{"strace-output"} || `tempfile -p depcheck`;
	chomp $file;
	$file =~ s%^(\s)%./$1%;
	my @strace_cmd=('strace', '-e', 'trace=open,execve',  '-f',
			'-q', '-o', $file, @_);
	$ENV{'LD_PRELOAD'} = $trace_preload;
	$ENV{'LC_ALL'}="C" if $opts{"C"};
	system(@strace_cmd);
	$? >> 8 == 0 or
	    die "Running strace failed (command line:\n@strace_cmd\n";
	if (defined $old_preload) { $ENV{'LD_PRELOAD'} = $old_preload; }
	else { delete $ENV{'LD_PRELOAD'}; }
	if (defined $old_locale) { $ENV{'LC_ALL'} = $old_locale; }
	else { delete $ENV{'LC_ALL'}; }
    }
    
    my %openfiles=();
    open FILE, $file or die "Cannot open $file for reading: $!\n";
    while (<FILE>) {
	# We only consider absolute filenames
	m/^\d+\s+(\w+)\(\"(\/.*?)\",.*\) = (-?\d+)/ or next;
	my ($syscall, $filename, $status) = ($1, $2, $3);
	if ($syscall eq 'open') { next unless $status >= 0; }
	elsif ($syscall eq 'execve') { next unless $status == 0; }
	else { next; }  # unrecognised syscall
	next if $feature{"discard-check-version"} and
	    m/execve\(\"\Q$filename\E\", \[\"[^\"]+\", "--version"\], /;
	# So it's a real file
	$openfiles{$filename}=1;
    }

    unlink $file unless $opts{"strace-input"} or $opts{"strace-output"};

    return keys %openfiles;
}


# Select those files which we are interested in, as determined by the
# user-specified options

sub filterfiles (@)
{
    my %files=();
    my %local_files=();
    my %alternatives=();
    my $pwd=cwd();

    foreach my $file (@_) {
	next unless -f $file;

	my @links=();
	my $prevlink='';
	foreach (ListSymlinks($file, $pwd)) {
	    if (m%^/(usr|var)/local(/|\z)%) {
		$feature{"warn-local"} and $local_files{$_} = 1;
		unless ($feature{"trace-local"}) {
		    $prevlink = $_;
		    next;
		}
	    }
	    elsif ($feature{"discard-sgml-catalogs"} and
		   m%^/usr/share/(sgml/.*\.cat|.*/catalog)%) {
		next;
	    }
	    elsif ($feature{"catch-alternatives"} and m%^/etc/alternatives/%) {
		$alternatives{"$prevlink --> " . readlink($_)} = 1
		    if $prevlink;
	    }
	    $prevlink=$_;
	    # If it's not in one of these dirs, we skip it
	    next unless m%^/(bin|etc|lib|sbin|usr|var)%;
	    push @links, $_;
	}

	@files{@links} = (1) x @links;
    }

    if (keys %local_files) {
	print "warning: files in /usr/local or /var/local used:\n",
	    join("\n", sort keys %local_files), "\n";
    }
    if (keys %alternatives) {
	print "warning: alternatives used:\n",
	    join("\n", sort keys %alternatives), "\n";
    }

    return keys %files;
}



# The purpose here is to find out all the symlinks crossed by a file access.
# We work from the end of the filename (basename) back towards the root of
# the filename (solving bug#246006 where /usr is a symlink to another
# filesystem), repeating this process until we end up with an absolute
# filename with no symlinks in it.  We return a list of all of the
# full filenames encountered.
# For example, if /usr -> /moved/usr, then
# /usr/bin/X11/xapp would yield:
# /usr/bin/X11/xapp, /usr/X11R6/bin/xapp, /moved/usr/X11R6/bin/xapp

# input: file, pwd
# output: if symlink found: (readlink-replaced file, prefix)
#         if not: (file, '')

sub NextSymlink ($)
{
    my $file = shift;

    my $filestart = $file;
    my $fileend = '';

    while ($filestart ne '/') {
	if (-l $filestart) {
	    my $link = readlink($filestart);
	    my $parent = dirname $filestart;
	    if ($link =~ m%^/%) { # absolute symlink
		return $link . $fileend;
	    }
	    while ($link =~ s%^\./%%) { }
	    # The following is not actually correct: if we have
	    # /usr -> /moved/usr and /usr/mylib -> ../mylibdir, then
	    # /usr/mylib should resolve to /moved/mylibdir, not /mylibdir
	    # But if we try to take this into account, we would need to
	    # use something like Cwd(), which would immediately resolve
	    # /usr -> /moved/usr, losing us the opportunity of recognising
	    # the filename we want.  This is a bug we'll probably have to
	    # cope with.
	    # One way of doing this correctly would be to have a function
	    # resolvelink which would recursively resolve any initial ../ in
	    # symlinks, but no more than that.  But I don't really want to
	    # implement this unless it really proves to be necessary:
	    # people shouldn't be having evil symlinks like that on their
	    # system!!
	    while ($link =~ s%^\.\./%%) { $parent = dirname $parent; }
	    return $parent . '/' . $link . $fileend;
	}
	else {
	    $fileend = '/' . basename($filestart) . $fileend;
	    $filestart = dirname($filestart);
	}
    }
    return undef;
}


# input: file, pwd
# output: list of full filenames encountered en route

sub ListSymlinks ($$)
{
    my ($file, $path) = @_;

    if ($file !~ m%^/%) { $file = "$path/$file"; }

    my @fn = ($file);

    while ($file = NextSymlink($file)) {
	push @fn, $file;
    }

    return @fn;
}
