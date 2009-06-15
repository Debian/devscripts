#! /usr/bin/perl -w

# Original shell script version:
# Copyright 1998,1999 Yann Dirson <dirson@debian.org>
# Perl version:
# Copyright 1999,2000,2001 by Julian Gilbey <jdg@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2 ONLY,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use 5.006_000;
use strict;
use Cwd;
use File::Basename;
use File::Temp qw/ tempdir tempfile /;
use lib '/usr/share/devscripts';
use Devscripts::Versort;

# Predeclare functions
sub wdiff_control_files($$$$$);
sub process_debc($$);
sub process_debI($);
sub mktmpdirs();
sub fatal(@);

my $progname = basename($0);
my $modified_conf_msg;
my $exit_status = 0;
my $dummyname = "---DUMMY---";

sub usage {
    print <<"EOF";
Usage: $progname [option]
   or: $progname [option] ... deb1 deb2
   or: $progname [option] ... changes1 changes2
   or: $progname [option] ... dsc1 dsc2
   or: $progname [option] ... --from deb1a deb1b ... --to deb2a deb2b ...
Valid options are:
    --no-conf, --noconf
                          Don\'t read devscripts config files;
                          must be the first option given
   --help, -h             Display this message
   --version, -v          Display version and copyright info
   --move FROM TO,        The prefix FROM in first packages has
     -m FROM TO             been renamed TO in the new packages
                            (multiple permitted)
   --move-regex FROM TO,  The prefix FROM in first packages has
                            been renamed TO in the new packages
                            (multiple permitted), using regexp substitution
   --dirs, -d             Note changes in directories as well as files
   --nodirs               Do not note changes in directories (default)
   --nocontrol            Skip comparing control files
   --control              Do compare control files
   --controlfiles FILE,FILE,...
                          Which control files to compare; default is just
                            control; could include preinst, etc, config or
                            ALL to compare all control files present
   --wp, --wl, --wt       Pass the option -p, -l, -t respectively to wdiff
                            (only one should be used)
   --wdiff-source-control When processing source packages, compare control
                            files as with --control for binary packages
   --no-wdiff-source-control
                          Do not do so (default)
   --show-moved           Indicate also all files which have moved
                            between packages
   --noshow-moved         Do not also indicate all files which have moved
                            between packages (default)
   --renamed FROM TO      The package formerly called FROM has been
                            renamed TO; only of interest with --show-moved
                            (multiple permitted)
   --quiet, -q            Be quiet if no differences were found
   --exclude PATTERN      Exclude files that match PATTERN
   --ignore-space, -w     Ignore whitespace in diffs
   --diffstat             Include the result of diffstat before the diff
   --no-diffstat          Do not do so (default)
   --auto-ver-sort        When comparing source packages, ensure the
                          comparison is performed in version order
   --no-auto-ver-sort     Do not do so (default)

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999,2000,2001 by Julian Gilbey <jdg\@debian.org>,
based on original code which is copyright 1998,1999 by
Yann Dirson <dirson\@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 ONLY.
EOF

# Start by setting default values

my $ignore_dirs = 1;
my $compare_control = 1;
my $controlfiles = 'control';
my $show_moved = 0;
my $wdiff_opt = '';
my @diff_opts = ();
my $show_diffstat = 0;
my $wdiff_source_control = 0;
my $auto_ver_sort = 0;

my $quiet = 0;

# Next, read read configuration files and then command line
# The next stuff is boilerplate

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DEBDIFF_DIRS' => 'no',
		       'DEBDIFF_CONTROL' => 'yes',
		       'DEBDIFF_CONTROLFILES' => 'control',
		       'DEBDIFF_SHOW_MOVED' => 'no',
		       'DEBDIFF_WDIFF_OPT' => '',
		       'DEBDIFF_SHOW_DIFFSTAT' => 'no',
		       'DEBDIFF_WDIFF_SOURCE_CONTROL' => 'no',
		       'DEBDIFF_AUTO_VER_SORT' => 'no',
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

    # Check validity
    $config_vars{'DEBDIFF_DIRS'} =~ /^(yes|no)$/
	or $config_vars{'DEBDIFF_DIRS'}='no';
    $config_vars{'DEBDIFF_CONTROL'} =~ /^(yes|no)$/
	or $config_vars{'DEBDIFF_CONTROL'}='yes';
    $config_vars{'DEBDIFF_SHOW_MOVED'} =~ /^(yes|no)$/
	or $config_vars{'DEBDIFF_SHOW_MOVED'}='no';
    $config_vars{'DEBDIFF_SHOW_DIFFSTAT'} =~ /^(yes|no)$/
	or $config_vars{'DEBDIFF_SHOW_DIFFSTAT'}='no';
    $config_vars{'DEBDIFF_WDIFF_SOURCE_CONTROL'} =~ /^(yes|no)$/
	or $config_vars{'DEBDIFF_WDIFF_SOURCE_CONTROL'}='no';
    $config_vars{'DEBDIFF_AUTO_VER_SORT'} =~ /^(yes|no)$/
	or $config_vars{'DEBDIFF_AUTO_VER_SORT'}='no';

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $ignore_dirs = $config_vars{'DEBDIFF_DIRS'} eq 'yes' ? 0 : 1;
    $compare_control = $config_vars{'DEBDIFF_CONTROL'} eq 'no' ? 0 : 1;
    $controlfiles = $config_vars{'DEBDIFF_CONTROLFILES'};
    $show_moved = $config_vars{'DEBDIFF_SHOW_MOVED'} eq 'yes' ? 1 : 0;
    $wdiff_opt = $config_vars{'DEBDIFF_WDIFF_OPT'} =~ /^-([plt])$/ ? $1 : '';
    $show_diffstat = $config_vars{'DEBDIFF_SHOW_DIFFSTAT'} eq 'yes' ? 1 : 0;
    $wdiff_source_control = $config_vars{'DEBDIFF_WDIFF_SOURCE_CONTROL'}
	eq 'yes' ? 1 : 0;
    $auto_ver_sort = $config_vars{'DEBDIFF_AUTO_VER_SORT'} eq 'yes' ? 1 : 0;

}

