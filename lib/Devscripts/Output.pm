package Devscripts::Output;

use strict;
use Exporter 'import';
use File::Basename;
use constant accept => qr/^y(?:es)?\s*$/i;
use constant refuse => qr/^n(?:o)?\s*$/i;

our @EXPORT = (
    qw(ds_debug ds_verbose ds_warn ds_error
      ds_die ds_msg who_called $progname $verbose
      ds_prompt accept refuse $ds_yes)
);

# ACCESSORS
our ($verbose, $die_on_error, $ds_yes) = (0, 1, 0);

our $progname = basename($0);

sub printwarn {
    my ($msg, $w) = @_;
    chomp $msg;
    if ($w) {
        print STDERR "$msg\n";
    } else {
        print "$msg\n";
    }
}

sub ds_msg($) {
    my $msg = $_[0];
    printwarn "$progname: $msg";
}

sub ds_verbose($) {
    my $msg = $_[0];
    if ($verbose > 0) {
        printwarn "$progname info: $msg";
    }
}

sub who_called {
    return '' unless ($verbose > 1);
    my @out = caller(1);
    return " [$out[0]: $out[2]]";
}

sub ds_warn ($) {
    my $msg = $_[0];
    printwarn("$progname warn: $msg" . who_called, 1);
}

sub ds_debug($) {
    my $msg = $_[0];
    printwarn "$progname debug: $msg" if $verbose > 1;
}

*ds_die = \&ds_error;

sub ds_error($) {
    my $msg = $_[0];
    $msg = "$progname error $msg" . who_called;
    if ($die_on_error) {
        print STDERR "$msg\n";
        exit 1;
    }
    printwarn($msg, 1);
}

sub ds_prompt {
    return 'yes' if ($ds_yes > 0);
    print STDERR shift;
    my $s = <STDIN>;
    chomp $s;
    return $s;
}

1;
