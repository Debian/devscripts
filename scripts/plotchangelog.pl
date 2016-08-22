#!/usr/bin/perl
#
# Plot the history of a debian package from the changelog, displaying
# when each release of the package occurred, and who made each release.
# To make the graph a little more interesting, the debian revision of the
# package is used as the y axis.
#
# Pass this program the changelog(s) you wish to be plotted.
#
# Copyright 1999 by Joey Hess <joey@kitenet.net>
# Modifications copyright 2003 by Julian Gilbey <jdg@debian.org>
#
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

use 5.006;
use strict;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempfile /;
use Fcntl;
use Getopt::Long qw(:config gnu_getopt);

BEGIN {
    pop @INC if $INC[-1] eq '.';
    eval { require Date::Parse; import Date::Parse (); };
    if ($@) {
	my $progname = basename($0);
	if ($@ =~ /^Can\'t locate Date\/Parse\.pm/) {
	    die "$progname: you must have the libtimedate-perl package installed\nto use this script\n";
	} else {
	    die "$progname: problem loading the Date::Parse module:\n  $@\nHave you installed the libtimedate-perl package?\n";
	}
    }
}


my $progname = basename($0);
my $modified_conf_msg;

sub usage {
    print <<"EOF";
Usage: plotchangelog [options] changelog ...
	-v	  --no-version	  Do not show package version information.
	-m	  --no-maint	  Do not show package maintainer information.
	-u        --urgency       Use larger points for higher urgency uploads.
	-l        --linecount     Make the Y axis be number of lines in the
	                          changelog.
	-b        --bugcount      Make the Y axis be number of bugs closed
	                          in the changelog.
        -c        --cumulative    With -l or -b, graph the cumulative number
                                  of lines or bugs closed.
	-g "commands"             Pass "commands" on to gnuplot, they will be
	--gnuplot="commands"      added to the gnuplot script that is used to
				  generate the graph.
	-s file   --save=file     Save the graph to the specified file in
	                          postscript format.
	-d        --dump          Dump gnuplot script to stdout.
	          --verbose       Outputs the gnuplot script.
                  --help          Show this message.
                  --version       Display version and copyright information.
                  --noconf        Don\'t read devscripts configuration files

  At most one of -l and -b (or their long equivalents) may be used.

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

my $versioninfo = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999 by Joey Hess <joey\@kitenet.net>.
Modifications copyright 1999-2003 by Julian Gilbey <jdg\@debian.org>
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF

my ($no_version, $no_maintainer, $gnuplot_commands, $dump,
    $save_filename, $verbose, $linecount, $bugcount, $cumulative,
    $help, $showversion, $show_urgency, $noconf)="";

# Handle config file unless --no-conf or --noconf is specified
# The next stuff is boilerplate
my $extra_gnuplot_commands='';
if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'PLOTCHANGELOG_OPTIONS' => '',
		       'PLOTCHANGELOG_GNUPLOT' => '',
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

    if ($config_vars{'PLOTCHANGELOG_OPTIONS'}) {
	unshift @ARGV, split(' ', $config_vars{'PLOTCHANGELOG_OPTIONS'});
    }
    $extra_gnuplot_commands=$config_vars{'PLOTCHANGELOG_GNUPLOT'};
}

GetOptions(
	   "no-version|v", \$no_version,
	   "no-maint|m", \$no_maintainer,
	   "gnuplot|g=s", \$gnuplot_commands,
	   "save|s=s", \$save_filename,
	   "dump|d", \$dump,
	   "urgency|u", \$show_urgency,
	   "verbose", \$verbose,
	   "l|linecount", \$linecount,
	   "b|bugcount", \$bugcount,
	   "c|cumulative", \$cumulative,
	   "help", \$help,
	   "version", \$showversion,
	   "noconf" => \$noconf,
	   "no-conf" => \$noconf,
	   )
    or die "Usage: $progname [options] changelog ...\nRun $progname --help for more details\n";

if ($noconf) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}

if ($help) {
    usage();
    exit 0;
}

if ($showversion) {
    print $versioninfo;
    exit 0;
}

