package Devscripts::Uscan::Output;

use strict;
use Exporter 'import';
use File::Basename;

our @EXPORT = (
    qw(
      uscan_msg uscan_verbose dehs_verbose uscan_warn uscan_debug uscan_die
      dehs_output $dehs $verbose $dehs_tags $dehs_start_output $dehs_end_output
      $progname
      )
);

# ACCESSORS
our ( $dehs, $dehs_tags, $dehs_start_output, $dehs_end_output, $verbose ) =
  ( 0, {}, 0, 0 );

our $progname = basename($0);

sub printwarn ($) {
    my $msg = $_[0];
    if ($dehs) {
        warn $msg;
    }
    else {
        print $msg;
    }
}

sub uscan_msg($) {
    my $msg = $_[0];
    printwarn "$progname: $msg";
}

sub uscan_verbose($) {
    my $msg = $_[0];
    if ( $verbose > 0 ) {
        printwarn "$progname info: $msg";
    }
}

sub dehs_verbose ($) {
    my $msg = $_[0];
    push @{ $dehs_tags->{'messages'} }, $msg;
    uscan_verbose($msg);
}

sub uscan_warn ($) {
    my $msg = $_[0];
    push @{ $dehs_tags->{'warnings'} }, $msg if $dehs;
    warn "$progname warn: $msg";
}

sub uscan_debug($) {
    my $msg = $_[0];
    warn "$progname debug: $msg" if $verbose > 1;
}

sub uscan_die ($) {
    my $msg = $_[0];
    if ($dehs) {
        $dehs_tags = { 'errors' => "$msg" };
        $dehs_end_output = 1;
        dehs_output();
    }
    die "$progname die: $msg";
}

sub dehs_output () {
    return unless $dehs;

    if ( !$dehs_start_output ) {
        print "<dehs>\n";
        $dehs_start_output = 1;
    }

    for my $tag (
        qw(package debian-uversion debian-mangled-uversion
        upstream-version upstream-url
        status target target-path messages warnings errors)
      )
    {
        if ( exists $dehs_tags->{$tag} ) {
            if ( ref $dehs_tags->{$tag} eq "ARRAY" ) {
                foreach my $entry ( @{ $dehs_tags->{$tag} } ) {
                    $entry =~ s/</&lt;/g;
                    $entry =~ s/>/&gt;/g;
                    $entry =~ s/&/&amp;/g;
                    print "<$tag>$entry</$tag>\n";
                }
            }
            else {
                $dehs_tags->{$tag} =~ s/</&lt;/g;
                $dehs_tags->{$tag} =~ s/>/&gt;/g;
                $dehs_tags->{$tag} =~ s/&/&amp;/g;
                print "<$tag>$dehs_tags->{$tag}</$tag>\n";
            }
        }
    }
    if ($dehs_end_output) {
        print "</dehs>\n";
    }

    # Don't repeat output
    $dehs_tags = {};
}
1;