# Are they a pair of debs, changes or dsc files, or a list of debs?
my $type = '';
my @excludes = ();
my @move = ();
my %renamed = ();


# handle command-line options

while (@ARGV) {
    if ($ARGV[0] =~ /^(--help|-h)$/) { usage(); exit 0; }
    if ($ARGV[0] =~ /^(--version|-v)$/) { print $version; exit 0; }
    if ($ARGV[0] =~ /^(--move(-regex)?|-m)$/) {
	fatal "Malformed command-line option $ARGV[0]; run $progname --help for more info"
	    unless @ARGV >= 3;

	my $regex = $ARGV[0] eq '--move-regex' ? 1 : 0;
	shift @ARGV;

	# Ensure from and to values all begin with a slash
	# dpkg -c produces filenames such as ./usr/lib/filename
	my $from = shift;
	my $to   = shift;
	$from =~ s%^\./%/%;
	$to   =~ s%^\./%/%;

	if ($regex) {
	    # quote ':' in the from and to patterns;
	    # used later as a pattern delimiter
	    $from =~ s/:/\\:/g;
	    $to =~ s/:/\\:/g;
	}
	push @move, [$regex, $from, $to];
    }
    elsif ($ARGV[0] eq '--renamed') {
	fatal "Malformed command-line option $ARGV[0]; run $progname --help for more info"
	    unless @ARGV >= 3;
	shift @ARGV;

	my $from = shift;
	my $to   = shift;
	$renamed{$from} = $to;
    }
    elsif ($ARGV[0] eq '--exclude') {
	fatal "Malformed command-line option $ARGV[0]; run $progname --help for more info"
	    unless @ARGV >= 2;
	shift @ARGV;

	my $exclude = shift;
	push @excludes, $exclude;
    }
    elsif ($ARGV[0] =~ s/^--exclude=//) {
	my $exclude = shift;
	push @excludes, $exclude;
    }
    elsif ($ARGV[0] eq '--controlfiles') {
	fatal "Malformed command-line option $ARGV[0]; run $progname --help for more info"
	    unless @ARGV >= 2;
	shift @ARGV;

	$controlfiles = shift;
    }
    elsif ($ARGV[0] =~ s/^--controlfiles=//) {
	$controlfiles = shift;
    }
    elsif ($ARGV[0] =~ /^(--dirs|-d)$/) { $ignore_dirs = 0; shift; }
    elsif ($ARGV[0] eq '--nodirs') { $ignore_dirs = 1; shift; }
    elsif ($ARGV[0] =~ /^(--quiet|-q)$/) { $quiet = 1; shift; }
    elsif ($ARGV[0] =~ /^(--show-moved|-s)$/) { $show_moved = 1; shift; }
    elsif ($ARGV[0] eq '--noshow-moved') { $show_moved = 0; shift; }
    elsif ($ARGV[0] eq '--nocontrol') { $compare_control = 0; shift; }
    elsif ($ARGV[0] eq '--control') { $compare_control = 1; shift; }
    elsif ($ARGV[0] eq '--from') { $type = 'debs'; last; }
    elsif ($ARGV[0] =~ /^--w([plt])$/) { $wdiff_opt = "-$1"; shift; }
    elsif ($ARGV[0] =~ /^(--ignore-space|-w)$/) {
	push @diff_opts, "-w"; 
	shift;
    }
    elsif ($ARGV[0] eq '--diffstat') { $show_diffstat = 1; shift; }
    elsif ($ARGV[0] =~ /^--no-?diffstat$/) { $show_diffstat = 0; shift; }
    elsif ($ARGV[0] eq '--wdiff-source-control') { $wdiff_source_control = 1; shift; }
    elsif ($ARGV[0] =~ /^--no-?wdiff-source-control$/) { $wdiff_source_control = 0; shift; }
    elsif ($ARGV[0] eq '--auto-ver-sort') { $auto_ver_sort = 1; shift; }
    elsif ($ARGV[0] =~ /^--no-?auto-ver-sort$/) { $auto_ver_sort = 0; shift; }
    elsif ($ARGV[0] =~ /^--no-?conf$/) {
	fatal "--no-conf is only acceptable as the first command-line option!";
    }

    # Not a recognised option
    elsif ($ARGV[0] =~ /^-/) {
	fatal "Unrecognised command-line option $ARGV[0]; run $progname --help for more info";
    }
    else {
	# End of command line options
	last;
    }
}