if ($bugcount && $linecount) {
    die "$progname: can't use --bugcount and --linecount\nRun $progname --help for usage information.\n";
}

if ($cumulative && ! $bugcount && ! $linecount) {
    warn "$progname: --cumulative without --bugcount or --linecount: ignoring\nRun $progname --help for usage information.\n";
}

if (! @ARGV) {
    die "Usage: $progname [options] changelog ...\nRun $progname --help for more details\n";
}

my %data;
my ($package, $version, $maintainer, $date, $urgency)=undef;
my ($data_tmpfile, $script_tmpfile);
my ($data_fh, $script_fh);

if (! $dump) {
    $data_fh = tempfile("plotdataXXXXXX", UNLINK => 1)
	or die "cannot create temporary file: $!";
    fcntl $data_fh, Fcntl::F_SETFD(), 0
	or die "disabling close-on-exec for temporary file: $!";
    $script_fh = tempfile("plotscriptXXXXXX", UNLINK => 1)
	or die "cannot create temporary file: $!";
    fcntl $script_fh, Fcntl::F_SETFD(), 0
	or die "disabling close-on-exec for temporary file: $!";
    $data_tmpfile='/dev/fd/'.fileno($data_fh);
    $script_tmpfile='/dev/fd/'.fileno($script_fh);
}
else {
    $data_tmpfile='-';
}
my %pkgcount;
my $c;

# Changelog parsing.
foreach (@ARGV) {
    if (/\.gz$/) {
	open F,"zcat $_|" || die "$_: $!";
    }
    else {
	open F,$_ || die "$_: $!";
    }

    while (<F>) {
	chomp;
	# Note that some really old changelogs use priority, not urgency.
	if (/^(\w+.*?)\s+\((.*?)\)\s+.*?;\s+(?:urgency|priority)=(.*)/i) {
	    $package=lc($1);
	    $version=$2;
	    if ($show_urgency) {
		$urgency=$3;
		if ($urgency=~/high/i) {
		    $urgency=2;
		}
		elsif ($urgency=~/medium/i) {
		    $urgency=1.5;
		}
		else {
		    $urgency=1;
		}
	    }
	    else {
		$urgency=1;
	    }
	    undef $maintainer;
	    undef $date;
	    $c=0;
	}
	elsif (/^ -- (.*?)  (.*)/) {
	    $maintainer=$1;
	    $date=str2time($2);

	    # Strip email address.
	    $maintainer=~s/<.*>//;
	    $maintainer=~s/\(.*\)//;
	    $maintainer=~s/\s+$//;
	}
	elsif (/^(\w+.*?)\s+\((.*?)\)\s+/) {
	    print STDERR qq[Parse error on "$_"\n];
	}
	elsif ($linecount && /^  /) {
	    $c++; # count changelog size.
	}
	elsif ($bugcount && /^  /) {
	    # count bugs that were said to be closed.
	    my @bugs=m/#\d+/g;
	    $c+=$#bugs+1;
	}

	if (defined $package && defined $version &&
	    defined $maintainer && defined $date && defined $urgency) {
	    $data{$package}{$pkgcount{$package}++}=
		[$linecount || $bugcount ? $c : $version,
		 $maintainer, $date, $urgency];
	    undef $package;
	    undef $version;
	    undef $maintainer;
	    undef $date;
	    undef $urgency;
	}
    }

    close F;
}

if ($cumulative) {
    # have to massage the data; based on some code from later on
    foreach $package (keys %data) {
	my $total = 0;
	# It's crucial the output is sorted by date.
	foreach my $i (sort {$data{$package}{$a}[2] <=> $data{$package}{$b}[2]}
		       keys %{$data{$package}}) {
	    $total += $data{$package}{$i}[0];
	    $data{$package}{$i}[0] = $total;
	}
    }
}

