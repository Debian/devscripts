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
use File::Temp qw/ tempdir /;

# Predeclare functions
sub process_debc($$);
sub mktmpdirs();
sub fatal(@);

my $progname = basename($0);
my $modified_conf_msg;

sub usage {
    print <<"EOF";
Usage: $progname [option] ... deb1 deb2
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
   --nocontrol            Skip comparing control files when comparing
                            two .debs
   --control              Do compare control files when comparing
                            two .debs (default)
   --wp, --wl, --wt       Pass the option -p, -l, -t respectively to wdiff
                            (only one should be used)
   --show-moved           Indicate also all files which have moved
                            between packages
   --noshow-moved         Do not also indicate all files which have moved
                            between packages (default)
   --renamed FROM TO      The package formerly called FROM has been
                            renamed TO; only of interest with --show-moved
                            (multiple permitted)

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
my $show_moved = 0;
my $wdiff_opt = '';

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
		       'DEBDIFF_SHOW_MOVED' => 'no',
		       'DEBDIFF_WDIFF_OPT' => '',
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

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $ignore_dirs = $config_vars{'DEBDIFF_DIRS'} eq 'yes' ? 0 : 1;
    $compare_control = $config_vars{'DEBDIFF_CONTROL'} eq 'no' ? 0 : 1;
    $show_moved = $config_vars{'DEBDIFF_SHOW_MOVED'} eq 'yes' ? 1 : 0;
    $wdiff_opt = $config_vars{'DEBDIFF_WDIFF_OPT'} =~ /^-([plt])$/ ? $1 : '';
}

# Are they a pair of debs, changes or dsc files, or a list of debs?
my $type = '';
my @move = ();
my %renamed = ();

##
## handle command-line options
##