my $guessed_version = 0;

# If no file is given, assume that we are in a source directory
# and try to create a diff with the previous version
if(@ARGV == 0) {
    my $namepat = qr/[-+0-9a-z.]/i;

    fatal "Can't read file: debian/changelog" unless -r "debian/changelog";
    open CHL, "debian/changelog";
    while(<CHL>) {
	if(/^(\w$namepat*)\s\((\d+:)?(.+)\)((\s+$namepat+)+)\;\surgency=.+$/) {
	    unshift @ARGV, "../".$1."_".$3.".dsc";
	    $guessed_version++;
	}
	last if $guessed_version > 1;
    }
    close CHL;
}

if (! $type) {
    # we need 2 deb files or changes files to compare
    fatal "Need exactly two deb files or changes files to compare"
	unless @ARGV == 2;

    foreach my $i (0,1) {
	fatal "Can't read file: $ARGV[$i]" unless -r $ARGV[$i];
    }

    if ($ARGV[0] =~ /\.deb$/) { $type = 'deb'; }
    elsif ($ARGV[0] =~ /\.udeb$/) { $type = 'deb'; }
    elsif ($ARGV[0] =~ /\.changes$/) { $type = 'changes'; }
    elsif ($ARGV[0] =~ /\.dsc$/) { $type = 'dsc'; }
    elsif (`file $ARGV[0]` =~ /Debian/) { $type = 'deb'; }
    else {
	fatal "Could not recognise files; the names should end .deb, .udeb, .changes or .dsc";
    }
    if ($ARGV[1] !~ /\.$type$/) {
	unless ($type eq 'deb' and `file $ARGV[0]` =~ /Debian/) {
	    fatal "The two filenames must have the same suffix, either .deb, .udeb, .changes or .dsc";
	}
    }
}

# We collect up the individual deb information in the hashes
# %deb1 and %deb2, each key of which is a .deb name and each value is
# a list ref.  Note we need to use our, not my, as we will be symbolically
# referencing these variables
my @CommonDebs = ();
my @singledeb;
our (%debs1, %debs2, %files1, %files2, @D1, @D2, $dir1, $dir2, %DebPaths1, %DebPaths2);

