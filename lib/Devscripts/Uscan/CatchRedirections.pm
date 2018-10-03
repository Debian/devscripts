# dummy subclass used to store all the redirections for later use
package Devscripts::Uscan::CatchRedirections;

use base 'LWP::UserAgent';

my @uscan_redirections;

sub redirect_ok {
    my $self = shift;
    my ($request) = @_;
    if ($self->SUPER::redirect_ok(@_)) {
        push @uscan_redirections, $request->uri;
        return 1;
    }
    return 0;
}

sub get_redirections {
    return \@uscan_redirections;
}

sub clear_redirections {
    undef @uscan_redirections;
    return;
}

1;
