#!/usr/bin/perl

=head1 NAME

namecheck - Check project names are not already taken.

=head1 ABOUT

This is a simple tool to automate the testing of project names at the most
common Open Source / Free Software hosting environments.

Each new project requires a name, and those names are ideally unique.  To come
up with names is hard, and testing to ensure they're not already in use is
time-consuming - unless you have a tool such as this one.

=head1 CUSTOMIZATION

The script, as is, contains a list of sites, and patterns, to test against.

If those patterns aren't sufficient then you may create your own additions and
add them to the script.  If you wish to have your own version of the patterns
you may save them into the file ~/.namecheckrc

=head1 AUTHOR

Steve
--
http://www.steve.org.uk/

=head1 LICENSE

Copyright (c) 2008 by Steve Kemp.  All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut



#
#  Good practise.
#
use strict;
use warnings;


#
#  A module for fetching webpages.
#
use LWP::UserAgent;



#
#  Get the name from the command line.
#
my $name = shift;
if ( !defined($name) )
{
    print <<EOF;
Usage: $0 name
EOF
    exit;
}



#
#  Get the patterns we're going to use for testing.
#
my @lines = loadPatterns();


#
#  Assuming we have patterns use them.
#
testSites(@lines);


#
#  NOT REACHED.
#
exit;



#
#  Load the list of sites, and patterns, to test.
#
#  By default these will come from the end of the script
# itself.  A user may create the file ~/.namecheckrc with
# their own patterns if they prefer.
#

sub loadPatterns
{
    my $file  = $ENV{ 'HOME' } . "/.namecheckrc";
    my @lines = ();

    if ( -e $file )
    {
        open( FILE, "<", $file )
          or die "Failed to open $file - $!";
        while (<FILE>)
        {
            push( @lines, $_ );
        }
        close(FILE);
    }
    else
    {
        while (<DATA>)
        {
            push( @lines, $_ );
        }
    }

    return (@lines);
}

#
#  Test the given name against the patterns we've loaded from our
# own script, or the users configuration file.
#

sub testSites
{
    my (@patterns) = (@_);

    #
    # Create and setup an agent for the downloading.
    #
    my $ua = LWP::UserAgent->new();
    $ua->agent('Mozilla/5.0');
    $ua->timeout(10);
    $ua->env_proxy();

    my $headers = HTTP::Headers->new();
    $headers->header('Accept' => '*/*');

    foreach my $entry (@patterns)
    {

        #
        #  Skip blank lines, and comments.
        #
        chomp($entry);
        next if ( ( !$entry ) || ( !length($entry) ) );
        next if ( $entry =~ /^#/ );


        #
        #  Each line is an URL + a pattern, separated by a pipe.
        #
        my ( $url, $pattern ) = split( /\|/, $entry );

        #
        #  Strip leading/trailing spaces.
        #
        $pattern =~ s/^\s+//;
        $pattern =~ s/\s+$//;


        #
        #  Interpolate the proposed project name in the string.
        #
        $url =~ s/\%s/$name/g if ( $url =~ /\%s/ );

        #
        #  Find the hostname we're downloading; just to show the user
        # something is happening.
        #
        my $urlname = $url;
        if ( $urlname =~ /:\/\/([^\/]+)\// )
        {
            $urlname = $1;
        }
        print sprintf "Testing %20s", $urlname;


        #
        #  Get the URL
        #
        my $request = HTTP::Request->new('GET', $url, $headers);
        my $response = $ua->request($request);

        #
        #  If success we look at the returned text.
        #
        if ( $response->is_success() )
        {

            #
            #  Get the page content - collapsing linefeeds.
            #
            my $c = $response->content();
            $c =~ s/[\r\n]//g;

            #
            #  Does the page have the pattern?
            #
            if ( $c !~ /\Q$pattern\E/i )
            {
                print " - In use\n";
                print "Aborting - name '$name' is currently used.\n";
                exit 0;
            }
            else
            {
                print " - Available\n";
            }
        }
        else
        {

            #
            #  Otherwise we'll assume that 404 means that the
            # project isn't taken.
            #
            my $c = $response->status_line();
            if ( $c =~ /404/ )
            {
                print " - Available\n";
            }
            else
            {

                #
                #  Other errors we can't handle.
                #
                print "ERROR fetching $url - $c\n";
            }
        }

    }


    #
    #  If we got here the name is free.
    #
    print "\n\nThe name '$name' doesn't appear to be in use.\n";
    exit 1;
}


__DATA__

#
#  The default patterns.
#
#  If you want to customise them either do so here, or create the
# file ~/.namecheckrc with your own contents in the same format.
#
http://%s.tuxfamily.org/             | Not Found
http://alioth.debian.org/projects/%s | Software Map
http://freshmeat.net/projects/%s     | We encounted an error
http://launchpad.net/%s              | no page with this address
http://savannah.gnu.org/projects/%s  | Invalid Group
http://sourceforge.net/projects/%s   | Invalid Project
http://www.ohloh.net/projects/%s     | Sorry, the page you are trying to view is not here
https://gna.org/projects/%s          | Invalid Group
http://code.google.com/p/%s          | Not Found
http://projects.apache.org/projects/%s.html | Not Found