if ($type eq 'deb') {
    no strict 'refs';
    foreach my $i (1,2) {
	my $deb = shift;
	my $debc = `env LC_ALL=C dpkg-deb -c $deb`;
	$? == 0 or fatal "dpkg-deb -c $deb failed!";
	my $debI = `env LC_ALL=C dpkg-deb -I $deb`;
	$? == 0 or fatal "dpkg-deb -I $deb failed!";
	# Store the name for later
	$singledeb[$i] = $deb;
	# get package name itself
	$deb =~ s,.*/,,; $deb =~ s/_.*//;
	@{"D$i"} = @{process_debc($debc,$i)};
	push @{"D$i"}, @{process_debI($debI)};
    }
}
elsif ($type eq 'changes' or $type eq 'debs') {
    # Have to parse .changes files or remaining arguments
    my $pwd = cwd;
    foreach my $i (1,2) {
	my (@debs) = ();
	if ($type eq 'debs') {
	    if (@ARGV < 2) {
		# Oops!  There should be at least --from|--to deb ...
		fatal "Missing .deb names or missing --to!  (Run debdiff -h for help)\n";
	    }
	    shift;  # get rid of --from or --to
	    while (@ARGV and $ARGV[0] ne '--to') {
		push @debs, shift;
	    }

	    # Is there only one .deb listed?
	    if (@debs == 1) {
		$singledeb[$i] = $debs[0];
	    }
	} else {
	    my $changes = shift;
	    open CHANGES, $changes
		or fatal "Couldn't open $changes: $!";
	    my $infiles = 0;
	    while (<CHANGES>) {
		last if $infiles and /^[^ ]/;
		/^Files:/ and $infiles=1, next;
		next unless $infiles;
		/ (\S*.u?deb)$/ and push @debs, dirname($changes) . '/' . $1;
	    }
	    close CHANGES
		or fatal "Problem reading $changes: $!";

	    # Is there only one .deb listed?
	    if (@debs == 1) {
		$singledeb[$i] = $debs[0];
	    }
	}

	foreach my $deb (@debs) {
	    no strict 'refs';
	    fatal "Can't read file: $deb" unless -r $deb;
	    my $debc = `env LC_ALL=C dpkg-deb -c $deb`;
	    $? == 0 or fatal "dpkg-deb -c $deb failed!";
	    my $debI = `env LC_ALL=C dpkg-deb -I $deb`;
	    $? == 0 or fatal "dpkg-deb -I $deb failed!";
	    my $debpath = $deb;
	    # get package name itself
	    $deb =~ s,.*/,,; $deb =~ s/_.*//;
	    $deb = $renamed{$deb} if $i == 1 and exists $renamed{$deb};
	    if (exists ${"debs$i"}{$deb}) {
		warn "Same package name appears more than once (possibly due to renaming): $deb\n";
	    } else {
		${"debs$i"}{$deb} = 1;
	    }
	    ${"DebPaths$i"}{$deb} = $debpath;
	    foreach my $file (@{process_debc($debc,$i)}) {
		${"files$i"}{$file} ||= "";
		${"files$i"}{$file} .= "$deb:";
	    }
	    foreach my $control (@{process_debI($debI)}) {
		${"files$i"}{$control} ||= "";
		${"files$i"}{$control} .= "$deb:";
	    }
	}
	no strict 'refs';
	@{"D$i"} = keys %{"files$i"};
	# Go back again
	chdir $pwd or fatal "Couldn't chdir $pwd: $!";
    }
}
elsif ($type eq 'dsc') {
    # Compare source packages
    my $pwd = cwd;

    my (@origs, @diffs, @dscs, @dscformats, @versions);
    foreach my $i (1,2) {
	my $dsc = shift;
	chdir dirname($dsc)
	    or fatal "Couldn't chdir ", dirname($dsc), ": $!";

	$dscs[$i] = cwd() . '/' . basename($dsc);

	open DSC, basename($dsc) or fatal "Couldn't open $dsc: $!";

	my $infiles=0;
	while(<DSC>) {
	    if (/^Files:/) {
		$infiles=1;
		next;
	    } elsif (/^Format: (.*)$/) {
		$dscformats[$i] = $1;
	    } elsif (/^Version: (.*)$/) {
		$versions[$i - 1] = [ $1, $i ];
	    }
	    next unless $infiles;
	    last if /^\s*$/;
	    last if /^[-\w]+:/;  # don't expect this, but who knows?
	    chomp;

	    # This had better match
	    if (/^\s+[0-9a-f]{32}\s+\d+\s+(\S+)$/) {
		my $file = $1;
		if ($file =~ /\.diff\.gz$/) {
		    $diffs[$i] = cwd() . '/' . $file;
		}
		elsif ($file =~ /(\.orig)?\.tar\.(gz|bz2|lzma)$/) {
		    $origs[$i] = $file;
		}
	    } else {
		warn "Unrecognised file line in .dsc:\n$_\n";
	    }
	}

	close DSC or fatal "Problem closing $dsc: $!";
	# Go back again
	chdir $pwd or fatal "Couldn't chdir $pwd: $!";
    }

    @versions = Devscripts::Versort::versort(@versions);
    # If the versions are currently out of order, should we swap them?
    if ($auto_ver_sort and !$guessed_version and $versions[0][1] == 1) {
	foreach my $var ((\@origs, \@diffs, \@dscs, \@dscformats)) {
	    my $temp = @{$var}[1];
	    @{$var}[1] = @{$var}[2];
	    @{$var}[2] = $temp;
	}
    }

    # Do we have interdiff?
    system("command -v interdiff >/dev/null 2>&1");
    my $use_interdiff = ($?==0) ? 1 : 0;
    system("command -v diffstat >/dev/null 2>&1");
    my $have_diffstat = ($?==0) ? 1 : 0;
    system("command -v wdiff >/dev/null 2>&1");
    my $have_wdiff = ($?==0) ? 1 : 0;

    my ($fh, $filename) = tempfile("debdiffXXXXXX",
				SUFFIX => ".diff",
				DIR => File::Spec->tmpdir,
				UNLINK => 1);

    # When wdiffing source control files we always fully extract both source
    # packages as it's the easiest way of getting the debian/control file,
    # particularly if the orig tar ball contains one which is patched in the
    # diffs
    if ($origs[1] eq $origs[2] and defined $diffs[1] and defined $diffs[2]
	and scalar(@excludes) == 0 and $use_interdiff and !$wdiff_source_control) {
	# same orig tar ball, interdiff exists and not wdiffing

	my $command = join( " ", ("interdiff", "-z", @diff_opts, "'$diffs[1]'",
	    "'$diffs[2]'", ">", $filename) );
	my $rv = system($command);
	if ($rv) {
	    fatal "interdiff -z $diffs[1] $diffs[2] failed!";
	} else {
	    if ($have_diffstat and $show_diffstat) {
		my $header = "diffstat for " . basename($diffs[1])
				. " " . basename($diffs[2]) . "\n\n";
		$header =~ s/\.diff\.gz//g;
		print $header;
		system("diffstat $filename");
		print "\n";
	    }

	    if (-s $filename) {
		open( INTERDIFF, '<', $filename );
		while( <INTERDIFF> ) {
		    print $_;
		}
		close INTERDIFF;

		$exit_status = 1;
	    }
	}
    } else {
	# Any other situation
	if ($origs[1] eq $origs[2] and
	    defined $diffs[1] and defined $diffs[2] and
	    scalar(@excludes) == 0 and !$wdiff_source_control) {
	    warn "Warning: You do not seem to have interdiff (in the patchutils package)\ninstalled; this program would use it if it were available.\n";
	}
	# possibly different orig tarballs, or no interdiff installed,
	# or wdiffing debian/control
	our ($sdir1, $sdir2);
	mktmpdirs();
	for my $i (1,2) {
	    no strict 'refs';
	    my @opts = ('-x');
	    push (@opts, '--skip-patches') if $dscformats[$i] eq '3.0 (quilt)';
	    my $cmd = qq(cd ${"dir$i"} && dpkg-source @opts $dscs[$i] >/dev/null);
	    system $cmd;
	    if ($? != 0) {
	    	    my $dir = dirname $dscs[1] if $i == 2;
	    	    $dir = dirname $dscs[2] if $i == 1;
	    	    my $cmdx = qq(cp $dir/$origs[$i] ${"dir$i"} >/dev/null);
		    system $cmdx;
		    fatal "$cmd failed" if $? != 0;
		    my $dscx = basename $dscs[$i];
		    $cmdx = qq(cp $diffs[$i] ${"dir$i"} && cp $dscs[$i] ${"dir$i"} && cd ${"dir$i"} && dpkg-source @opts $dscx > /dev/null);
		    system $cmdx;
		    fatal "$cmd failed" if $? != 0;
	    }
	    opendir DIR,${"dir$i"};
	    while ($_ = readdir(DIR)) {
		    next if $_ eq '.' || $_ eq '..' || ! -d ${"dir$i"}."/$_";
		    ${"sdir$i"} = $_;
		    last;
	    }
	    closedir(DIR);
	    opendir DIR,${"dir$i"}.'/'.${"sdir$i"};

	    my $tarballs = 1;
	    while ($_ = readdir(DIR)) {
		    my $unpacked = "=unpacked-tar" . $tarballs . "=";
		    my $filename = $_;
		    if ($_ =~ /tar.gz$/) {
			$filename =~ s%(.*)\.tar\.gz$%$1%;
			$tarballs++;
		        system qq(cd ${"dir$i"}/${"sdir$i"} && tar zxf $_ >/dev/null && test -d $filename && mv $filename $unpacked); 
		    }
		    if ($_ =~ /tar.bz$/ || $_ =~ /tar.bz2$/) {
			$filename =~ s%(.*)\.tar\.bz2?$%$1%;
			$tarballs++;
		        system qq(cd ${"dir$i"}/${"sdir$i"} && tar jxf $_ >/dev/null && test -d $filename && mv $filename $unpacked);
		    }
	    }
	    closedir(DIR);
	}

	my @command = ("diff", "-Nru", @diff_opts);
	for my $exclude (@excludes) {
	    push @command, ("--exclude", "'$exclude'");
	}
	push @command, ("'$dir1/$sdir1'", "'$dir2/$sdir2'");
	push @command, (">", $filename);

	# Execute diff and remove the common prefixes $dir1/$dir2, so the patch can be used with -p1,
	# as if when interdiff would have been used:
	system(join(" ", @command));

	if ($have_diffstat and $show_diffstat) {
	    print "diffstat for $sdir1 $sdir2\n\n";
	    system("diffstat $filename");
	    if ($? != 0) {
		fatal "Failed to diffstat $filename!";
	    }
	    print "\n";
	}

	if ($have_wdiff and $wdiff_source_control) {
	    # Abuse global variables slightly to create some temporary directories
	    my $tempdir1 = $dir1;
	    my $tempdir2 = $dir2;
	    mktmpdirs();
	    our $wdiffdir1 = $dir1;
	    our $wdiffdir2 = $dir2;
	    $dir1 = $tempdir1;
	    $dir2 = $tempdir2;
	    our @cf;
	    if ($controlfiles eq 'ALL') {
		@cf = ('control');
	    } else {
		@cf = split /,/, $controlfiles;
	    }

	    no strict 'refs';
	    for my $i (1,2) {
		foreach my $file (@cf) {
		    system qq(cp ${"dir$i"}/${"sdir$i"}/debian/$file ${"wdiffdir$i"});
		}
	    }
	    use strict 'refs';

	    # We don't support "ALL" for source packages as that would
	    # wdiff debian/*
	    $exit_status = wdiff_control_files($wdiffdir1, $wdiffdir2, $dummyname,
		$controlfiles eq 'ALL' ? 'control' : $controlfiles,
		$exit_status);
	    print "\n";

	    # Clean up
	    system ("rm", "-rf", $wdiffdir1, $wdiffdir2);
	}

	if (! -f $filename) {
	    fatal "Creation of diff file $filename failed!";
	} elsif (-s $filename) {
	    open( DIFF, '<', $filename ) or fatal "Opening diff file $filename failed!";

	    while(<DIFF>) {
		s/^--- $dir1\//--- /;
		s/^\+\+\+ $dir2\//+++ /;
		s/^(diff .*) $dir1\/\Q$sdir1\E/$1 $sdir1/;
		s/^(diff .*) $dir2\/\Q$sdir2\E/$1 $sdir2/;
		print;
	    }
	    close DIFF;

	    $exit_status = 1;
	}
    }

    exit $exit_status;
}
else {
    fatal "Internal error: \$type = $type unrecognised";
}


