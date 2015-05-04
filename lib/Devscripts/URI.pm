# This module is stolen from debbugs until the real
# URI::query_form properly handles ; and is released
# under the terms of the GPL version 2, or any later
# version at your option.
# See the file README and COPYING for more information.
#
# Copyright 2007 by Don Armstrong <don@donarmstrong.com>.
# query_form is
# Copyright 1995-2003 Gisle Aas.
# Copyright 1995 Martijn Koster.


package Devscripts::URI;

=head1 NAME

Devscripts::URI -- Derivative of URI which overrides the query_param
 method to use ';' instead of '&' for separators.

=head1 SYNOPSIS

use Devscripts::URI;

=head1 DESCRIPTION

See L<URI> for more information.

=head1 BUGS

None known.

=cut

use warnings;
use strict;
use base qw(URI URI::_query);

=head2 query_param

     $uri->query_form( $key1 => $val1, $key2 => $val2, ... )

Exactly like query_param in L<URI> except query elements are joined by
; instead of &.

=cut

{

     package URI::_query;

     no warnings 'redefine';
     # Handle ...?foo=bar&bar=foo type of query
     sub URI::_query::query_form {
	  my $self = shift;
	  my $old = $self->query;
	  if (@_) {
	       # Try to set query string
	       my @new = @_;
	       if (@new == 1) {
		    my $n = $new[0];
		    if (ref($n) eq "ARRAY") {
			 @new = @$n;
		    }
		    elsif (ref($n) eq "HASH") {
			 @new = %$n;
		    }
	       }
	       my @query;
	       while (my($key,$vals) = splice(@new, 0, 2)) {
		    $key = '' unless defined $key;
		    $key =~ s/([;\/?:@&=+,\$\[\]%])/$URI::Escape::escapes{$1}/g;
		    $key =~ s/ /+/g;
		    $vals = [ref($vals) eq "ARRAY" ? @$vals : $vals];
		    for my $val (@$vals) {
			 $val = '' unless defined $val;
			 $val =~ s/([;\/?:@&=+,\$\[\]%])/$URI::Escape::escapes{$1}/g;
			 $val =~ s/ /+/g;
			 push(@query, "$key=$val");
		    }
	       }
	       # We've changed & to a ; here.
	       $self->query(@query ? join(';', @query) : undef);
	  }
	  return if !defined($old) || !length($old) || !defined(wantarray);
	  return unless $old =~ /=/; # not a form
	  map { s/\+/ /g; uri_unescape($_) }
	       # We've also changed the split here to split on ; as well as &
	       map { /=/ ? split(/=/, $_, 2) : ($_ => '')} split(/[&;]/, $old);
     }
}






1;


__END__






