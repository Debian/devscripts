#!/usr/bin/perl

use strict;
use warnings;

# Define item leadin/leadout for man output
my $ITEM_LEADIN = '.IP "\fI';
my $ITEM_LEADOUT = '\fR(1)"';

# Open control file
open(CONTROL, "< ../debian/control") or die "unable to open control: $!";

my $package;
my $description;

# Parse the control file
while(<CONTROL>) {
    chomp;
    # A line starting with '  -' indicates a script
    if (/^  - ([^:]*): (.*)/) {
	if ($package and $description) {
	    # If we get here, then we need to output the man code
	    print $ITEM_LEADIN . $package . $ITEM_LEADOUT . "\n";
	    print $description . "\n";
	}
	$package = $1;
	$description = $2
    }
    # Handle the last description
    elsif (/^ \./ and $package and $description) {
        print $ITEM_LEADIN . $package . $ITEM_LEADOUT . "\n";
        print $description . "\n";
    }
    else {
	s/^.{3}//;
	$description .= $_;
    }
}