# Compare
# Start by a piece of common code to set up the @CommonDebs list and the like

my (@deblosses, @debgains);

{
    my %debs;
    grep $debs{$_}--, keys %debs1;
    grep $debs{$_}++, keys %debs2;

    @deblosses = sort grep $debs{$_} < 0, keys %debs;
    @debgains  = sort grep $debs{$_} > 0, keys %debs;
    @CommonDebs= sort grep $debs{$_} == 0, keys %debs;
}

if ($show_moved and $type ne 'deb') {
    if (@debgains) {
	my $msg = "Warning: these package names were in the second list but not in the first:";
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@debgains), "\n\n";
    }

    if (@deblosses) {
	print "\n" if @debgains;
	my $msg = "Warning: these package names were in the first list but not in the second:";
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@deblosses), "\n\n";
    }

    # We start by determining which files are in the first set of debs, the 
    # second set of debs or both.
    my %files;
    grep $files{$_}--, @D1;
    grep $files{$_}++, @D2;

    my @old = sort grep $files{$_} < 0, keys %files;
    my @new = sort grep $files{$_} > 0, keys %files;
    my @same = sort grep $files{$_} == 0, keys %files;

    # We store any changed files in a hash of hashes %changes, where
    # $changes{$from}{$to} is an array of files which have moved
    # from package $from to package $to; $from or $to is '-' if
    # the files have appeared or disappeared

    my %changes;
    my @funny;  # for storing changed files which appear in multiple debs

    foreach my $file (@old) {
	my @firstdebs = split /:/, $files1{$file};
	foreach my $firstdeb (@firstdebs) {
	    push @{$changes{$firstdeb}{'-'}}, $file;
	}
    }

    foreach my $file (@new) {
	my @seconddebs = split /:/, $files2{$file};
	foreach my $seconddeb (@seconddebs) {
	    push @{$changes{'-'}{$seconddeb}}, $file;
	}
    }

    foreach my $file (@same) {
	# Are they identical?
	next if $files1{$file} eq $files2{$file};

	# Ah, they're not the same.  If the file has moved from one deb
	# to another, we'll put a note in that pair.  But if the file
	# was in more than one deb or ends up in more than one deb, we'll
	# list it separately.
	my @fdebs1 = split (/:/, $files1{$file});
	my @fdebs2 = split (/:/, $files2{$file});
	
	if (@fdebs1 == 1 && @fdebs2 == 1) {
	    push @{$changes{$fdebs1[0]}{$fdebs2[0]}}, $file;
	} else {
	    # two packages to one or vice versa, or something like that
	    push @funny, [$file, \@fdebs1, \@fdebs2];
	}
    }

    # This is not a very efficient way of doing things if there are
    # lots of debs involved, but since that is highly unlikely, it
    # shouldn't be much of an issue
    my $changed = 0;

    for my $deb1 (sort(keys %debs1), '-') {
	next unless exists $changes{$deb1};
	for my $deb2 ('-', sort keys %debs2) {
	    next unless exists $changes{$deb1}{$deb2};
	    my $msg;
	    if (! $changed) {
		print "[The following lists of changes regard files as different if they have\ndifferent names, permissions or owners.]\n\n";
	    }
	    if ($deb1 eq '-') {
		$msg = "New files in second set of .debs, found in package $deb2";
	    } elsif ($deb2 eq '-') {
		$msg = "Files only in first set of .debs, found in package $deb1";
	    } else {
		$msg = "Files moved from package $deb1 to package $deb2";
	    }
	    print $msg, "\n", '-' x length $msg, "\n";
	    print join("\n",@{$changes{$deb1}{$deb2}}), "\n\n";
	    $changed = 1;
	}
    }

    if (@funny) {
	my $msg = "Files moved or copied from at least TWO packages or to at least TWO packages";
	print $msg, "\n", '-' x length $msg, "\n";
	for my $funny (@funny) {
	    print $$funny[0], "\n"; # filename and details
	    print "From package", (@{$$funny[1]} > 1 ? "s" : ""), ": ";
	    print join(", ", @{$$funny[1]}), "\n";
	    print "To package", (@{$$funny[2]} > 1 ? "s" : ""), ": ";
	    print join(", ", @{$$funny[2]}), "\n";
	}
	$changed = 1;
    }

    if (! $quiet && ! $changed) {
	print "File lists identical on package level (after any substitutions)\n";
    }
    $exit_status = 1 if $changed;
} else {
    my %files;
    grep $files{$_}--, @D1;
    grep $files{$_}++, @D2;

    my @losses = sort grep $files{$_} < 0, keys %files;
    my @gains = sort grep $files{$_} > 0, keys %files;

    if (@losses == 0 && @gains == 0) {
	print "File lists identical (after any substitutions)\n"
	    unless $quiet;
    } else {
	print "[The following lists of changes regard files as different if they have\ndifferent names, permissions or owners.]\n\n";
    }

    if (@gains) {
	my $msg;
	if ($type eq 'debs') {
	    $msg = "Files in second set of .debs but not in first";
	} else {
	    $msg = sprintf "Files in second .%s but not in first",
		    $type eq 'deb' ? 'deb' : 'changes';
	}
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@gains), "\n";
	$exit_status = 1;
    }

    if (@losses) {
	print "\n" if @gains;
	my $msg;
	if ($type eq 'debs') {
	    $msg = "Files in first set of .debs but not in second";
	} else {
	    $msg = sprintf "Files in first .%s but not in second",
		    $type eq 'deb' ? 'deb' : 'changes';
	}
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@losses), "\n";
	$exit_status = 1;
    }
}

