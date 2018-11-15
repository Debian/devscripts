
=head1 NAME

Devscripts::Config - devscripts Perl scripts configuration object

=head1 SYNOPSIS

  # Configuration module
  package Devscripts::My::Config;
  use Moo;
  extends 'Devscripts::Config';
  
  use constant keys => [
    [ 'text1=s', 'MY_TEXT', qr/^\S/, 'Default_text' ],
    # ...
  ];
  
  has text1 => ( is => 'rw' );
  
  # Main package or script
  package Devscripts::My;
  
  use Moo;
  my $config = Devscripts::My::Config->new->parse;
  1;

=head1 DESCRIPTION

Devscripts Perl scripts configuration object. It can scan configuration files
(B</etc/devscripts.conf> and B<~/.devscripts>) and command line arguments.

A devscripts configuration package has just to declare:

=over

=item B<keys> constant: array ref I<(see below)>

=item B<rules> constant: hash ref I<(see below)>

=back

=head1 KEYS

Each element of B<keys> constant is an array containing four elements which can
be undefined:

=over

=item the string to give to L<Getopt::Long>

=item the name of the B<devscripts.conf> key

=item the rule to check value. It can be:

=over

=item B<regexp> ref: will be applied to the value. If it fails against the
devscripts.conf value, Devscripts::Config will warn. If it fails against the
command line argument, Devscripts::Config will die.

=item B<sub> ref: function will be called with 2 arguments: current config
object and proposed value. Function must return a true value to continue or
0 to stop. This is not simply a "check" function: Devscripts::Config will not
do anything else than read the result to continue with next argument or stop.

=item B<"bool"> string: means that value is a boolean. devscripts.conf value
can be either "yes", 1, "no", 0.

=back

=item the default value

=back

=head2 RULES

It is possible to declare some additional rules to check the logic between
options:

  use constant rules => [
    sub {
      my($self)=@_;
      # OK
      return 1 if( $self->a < $self->b );
      # OK with warning
      return ( 1, 'a should be lower than b ) if( $self->a > $self->b );
      # NOK with an error
      return ( 0, 'a must not be equal to b !' );
    },
    sub {
      my($self)=@_;
      # ...
      return 1;
    },
  ];

=head1 METHODS

=head2 new()

Constructor

=cut

package Devscripts::Config;

use strict;
use Devscripts::Output;
use Dpkg::IPC;
use File::HomeDir;
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use Moo;

# Common options
has common_opts => (
    is      => 'ro',
    default => sub {
        [[
                'help', undef,
                sub {
                    if ($_[1]) { $_[0]->usage; exit 0 }
                }
            ]]
    });

# Internal attributes

has modified_conf_msg => (is => 'rw', default => sub { '' });

$ENV{HOME} = File::HomeDir->my_home;

our @config_files
  = ('/etc/devscripts.conf', ($ENV{HOME} ? "$ENV{HOME}/.devscripts" : ()));

sub keys {
    die "conffile_keys() must be defined in sub classes";
}

=head2 parse()

Launches B<parse_conf_files()>, B<parse_command_line()> and B<check_rules>

=cut

sub BUILD {
    my ($self) = @_;
    $self->set_default;
}

sub parse {
    my ($self) = @_;

    # 1 - Parse /etc/devscripts.conf and ~/.devscripts
    $self->parse_conf_files;

    # 2 - Parse command line
    $self->parse_command_line;

    # 3 - Check rules
    $self->check_rules;
    return $self;
}

# I - Parse /etc/devscripts.conf and ~/.devscripts

=head2 parse_conf_files()

Reads values in B</etc/devscripts.conf> and B<~/.devscripts>

=cut

sub set_default {
    my ($self) = @_;
    my $keys = $self->keys;
    foreach my $key (@$keys) {
        my ($kname, $name, $check, $default) = @$key;
        next unless (defined $default);
        $kname =~ s/^\-\-//;
        $kname =~ s/-/_/g;
        $kname =~ s/[!\|=].*$//;
        if (ref $default) {
            unless (ref $default eq 'CODE') {
                die "Default value must be a sub ($kname)";
            }
            $self->{$kname} = $default->();
        } else {
            $self->{$kname} = $default;
        }
    }
}

sub parse_conf_files {
    my ($self) = @_;
    if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
        $self->modified_conf_msg("  (no configuration files read)");
        shift @ARGV;
        return $self;
    }

    @config_files = grep { -r $_ } @config_files;
    my $keys = $self->keys;
    if (@config_files) {
        my @key_names = map { $_->[1] ? $_->[1] : () } @$keys;
        my %config_vars;

        my $shell_cmd
          = 'for file in ' . join(" ", @config_files) . '; do . $file; done;';

        # Read back values
        foreach my $var (@key_names) {
            $shell_cmd .= "echo \$$var;\n";
        }
        my $shell_out;
        spawn(
            exec       => ['/bin/bash', '-c', $shell_cmd],
            wait_child => 1,
            to_string  => \$shell_out
        );
        @config_vars{@key_names} = map { s/^\s*(.*?)\s*/$1/ ? $_ : undef }
          split(/\n/, $shell_out, -1);

        # Check validity and set value
        foreach my $key (@$keys) {
            my ($kname, $name, $check, $default) = @$key;
            next unless ($name);
            $kname //= '';
            $kname =~ s/^\-\-//;
            $kname =~ s/-/_/g;
            $kname =~ s/[!|=+].*$//;
            # Case 1: nothing in conf files, set default
            next unless (length $config_vars{$name});
            if (defined $check) {
                if (not(ref $check)) {
                    $check
                      = $self->_subs_check($check, $kname, $name, $default);
                }
                if (ref $check eq 'CODE') {
                    my ($res, $msg)
                      = $check->($self, $config_vars{$name}, $kname);
                    ds_warn $msg unless ($res);
                    next;
                } elsif (ref $check eq 'Regexp') {
                    unless ($config_vars{$name} =~ $check) {
                        ds_warn("Bad $name value $config_vars{$name}");
                        next;
                    }
                } else {
                    ds_die("Unknown check type for $name");
                    return undef;
                }
            }
            $self->{$kname} = $config_vars{$name};
            $self->{modified_conf_msg} .= "  $name=$config_vars{$name}\n";
            if (ref $default and ref($default->()) eq 'ARRAY') {
                my @tmp = ($config_vars{$name} =~ /\s+"([^"]*)"\s+/g);
                $config_vars{$name} =~ s/\s+"([^"]*)"\s+/ /g;
                push @tmp, split(/\s+/, $config_vars{$name});
                $self->{$kname} = \@tmp;
            }
        }
    }
    return $self;
}