while (@ARGV) {
    if ($ARGV[0] =~ /^(--help|-h)$/) { usage(); exit 0; }
    if ($ARGV[0] =~ /^(--version|-v)$/) { print $version; exit 0; }
    if ($ARGV[0] =~ /^(--move(-regex)?|-m)$/) {
	fatal "Malformed command-line options; run $progname --help for more info"
	    unless @ARGV >= 3;

	my $regex = $ARGV[0] eq '--move-regex' ? 1 : 0;
	shift @ARGV;

	# Ensure from and to values all begin with a slash
	# From potato onward, dpkg -c gives filenames such as:
	#  ./usr/lib/filename
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
	fatal "Malformed command-line options; run $progname --help for more info"
	    unless @ARGV >= 3;
	shift @ARGV;

	my $from = shift;
	my $to   = shift;
	$renamed{$from} = $to;
    }
    elsif ($ARGV[0] =~ /^(--dirs|-d)$/) { $ignore_dirs = 0; shift; }
    elsif ($ARGV[0] eq '--nodirs') { $ignore_dirs = 1; shift; }
    elsif ($ARGV[0] =~ /^(--show-moved|-s)$/) { $show_moved = 1; shift; }
    elsif ($ARGV[0] eq '--noshow-moved') { $show_moved = 0; shift; }
    elsif ($ARGV[0] eq '--nocontrol') { $compare_control = 0; shift; }
    elsif ($ARGV[0] eq '--control') { $compare_control = 1; shift; }
    elsif ($ARGV[0] eq '--from') { $type = 'debs'; last; }
    elsif ($ARGV[0] =~ /^--w([plt])$/) { $wdiff_opt = "-$1"; shift; }
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
my @singledeb;
our (%debs1, %debs2, %files1, %files2, @D1, @D2, $dir1, $dir2);

if ($type eq 'deb') {
    no strict 'refs';
    foreach my $i (1,2) {
	my $deb = shift;
	my $debc = `env LC_ALL=C dpkg-deb -c $deb`;
	$? == 0 or fatal "dpkg-deb -c $deb failed!";
	# Store the name for later
	$singledeb[$i] = $deb;
	# get package name itself
	$deb =~ s,.*/,,; $deb =~ s/_.*//;
	@{"D$i"} = @{process_debc($debc,$i)};
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
		/ (\S*.u?deb)$/ and push @debs, $1;
        }
	    close CHANGES
		or fatal "Problem reading $changes: $!";

	    chdir dirname($changes)
		or fatal "Couldn't chdir ", dirname($changes), ": $!";

	    # Is there only one .deb listed?
	    if (@debs == 1) {
		$singledeb[$i] = dirname($changes) . '/' . $debs[0];
	    }
	}

	my %D = ();
	foreach my $deb (@debs) {
	    no strict 'refs';
	    fatal "Can't read file: $deb" unless -r $deb;
	    my $debc = `env LC_ALL=C dpkg-deb -c $deb`;
	    $? == 0 or fatal "dpkg-deb -c $deb failed!";
	    # get package name itself
	    $deb =~ s,.*/,,; $deb =~ s/_.*//;
	    $deb = $renamed{$deb} if $i == 1 and exists $renamed{$deb};
	    if (exists ${"debs$i"}{$deb}) {
		warn "Same package name appears more than once (possibly due to renaming): $deb\n";
	    } else {
		${"debs$i"}{$deb} = 1;
	    }
	    foreach my $file (@{process_debc($debc,$i)}) {
		${"files$i"}{$file} .= "$deb:";
		${"D$i"}{$file} = 1;
	    }
	}
	no strict 'refs';
	@{"D$i"} = keys %{"D$i"};
	# Go back again
	chdir $pwd or fatal "Couldn't chdir $pwd: $!";
    }
}
elsif ($type eq 'dsc') {
    # Compare source packages
    my $pwd = cwd;

    my (@origs, @diffs, @dscs);
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
		elsif ($file =~ /(\.orig)?\.tar\.gz$/) {
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

    # Do we have interdiff?
    system("(interdiff --version) >/dev/null 2>&1");
    my $use_interdiff = ($?==0) ? 1 : 0;

    if ($origs[1] eq $origs[2] and defined $diffs[1] and defined $diffs[2]
	and $use_interdiff) {
	# same orig tar ball and interdiff exists
	my $rv = system('interdiff', '-z', $diffs[1], $diffs[2]);
	if ($rv) {
	    fatal "interdiff -z $diffs[1] $diffs[2] failed!";
	}
    } else {
	# Any other situation
	if ($origs[1] eq $origs[2] and
	    defined $diffs[1] and defined $diffs[2]) {
	    warn "Warning: You do not seem to have interdiff (in the patchutils package)\ninstalled; this program would use it if it were available.\n";
	}
	# possibly different orig tarballs, or no interdiff installed
	our ($sdir1, $sdir2);
	mktmpdirs();
	for my $i (1,2) {
	    no strict 'refs';
	    my $cmd = qq(cd ${"dir$i"} && dpkg-source -x $dscs[$i] >/dev/null);
	    system $cmd;
	    fatal "$cmd failed" if $? != 0;
	    opendir DIR,${"dir$i"};
	    while ($_ = readdir(DIR)) {
		    next if $_ eq '.' || $_ eq '..' || ! -d ${"dir$i"}."/$_";
		    ${"sdir$i"} = $_;
		    last;
	    }
	    closedir(DIR);
	}
	system ("diff", "-Nru", "$dir1/$sdir1", "$dir2/$sdir2");
    }

    exit 0;
}
else {
    fatal "Internal error: \$type = $type unrecognised";
}

##
## Compare
##

if ($show_moved and $type ne 'deb') {
    # We first check the list of .debs
    my %debs;
    grep $debs{$_}--, keys %debs1;
    grep $debs{$_}++, keys %debs2;

    my @losses = sort grep $debs{$_} < 0, keys %debs;
    my @gains  = sort grep $debs{$_} > 0, keys %debs;

    if (@gains) {
	my $msg = "Warning: these package names were in the second list but not in the first:";
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@gains), "\n\n";
    }

    if (@losses) {
	print "\n" if @gains;
	my $msg = "Warning: these package names were in the first list but not in the second:";
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@losses), "\n\n";
    }

    # We run through all of the files in the first set of debs one by
    # one, then pick up any which are new in the second set of debs
    # We store any changed files in a hash of hashes %changes, where
    # $changes{$from}{$to} is an array of files which have moved
    # from package $from to package $to; $from or $to is '-' if
    # the files have appeared or disappeared
    my %changes;
    foreach my $file (@D1) {
	if (exists $files2{$file}) {
	    next if $files1{$file} eq $files2{$file};
	    # Ah, they're not the same.  We'll put a note in every
	    # pair where the file is in the deb in the first set but not
	    # in the deb in the second set
	    my @firstdebs = split /:/, $files1{$file};
	    my @seconddebs = split /:/, $files2{$file};
	    foreach my $firstdeb (@firstdebs) {
		foreach my $seconddeb (@seconddebs) {
		    next if $firstdeb eq $seconddeb;
		    push @{$changes{$firstdeb}{$seconddeb}}, $file;
		}
	    }
	}
	else {
	    my @firstdebs = split /:/, $files1{$file};
	    foreach my $firstdeb (@firstdebs) {
		push @{$changes{$firstdeb}{'-'}}, $file;
	    }
	}
    }

    my %files;
    grep $files{$_}--, @D1;
    grep $files{$_}++, @D2;

    my @new = sort grep $files{$_} > 0, keys %files;

    foreach my $file (@new) {
	my @seconddebs = split /:/, $files2{$file};
	foreach my $seconddeb (@seconddebs) {
	    push @{$changes{'-'}{$seconddeb}}, $file;
	}
    }

    # This is not a very efficient way of doing things if there are
    # lots of debs involved, but since that is highly unlikely, it
    # shouldn't be much of an issue
    my $changes = 0;

    for my $deb1 (sort(keys %debs1), '-') {
	next unless exists $changes{$deb1};
	for my $deb2 ('-', sort keys %debs2) {
	    next unless exists $changes{$deb1}{$deb2};
	    my $msg;
	    if ($deb1 eq '-') {
		$msg = "New files in second set of .debs, found in package $deb2";
	    } elsif ($deb2 eq '-') {
		$msg = "Files only in first set of .debs, found in package $deb1";
	    } else {
		$msg = "Files moved or copied from package $deb1 to package $deb2";
	    }
	    print $msg, "\n", '-' x length $msg, "\n";
	    print join("\n",@{$changes{$deb1}{$deb2}}), "\n\n";
	    $changes = 1;
	}
    }

    if (! $changes) {
	print "File lists identical on package level (after any substitutions)\n";
    }
} else {
    my %files;
    grep $files{$_}--, @D1;
    grep $files{$_}++, @D2;

    my @losses = sort grep $files{$_} < 0, keys %files;
    my @gains = sort grep $files{$_} > 0, keys %files;

    if (@losses == 0 && @gains == 0) {
	print "File lists identical (after any substitutions)\n";
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
    }
}