# We compare the control files (at least the dependency fields)
if (defined $singledeb[1] and defined $singledeb[2]) {
	@CommonDebs = ( $dummyname );
	$DebPaths1{$dummyname} = $singledeb[1];
	$DebPaths2{$dummyname} = $singledeb[2];
}

exit $exit_status unless (@CommonDebs > 0) and $compare_control;

unless (system ("command -v wdiff >/dev/null 2>&1") == 0) {
    warn "Can't compare control files; wdiff package not installed\n";
    exit $exit_status;
}

for my $debname (@CommonDebs) {
    no strict 'refs';
    mktmpdirs();

    for my $i (1,2) {
	if (system('dpkg-deb', '-e', "${\"DebPaths$i\"}{$debname}", ${"dir$i"})) {
	    my $msg = "dpkg-deb -e ${\"DebPaths$i\"}{$debname} failed!";
	    system ("rm", "-rf", $dir1, $dir2);
	    fatal $msg;
	}
    }

    use strict 'refs';
    $exit_status = wdiff_control_files($dir1, $dir2, $debname, $controlfiles,
	$exit_status);

    # Clean up
    system ("rm", "-rf", $dir1, $dir2);
}

exit $exit_status;

###### Subroutines

# This routine takes the output of dpkg-deb -c and returns
# a processed listref
sub process_debc($$)
{
    my ($data,$number) = @_;
    my (@filelist);

    # Format of dpkg-deb -c output:
    # permissions owner/group size date time name ['->' link destination]
    $data =~ s/^(\S+)\s+(\S+)\s+(\S+\s+){3}/$1  $2   /mg;
    $data =~ s,   \./,   /,mg;
    @filelist = grep ! m|   /$|, split /\n/, $data; # don't bother keeping '/'

    # Are we keeping directory names in our filelists?
    if ($ignore_dirs) {
	@filelist = grep ! m|/$|, @filelist;
    }

    # Do the "move" substitutions in the order received for the first debs
    if ($number == 1 and @move) {
	my @split_filelist = map { m/^(\S+)  (\S+)   (.*)/ && [$1, $2, $3] }
	    @filelist;
	for my $move (@move) {
	    my $regex = $$move[0];
	    my $from  = $$move[1];
	    my $to    = $$move[2];
	    map { if ($regex) { eval "\$\$_[2] =~ s:$from:$to:g"; }
		  else { $$_[2] =~ s/\Q$from\E/$to/; } } @split_filelist;
	}
	@filelist = map { "$$_[0]  $$_[1]   $$_[2]" } @split_filelist;
    }

    return \@filelist;
}

