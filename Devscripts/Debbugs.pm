package Devscripts::Debbugs;

=head1 OPTIONS

=item select [key:value  ...]

Uses the SOAP interface to output a list of bugs which match the given
selection requirements.

The following keys are allowed, and may be given multiple times.

=over 8

=item package

Binary package name.

=item source

Source package name.

=item maintainer

E-mail address of the maintainer.

=item submitter

E-mail address of the submitter.

=item severity

Bug severity.

=item status

Status of the bug.

=item tag

Tags applied to the bug. If I<users> is specified, may include
usertags in addition to the standard tags.

=item owner

Bug's owner.

=item bugs

List of bugs to search within.

=item users

Users to use when looking up usertags.

=item archive

Whether to search archived bugs or normal bugs; defaults to 0
(i.e. only search normal bugs). As a special case, if archive is
'both', both archived and unarchived bugs are returned.

=back

For example, to select the set of bugs submitted by
jrandomdeveloper@example.com and tagged wontfix, one would use

select("submitter:jrandomdeveloper@example.com", "tag:wontfix")

=cut

my $soapurl='Debbugs/SOAP/1';
my $soapproxyurl='http://bugs.debian.org/cgi-bin/soap.cgi';

my $soap_broken;
sub have_soap {
     return ($soap_broken ? 0 : 1) if defined $soap_broken;
     eval {
          require SOAP::Lite;
     };

     if ($@) {
          if ($@ =~ m%^Can't locate SOAP/%) {
               $soap_broken="the libsoap-lite-perl package is not installed";
          } else {
               $soap_broken="couldn't load SOAP::Lite: $@";
          }
     }
     else {
          $soap_broken = 0;
     }
     return ($soap_broken ? 0 : 1);
}

sub select {
     die "Couldn't run select: $soap_broken\n" unless have_soap();
     my @args = @_;
     my %valid_keys = (package => 'package',
                       pkg     => 'package',
                       src     => 'src',
                       source  => 'src',
                       maint   => 'maint',
                       maintainer => 'maint',
                       submitter => 'submitter',
		       from => 'submitter',
                       status    => 'status',
                       tag       => 'tag',
                       owner     => 'owner',
                       dist      => 'dist',
                       distribution => 'dist',
                       bugs       => 'bugs',
                       archive    => 'archive',
                      );
     my %users;
     my %search_parameters;
     my $soap = SOAP::Lite->uri($soapurl)->proxy($soapproxyurl);
     for my $arg (@args) {
          my ($key,$value) = split /:/, $arg, 2;
          if (exists $valid_keys{$key}) {
               push @{$search_parameters{$valid_keys{$key}}},
                    $value;
          }
          elsif ($key =~/users?/) {
               $users{$value} = 1;
          }
     }
     my %usertags;
     for my $user (keys %users) {
          my $ut = $soap->get_usertag($user)->result();
          next unless defined $ut;
          for my $tag (keys %{$ut}) {
               push @{$usertags{$tag}},
                    @{$ut->{$tag}};
          }
     }
     my $bugs = $soap->get_bugs(%search_parameters,
                                (keys %usertags)?(usertags=>\%usertags):()
                               )->result();
     if (not defined $bugs) {
          die "Error while retrieving bugs from SOAP server";
     }

    return $bugs;
}

1;

__END__

