#! /usr/bin/perl -w

# desktop2menu: This program generates a skeleton menu file from a
# freedesktop.org desktop file
# 
# Written by Sune Vuorela <debian@pusling.com>
# Modifications by Adam D. Barratt <adam@adam-barratt.org.uk>
# Copyright 2007 Sune Vuorela <debian@pusling.com>
# Modifications Copyright 2007 Adam D. Barratt <adam@adam-barratt.org.uk>
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=head1 NAME

desktop2menu - create a menu file skeleton from a desktop file

=head1 SYNOPSIS

B<desktop2menu> B<--help|--version>

B<desktop2menu> I<desktop file> [I<package name>]

=head1 DESCRIPTION

B<desktop2menu> generates a skeleton menu file from the supplied 
freedesktop.org desktop file.

The package name to be used in the menu file may be passed as an additional 
argument. If it is not supplied then B<desktop2menu> will attempt to derive 
the package name from the data in the desktop file.

=head1 LICENSE

This program is Copyright (C) 2007 by Sune Vuorela <debian@pusling.com>. It 
was modified by Adam D. Barratt <adam@adam-barratt.org.uk> for the devscripts 
package.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License, version 2 or later.

=head1 AUTHOR

Sune Vuorela <debian@pusling.com> with modifications by Adam D. Barratt 
<adam@adam-barratt.org.uk>

=cut

use warnings;
use strict;
use Getopt::Long;
use File::Basename;

my $progname = basename($0);

BEGIN {
    # Load the File::DesktopEntry module safely
    eval { require File::DesktopEntry; };
    if ($@) {
	my $progname = basename $0;
	if ($@ =~ /^Can\'t locate File\/DesktopEntry\.pm/) {
	    die "$progname: you must have the libfile-desktopentry-perl package installed\nto use this script\n";
	}
	die "$progname: problem loading the File::DesktopEntry module:\n  $@\nHave you installed the libfile-desktopentry-perl package?\n";
    }
    import File::DesktopEntry;
}

use File::DesktopEntry;

# Big generic mapping between fdo sections and menu sections
my %mappings = (
    "AudioVideo" => "Applications/Video",
    "Audio" => "Applications/Sound",
    "Video" => "Applications/Video",
    "Development" => "Applications/Programming",
    "Education" => "Applications/Education",
    "Game" => "Games!WARN",
    "Graphics" => "Applications/Graphics!WARN",
    "Network" => "Applications/Network!WARN",
    "Office" => "Applications/Office",
    "System" => "Applications/System/Administration",
    "Utility" => "Applications!WARN",
    "Building" => "Applications/Programming",
    "Debugger" => "Applications/Programming",
    "IDE" => "Applications/Programming",
    "Profiling" => "Applications/Programming",
    "RevisionControl" => "Applications/Programming",
    "Translation" => "Applications/Programming",
    "Calendar" => "Applications/Data Management",
    "ContactManagement" => "Applications/Data Management",
    "Database" => "Applications/Data Management",
    "Dictionary" => "Applications/Text",
    "Chart" => "Applications/Office",
    "Email" => "Applications/Network/Communication",
    "Finance" => "Applications/Office",
    "FlowChart" => "Applications/Office",
    "PDA" => "Applications/Mobile Devices",
    "ProjectManagement" => "Applications/Project Management",
    "Presentation" => "Applications/Office",
    "Spreadsheet" => "Applications/Office",
    "Wordprocessor" => "Applications/Office",
    "2DGraphics" => "Applications/Graphics",
    "VectorGraphics" => "Applications/Graphics",
    "RasterGraphics" => "Applications/Graphics",
    "3DGraphics" => "Applications/Graphics",
    "Scanning" => "Applications/Graphics",
    "OCR" => "Applications/Text",
    "Photography" => "Applications/Graphics",
    "Publishing" => "Applications/Office",
    "Viewer" => "Applications/Viewers",
    "TextTools" => "Applications/Text",
    "DesktopSettings" => "Applications/System/Administration",
    "HardwareSettings" => "Applications/System/Hardware",
    "Printing" => "Applications/System/Administration",
    "PackageManager" => "Applications/System/Package Management",
    "Dialup" => "Applications/System/Administration",
    "InstantMesasging" => "Applications/Network/Communication",
    "Chat" => "Applications/Network/Communication",
    "IRCClient" => "Applications/Nework/Communication",
    "FileTransfer" => "Applications/Network/File Transfer",
    "HamRadio" => "Applications/Amateur Radio",
    "News" => "Applicatiosn/Network/Web News",
    "P2P" => "Applications/File Transfer",
    "RemoteAccess" => "Applications/System/Administration",
    "Telephony" => "Applications/Network/Communication",
    "TelephonyTools" => "Applications/Network/Communication",
    "VideoConference" => "Applications/Network/Communication",
    "Midi" => "Applications/Sound",
    "Mixer" => "Applications/Sound",
    "Sequencer" => "Applications/Sound",
    "Tuner" => "Applications/TV and Radio",
    "TV" => "Applications/TV and Radio",
    "AudioVideoEditing" => "Applications/Video!WARN",
    "Player" => "Applications/Video!WARN",
    "Recorder" => "Applications/Video!WARN",
    "DiscBurning" => "Applications/File Management",
    "ActionGame" => "Games/Action",
    "AdventureGame" => "Games/Adventure",
    "ArcadeGame" => "Games/Action",
    "BoardGame" => "Games/Board",
    "BlocksGame" => "Games/Blocks",
    "CardGame" => "Games/Card",
    "KidsGames" => "Games/Toys!WARN",
    "LogicGames" => "Games/Puzzles",
    "RolePlaying" => "Games/Adventure",
    "Simulation" => "Games/Simulation",
    "SportsGame" => "Games/Action",
    "StrategyGame" => "Games/Strategy",
    "Art" => "Applications/Education",
    "Construction" => "Applications/Education",
    "Music" => "Applications/Education",
    "Languages" => "Applications/Education",
    "Science" => "Applications/Science!WARN",
    "ArtificialIntelligence" => "Applications/Science!WARN",
    "Astronomy" => "Applications/Science/Astronomy",
    "Biology" => "Applications/Science/Biology",
    "Chemistry" => "Applications/Science/Chemistry",
    "ComputerScience" => "Applications/Science/Electronics!WARN",
    "DataVisualization" => "Applications/Science/Data Analysis",
    "Economy" => "Applications/Office",
    "Electricity" => "Applications/Science/Engineering",
    "Geography" => "Applications/Science/Geoscience",
    "Geology" => "Applications/Science/Geoscience",
    "Geoscience" => "Applications/Science/Geoscience",
    "History" => "Applications/Science/Social",
    "ImageProcessing" => "Applications/Graphics",
    "Literature" => "Applications/Data Management",
    "Math" => "Applications/Science/Mathematics",
    "NumericalAnalyzisis" => "Applications/Science/Mathematics",
    "MedicalSoftware" => "Applications/Science/Medicine",
    "Physics" => "Applications/Science/Physics",
    "Robotics" => "Applications/Science/Engineering",
    "Sports" => "Games/Tools!WARN",
    "ParallelComputing" => "Applications/Science/Electronics!WARN",
    "Amusement" => "Games/Toys",
    "Archiving" => "Applications/File Management",
    "Compression" => "Applications/File Management",
    "Electronics" => "Applications/Science/Electronics",
    "Emulator" => "Applications/Emulators",
    "Engineering" => "Applications/Science/Engineering",
    "FileTools" => "Applications/File Management",
    "FileManager" => "Applications/File Management",
    "TerminalEmulator" => "Applications/Shells",
    "Filesystem" => "Applications/System/Administration",
    "Monitor" => "Applications/System/Monitoring",
    "Security" => "Applications/System/Security",
    "Accessibility" => "Applications/Accessibility",
    "Calculator" => "Applications/Science/Mathematics",
    "Clock" => "Games/Toys",
    "TextEditor" => "Applications/Editors",
);

