#!/usr/bin/perl

use strict;
use warnings;

# Define item leadin/leadout for man output
my $ITEM_LEADIN  = '.IP "\fI';
my $ITEM_LEADOUT = '\fR(1)"';

my $package;
my $description;


# Parse the shortened README file
while (<>) {
    chomp;
    # A line starting with '  -' indicates a script
    if (/^ - ([^:]*): (.*)/) {
        if ($package and $description) {
            # If we get here, then we need to output the man code
            print $ITEM_LEADIN . $package . $ITEM_LEADOUT . "\n";
            print $description . "\n";
        }
        $package     = $1;
        $description = $2;
    } else {
        s/^  //;
        $description .= $_;
    }
}
