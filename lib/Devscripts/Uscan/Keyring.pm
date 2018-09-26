package Devscripts::Uscan::Keyring;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Dpkg::IPC;
use File::Copy qw/copy move/;
use File::Which;
use File::Path qw/make_path remove_tree/;
use File::Temp qw/tempfile tempdir/;
use List::Util qw/first/;

sub new {
    my ($class) = @_;
    my $keyring;
    my $havegpgv = first {
        which $_
    }
    qw(gpgv2 gpgv);
    my $havegpg = first {
        which $_
    }
    qw(gpg2 gpg);
    uscan_die("Please install gpgv or gpgv2.")   unless defined $havegpgv;
    uscan_die("Please install gnupg or gnupg2.") unless defined $havegpg;

    # upstream/signing-key.pgp and upstream-signing-key.pgp are deprecated
    # but supported
    if ( -r "debian/upstream/signing-key.asc" ) {
        $keyring = "debian/upstream/signing-key.asc";
    }
    else {
        my $binkeyring = first { -r $_ } qw(
          debian/upstream/signing-key.pgp
          debian/upstream-signing-key.pgp
        );
        if ( defined $binkeyring ) {
            make_path( 'debian/upstream', 0700, 'true' );

            # convert to the policy complying armored key
            uscan_verbose("Found upstream binary signing keyring: $binkeyring");

            # Need to convert to an armored key
            $keyring = "debian/upstream/signing-key.asc";
            uscan_warn "Found deprecated binary keyring ($binkeyring)."
              . "Please save it in armored format in $keyring. For example:\n"
              . "   gpg --output $keyring --enarmor $binkeyring";
            spawn(
                exec => [
                    $havegpg,
                    '--homedir' => "/dev/null",
                    '--no-options', '-q', '--batch', '--no-default-keyring',
                    '--output' => $keyring,
                    '--enarmor', $binkeyring
                ],
                wait_child => 1
            );
            uscan_warn("Generated upstream signing keyring: $keyring");
            move $binkeyring, "$binkeyring.backup";
            uscan_verbose(
                "Renamed upstream binary signing keyring: $binkeyring.backup");
        }
    }

    # Need to convert an armored key to binary for use by gpgv
    my $gpghome;
    if ( defined $keyring ) {
        uscan_verbose("Found upstream signing keyring: $keyring");
        if ( $keyring =~ m/\.asc$/ ) {    # always true
            $gpghome = tempdir( CLEANUP => 1 );
            my $newkeyring = "$gpghome/trustedkeys.gpg";
            spawn(
                exec => [
                    $havegpg,
                    '--homedir' => $gpghome,
                    '--no-options', '-q', '--batch', '--no-default-keyring',
                    '--output' => $newkeyring,
                    '--dearmor', $keyring
                ],
                wait_child => 1
            );
            $keyring = $newkeyring;
        }
    }

    # Return undef if not key found
    else {
        return undef;
    }
    my $self = bless {
        keyring => $keyring,
        gpghome => $gpghome,
        gpgv    => $havegpgv,
        gpg     => $havegpg,
    }, $class;
    return $self;
}

sub verify {
    my ( $self, $sigfile, $newfile ) = @_;
    uscan_verbose(
        "Verifying OpenPGP self signature of $newfile and extract $sigfile");
    unless (
        uscan_exec_no_fail(
            $self->{gpg},
            '--homedir' => $self->{gpghome},
            '--no-options', '-q', '--batch', '--no-default-keyring',
            '--keyring' => $self->{keyring},
            '--trust-model', 'always', '--decrypt',
            '-o' => "$sigfile",
            "$newfile"
        ) >> 8 == 0
      )
    {
        uscan_die("OpenPGP signature did not verify.");
    }
}

sub verifyv {
    my ( $self, $sigfile, $base ) = @_;
    uscan_verbose("Verifying OpenPGP signature $sigfile for $base");
    unless (
        uscan_exec_no_fail(
            $self->{gpgv},
            '--homedir' => '/dev/null',
            '--keyring' => $self->{keyring},
            $sigfile, $base
        ) >> 8 == 0
      )
    {
        uscan_die("OpenPGP signature did not verify.");
    }
}

sub verify_git {
    my ( $self, $gitdir, $tag ) = @_;
    my $commit;
    spawn(
        exec      => [ 'git', '--git-dir', "../$gitdir", 'show-ref', $tag ],
        to_string => \$commit
    );
    uscan_die "git tag not found" unless ($commit);
    $commit =~ s/\s.*$//;
    chomp $commit;
    my $file;
    spawn(
        exec => [ 'git', '--git-dir', "../$gitdir", 'cat-file', '-p', $commit ],
        to_string => \$file
    );
    my $dir;
    spawn( exec => [ 'mktemp', '-d' ], to_string => \$dir );
    chomp $dir;

    unless ( $file =~ /^(.*?\n)(\-+\s*BEGIN PGP SIGNATURE\s*\-+.*)$/s ) {
        uscan_die "Tag $tag is not signed";
    }
    open F, ">$dir/txt" or die $!;
    open S, ">$dir/sig" or die $!;
    print F $1;
    print S $2;
    close F;
    close S;

    unless (
        uscan_exec_no_fail(
            $self->{gpg},
            '--homedir' => $self->{gpghome},
            '--keyring' => $self->{keyring},
            '--verify',
            "$dir/sig", "$dir/txt"
        ) >> 8 == 0
      )
    {
        uscan_die("OpenPGP signature did not verify.");
    }
    remove_tree($dir);
}

1;