#values mentioned in Categories we accept as valid hints.
my %hintscategories = (
    "KDE" => "true",
    "Qt" => "true",
    "GNOME" => "true",
    "GTK" => "true",
);

my ($opt_help, $opt_version);

GetOptions("help|h" => \$opt_help,
	   "version" => \$opt_version,
	  )
    or die "Usage: $progname desktopfile packagename\nRun $progname --help for more details\n";

if ($opt_help) { help(); exit 0; }
if ($opt_version) { version(); exit 0; }

if (@ARGV == 0) {
    help();
    exit 0;
}

my $section;
my @hints;
my $needs;
my $warnings = 0;

my $filename = shift @ARGV;
my $file = File::DesktopEntry->new_from_file("$filename") ;

# do menu files for non-applications make sense?
die $file->get_value('Name') . " isn't an application\n"
    unless $file->get_value('Type') eq 'Application';

my $package = join(' ', @ARGV);
if (!$package) {
    # Bad guess, but... maybe icon name could be better?
    $package = $file->get_value('Name');
    print STDERR "WARNING: Package not specified. Guessing package as: $package\n";
    $warnings++;
}

my $category = $file->get_value('Categories');

my @categories = reverse split(";", $category);
foreach (@categories ) {
    if ($mappings{$_} && ! $section) {
	$section = $mappings{$_};
    }
    if ($hintscategories{$_}) {
	push(@hints,$_);
    }	
}

die "Desktop file has invalid categories" unless $section;

# Not all mappings are completely accurate. Most are, but...
if ($section =~ /!WARN/) {
    print STDERR "WARNING: Section is highly inaccurate. Please check it manually\n";
    $warnings++;
}

# Let's just pretend that the wm and the vc needs don't exist. 
if ($category =~ /ConsoleOnly/) {
    $needs = "text";
} else {
    $needs = "X11";
}

print "\n" if $warnings > 0;
print "?package(" . $package . "): \\\n";
print "\tneeds=\"" . $needs . "\" \\\n";
print "\tsection=\"" . $section . "\" \\\n";
print "\ttitle=\"" . $file->get_value('Name') . "\" \\\n";
print "\thints=\"" . join(",", @hints) . "\" \\\n" if @hints;
print "\tcommand=\"" . $file->get_value('Exec') . "\" \\\n";
print "\ticon=\"/usr/share/pixmaps/" . $file->get_value('Icon') . ".xpm\" \\\n";
print "\n";

# Unnecessary. but for clarity
exit 0;

sub help {
    print <<"EOF";
Usage: $progname [options] filename packagename

Valid options are:
   --help, -h             Display this message
   --version, -v          Display version and copyright info
EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
Copyright (C) 2007 by Sune Vuorela <debian\@pusling.com>.
Modifications copyright (C) 2007 by Adam D. Barratt <adam\@adam-barratt.org.uk>

This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2, or (at your option) any
later version.
EOF
}