# We compare the control files (at least the dependency fields)
# if we are examining precisely two .debs.
exit 0 unless defined $singledeb[1] and defined $singledeb[2]
    and $compare_control;

unless (system ("command -v wdiff >/dev/null 2>&1") == 0) {
    warn "Can't compare control files; wdiff package not installed\n";
    exit 0;
}

mktmpdirs();

no strict 'refs';

for my $i (1,2) {
    if (system('dpkg-deb', '-e', "$singledeb[$i]", ${"dir$i"})) {
	my $msg = "dpkg-deb -e $singledeb[$i] failed!";
	system ("rm", "-rf", $dir1, $dir2);
	fatal $msg;
    }
}

use strict 'refs';

print "\n";
my $wdiff = `wdiff -n $wdiff_opt $dir1/control $dir2/control`;
if ($? >> 8 == 0) {
    print "No differences were encountered in the control files\n";
} elsif ($? >> 8 == 1) {
    if ($wdiff_opt) {
	# Don't try messing with control codes
	my $msg = "The following is the wdiff output between the control files:";
	print $msg, "\n", '-' x length $msg, "\n";
	print $wdiff;
    } else {
	my @output;
	@output = split /\n/, $wdiff;
	@output = grep /(\[-|\{\+)/, @output;
	my $msg = "The following lines in the control files differ (wdiff output format):";
	print $msg, "\n", '-' x length $msg, "\n";
	print join("\n",@output), "\n";
    }
} else {
    warn "wdiff failed (exit status " . ($? >> 8) .
	(($? & 0x7f) ? " with signal " . ($? & 0x7f) : "") . ")\n";
}
# Clean up
system ("rm", "-rf", $dir1, $dir2);

###### Subroutines

# This routine takes the output of dpkg-deb -c and returns
# a processed listref
sub process_debc($$)
{
    my ($data,$number) = @_;
    my (@filelist);

    # Format of dpkg-deb -c output:
    # permissions owner/group size date time name ['->' link destination]
    # And remember the slink -> potato stuff
    $data =~ s/^(\S+\s+){5}//mg;
    $data =~ s,^\./,/,mg;
    $data =~ s,^([^/]),/$1,mg;
    @filelist = grep ! m|^/$|, split /\n/, $data; # don't bother keeping '/'

    # Are we keeping directory names in our filelists?
    if ($ignore_dirs) {
	@filelist = grep ! m|/$|, @filelist;
    }

    # Do the "move" substitutions in the order received for the first debs
    if ($number == 1) {
	for my $move (@move) {
	    my $regex = $$move[0];
	    my $from  = $$move[1];
	    my $to    = $$move[2];
	    map { if ($regex) { eval "\$_ =~ s:^$from:$to:"; }
	          else { $_ =~ s/^\Q$from\E/$to/; } } @filelist;
	}
    }

    return \@filelist;
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