# II - Parse command line

=head2 parse_command_line()

Parse command line arguments

=cut

sub parse_command_line {
    my ($self, @arrays) = @_;
    my $opts = {};
    my $keys = [@{ $self->common_opts }, @{ $self->keys }];
    # If default value is set to [], we must prepare hash ref to be able to
    # receive more than one value
    foreach (@$keys) {
        if ($_->[3] and ref($_->[3])) {
            my $kname = $_->[0];
            $kname =~ s/[!\|=].*$//;
            $opts->{$kname} = $_->[3]->();
        }
    }
    unless (GetOptions($opts, map { $_->[0] ? ($_->[0]) : () } @$keys)) {
        $_[0]->usage;
        exit 1;
    }
    foreach my $key (@$keys) {
        my ($kname, $tmp, $check, $default) = @$key;
        next unless ($kname);
        $kname =~ s/[!|=+].*$//;
        my $name = $kname;
        $kname =~ s/-/_/g;
        if (defined $opts->{$name}) {
            next if (ref $opts->{$name} and !@{ $opts->{$name} });
            if (defined $check) {
                if (not(ref $check)) {
                    $check
                      = $self->_subs_check($check, $kname, $name, $default);
                }
                if (ref $check eq 'CODE') {
                    my ($res, $msg) = $check->($self, $opts->{$name}, $kname);
                    ds_die "Bad value for $name: $msg" unless ($res);
                } elsif (ref $check eq 'Regexp') {
                    if ($opts->{$name} =~ $check) {
                        $self->{$kname} = $opts->{$name};
                    } else {
                        ds_die("Bad $name value in command line");
                    }
                } else {
                    ds_die("Unknown check type for $name");
                }
            } else {
                $self->{$kname} = $opts->{$name};
            }
        }
    }
    return $self;
}

sub check_rules {
    my ($self) = @_;
    if ($self->can('rules')) {
        if (my $rules = $self->rules) {
            my $i = 0;
            foreach my $sub (@$rules) {
                $i++;
                my ($res, $msg) = $sub->($self);
                if ($res) {
                    ds_warn($msg) if ($msg);
                } else {
                    ds_error($msg || "config rule $i");
                    # ds_error may not die if $Devscripts::Output::die_on_error
                    # is set to 0
                    next;
                }
            }
        }
    }
    return $self;
}

sub _subs_check {
    my ($self, $check, $kname, $name, $default) = @_;
    if ($check eq 'bool') {
        $check = sub {
            $_[0]->{$kname} = (
                  $_[1] =~ /^(?:1|yes)$/i ? 1
                : $_[1] =~ /^(?:0|no)$/i  ? 0
                : $default                ? $default
                :                           undef
            );
            return 1;
        };
    } else {
        $self->die("Unknown check type for $name");
    }
    return $check;
}

# Default usage: switch to manpage
sub usage {
    $progname =~ s/\.pl//;
    exec("man", '-P', '/bin/cat', $progname);
}

1;
__END__
=head1 SEE ALSO

L<devscripts>

=head1 AUTHOR

Xavier Guimard E<lt>yadd@debian.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2018 by Xavier Guimard <yadd@debian.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