my $header=q{
set key below title "key" box
set timefmt "%m/%d/%Y %H:%M"
set xdata time
set format x "%m/%y"
set yrange [0 to *]
};
if ($linecount) {
    if ($cumulative) { $header.="set ylabel 'Cumulative changelog length'\n"; }
    else { $header.="set ylabel 'Changelog length'\n"; }
}
elsif ($bugcount) {
    if ($cumulative) { $header.="set ylabel 'Cumulative bugs closed'\n"; }
    else { $header.="set ylabel 'Bugs closed'\n"; }
}
else {
    $header.="set ylabel 'Debian version'\n";
}
if ($save_filename) {
    $header.="set terminal postscript color solid\n";
    $header.="set output '$save_filename'\n";
}
my $script="plot ";
my $data='';
my $index=0;
my %maintdata;

# Note that "lines" is used if we are also showing maintainer info,
# otherwise we use "linespoints" to make sure points show up for each
# release anyway.
my $style = $no_maintainer ? "linespoints" : "lines";

foreach $package (keys %data) {
    my $oldmaintainer="";
    my $oldversion="";
    # It's crucial the output is sorted by date.
    foreach my $i (sort {$data{$package}{$a}[2] <=> $data{$package}{$b}[2]}
		   keys %{$data{$package}}) {
	my $v=$data{$package}{$i}[0];
	$maintainer=$data{$package}{$i}[1];
	$date=$data{$package}{$i}[2];
	$urgency=$data{$package}{$i}[3];

	$maintainer=~s/"/\\"/g;

	my $y;

	# If it's got a debian revision, use that as the y coordinate.
	if ($v=~m/(.*)-(.*)/) {
	    $y=$2;
	    $version=$1;
	}
	else {
	    $y=$v;
	}

	# Now make sure the version is a real number. This includes making
	# sure it has no more than one decimal point in it, and getting rid of
	# any nonnumeric stuff. Otherwise, the "set label" command below could
	# fail. Luckily, perl's string -> num conversion is perfect for this job.
	$y=$y+0;

	if (lc($maintainer) ne lc($oldmaintainer)) {
	    $oldmaintainer=$maintainer;
	}

	my ($sec, $min, $hour, $mday, $mon, $year)=localtime($date);
	my $x=($mon+1)."/$mday/".(1900+$year)." $hour:$min";
	$data.="$x\t$y\n";
	$maintdata{$oldmaintainer}{$urgency}.="$x\t$y\n";

	if ($oldversion ne $version && ! $no_version) {
	    # Upstream version change. Label it.
	    $header.="set label '$version' at '$x',$y left\n";
	    $oldversion=$version;
	}
    }
    $data.="\n\n"; # start new dataset
    # Add to plot command.
    $script.="'$data_tmpfile' index $index using 1:3 title '$package' with $style, ";
    $index++;
}

# Add a title.
my $title.="set title '";
$title.=$#ARGV > 1 ? "Graphing Debian changelogs" :
    "Graphing Debian changelog";
$title.="'\n";

if (! $no_maintainer) {
    foreach $maintainer (sort keys %maintdata) {
	foreach $urgency (sort keys %{$maintdata{$maintainer}}) {
	    $data.=$maintdata{$maintainer}{$urgency}."\n\n";
	    $script.="'$data_tmpfile' index $index using 1:3 title \"$maintainer\" with points pointsize ".(1.5 * $urgency).", ";
	    $index++;
	}
    }
}

$script=~s/, $/\n/;
$script=qq{
$header
$title
$extra_gnuplot_commands
$gnuplot_commands
$script
};
$script.="pause -1 'Press Return to continue.'\n"
    unless $save_filename || $dump;

if (! $dump) {
    # Annoyingly, we have to use 2 temp files. I could just send everything to
    # gnuplot on stdin, but then the pause -1 doesn't work.
    open (DATA, ">$data_tmpfile") || die "$data_tmpfile: $!";
    open (SCRIPT, ">$script_tmpfile") || die "$script_tmpfile: $!";
}
else {
    open (DATA, ">&STDOUT");
    open (SCRIPT, ">&STDOUT");
}

print SCRIPT $script;
print $script if $verbose && ! $dump;
print DATA $data;
close SCRIPT;
close DATA;

if (! $dump) {
    unless (system("gnuplot",$script_tmpfile) == 0) {
	die "gnuplot program failed (is the gnuplot package installed?): $!\n";
    }
}