# This does the same for dpkg-deb -I
sub process_debI($)
{
    my ($data) = @_;
    my (@filelist);

    # Format of dpkg-deb -c output:
    # 2 (always?) header lines
    #   nnnn bytes,    nnn lines   [*]  filename    [interpreter]
    # Package: ...
    # rest of control file

    foreach (split /\n/, $data) {
	last if /^Package:/;
	next unless /^\s+\d+\s+bytes,\s+\d+\s+lines\s+(\*)?\s+([\-\w]+)/;
	my $control = $2;
	my $perms = ($1 ? "-rwxr-xr-x" : "-rw-r--r--");
	push @filelist, "$perms  root/root   DEBIAN/$control";
    }

    return \@filelist;
}

sub wdiff_control_files($$$$$)
{
    my ($dir1, $dir2, $debname, $controlfiles, $origstatus) = @_;
    return unless defined $dir1 and defined $dir2 and defined $debname
	and defined $controlfiles;
    my @cf;
    my $status = $origstatus;
    if ($controlfiles eq 'ALL') {
	# only need to list one directory as we are only comparing control
	# files in both packages
	@cf = grep { ! /md5sums/ } map { basename($_); } glob("$dir1/*");
    } else {
	@cf = split /,/, $controlfiles;
    }

    foreach my $cf (@cf) {
	next unless -f "$dir1/$cf" and -f "$dir2/$cf";
	if ($cf eq 'control' or $cf eq 'conffiles') {
	    for my $file ("$dir1/$cf", "$dir2/$cf") {
		my ($fd, @hdrs);
		open $fd, '<', $file or fatal "Cannot read $file: $!";
		while (<$fd>) {
		    if (/^\s/ and @hdrs > 0) {
			$hdrs[$#hdrs] .= $_;
		    } else {
			push @hdrs, $_;
		    }
		}
		close $fd;
		open $fd, '>', $file or fatal "Cannot write $file: $!";
		print $fd sort @hdrs;
		close $fd;
	    }
	}
	my $wdiff = `wdiff -n $wdiff_opt $dir1/$cf $dir2/$cf`;
	my $usepkgname = $debname eq $dummyname ? "" : " of package $debname";
	if ($? >> 8 == 0) {
	    if (! $quiet) {
		print "\nNo differences were encountered between the $cf files$usepkgname\n";
	    }
	} elsif ($? >> 8 == 1) {
	    print "\n";
	    if ($wdiff_opt) {
		# Don't try messing with control codes
		my $msg = ucfirst($cf) . " files$usepkgname: wdiff output";
		print $msg, "\n", '-' x length $msg, "\n";
		print $wdiff;
	    } else {
		my @output;
		@output = split /\n/, $wdiff;
		@output = grep /(\[-|\{\+)/, @output;
		my $msg = ucfirst($cf) . " files$usepkgname: lines which differ (wdiff format)";
		print $msg, "\n", '-' x length $msg, "\n";
		print join("\n",@output), "\n";
	    }
	    $status = 1;
	} else {
	    warn "wdiff failed (exit status " . ($? >> 8) .
		(($? & 0x7f) ? " with signal " . ($? & 0x7f) : "") . ")\n";
	}
    }

    return $status;
}

sub mktmpdirs ()
{
    no strict 'refs';

    for my $i (1,2) {
	${"dir$i"}=tempdir( CLEANUP => 1 );
	fatal "Couldn't create temp directory"
	    if not defined ${"dir$i"};
    }
}

sub fatal(@)
{
    my ($pack,$file,$line);
    ($pack,$file,$line) = caller();
    (my $msg = "$progname: fatal error at line $line:\n@_\n") =~ tr/\0//d;
    $msg =~ s/\n\n$/\n/;
    die $msg;
}
