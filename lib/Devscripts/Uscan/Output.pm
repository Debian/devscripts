package Devscripts::Uscan::Output;

use strict;
use Devscripts::Output;
use Exporter 'import';
use File::Basename;

our @EXPORT = (
    @Devscripts::Output::EXPORT, qw(
      uscan_msg uscan_verbose dehs_verbose uscan_warn uscan_debug
      uscan_extra_debug uscan_die dehs_output $dehs $verbose $dehs_tags
      $dehs_start_output $dehs_end_output $found
      ));

# ACCESSORS
our ($dehs, $dehs_tags, $dehs_start_output, $dehs_end_output, $found)
  = (0, {}, 0, 0);

our $progname = basename($0);

sub printwarn {
    my ($msg, $w) = @_;
    chomp $msg;
    if ($w or $dehs) {
        print STDERR "$msg\n";
    } else {
        print "$msg\n";
    }
}

*uscan_msg = \&ds_msg;

*uscan_verbose = \&ds_verbose;

*uscan_extra_debug = \&ds_extra_debug;

sub dehs_verbose ($) {
    my $msg = $_[0];
    push @{ $dehs_tags->{'messages'} }, "$msg\n";
    uscan_verbose($msg);
}

sub uscan_warn ($) {
    my $msg = $_[0];
    push @{ $dehs_tags->{'warnings'} }, $msg if $dehs;
    printwarn("$progname warn: $msg" . &Devscripts::Output::who_called, 1);
}

*uscan_debug = \&ds_debug;

sub uscan_die ($) {
    my $msg = $_[0];
    if ($dehs) {
        $dehs_tags       = { 'errors' => "$msg" };
        $dehs_end_output = 1;
        dehs_output();
    }
    $msg = "$progname die: $msg" . &Devscripts::Output::who_called;
    if ($Devscripts::Output::die_on_error) {
        die $msg;
    }
    printwarn($msg, 1);
}

sub dehs_output () {
    return unless $dehs;

    if (!$dehs_start_output) {
        print "<dehs>\n";
        $dehs_start_output = 1;
    }

    for my $tag (
        qw(package debian-uversion debian-mangled-uversion
        upstream-version upstream-url decoded-checksum
        status target target-path messages warnings errors)
    ) {
        if (exists $dehs_tags->{$tag}) {
            if (ref $dehs_tags->{$tag} eq "ARRAY") {
                foreach my $entry (@{ $dehs_tags->{$tag} }) {
                    $entry =~ s/</&lt;/g;
                    $entry =~ s/>/&gt;/g;
                    $entry =~ s/&/&amp;/g;
                    print "<$tag>$entry</$tag>\n";
                }
            } else {
                $dehs_tags->{$tag} =~ s/</&lt;/g;
                $dehs_tags->{$tag} =~ s/>/&gt;/g;
                $dehs_tags->{$tag} =~ s/&/&amp;/g;
                print "<$tag>$dehs_tags->{$tag}</$tag>\n";
            }
        }
    }
    foreach my $cmp (@{ $dehs_tags->{'component-name'} }) {
        print qq'<component id="$cmp">\n';
        foreach my $tag (
            qw(debian-uversion debian-mangled-uversion
            upstream-version upstream-url target target-path)
        ) {
            my $v = shift @{ $dehs_tags->{"component-$tag"} };
            print "  <component-$tag>$v</component-$tag>\n" if $v;
        }
        print "</component>\n";
    }
    if ($dehs_end_output) {
        print "</dehs>\n";
    }

    # Don't repeat output
    $dehs_tags = {};
}
1;
