=head1 NAME

Devscripts::Uscan::Config - uscan configuration object

=head1 SYNOPSIS

  use Devscripts::Uscan::Config;
  my $config = Devscripts::Uscan::Config->new->parse;

=head1 DESCRIPTION

Uscan configuration object. It can scan configuration files
(B</etc/devscripts.conf> and B<~/.devscripts>) and command line arguments.

=head1 METHODS

=head2 new()

Constructor

=cut

package Devscripts::Uscan::Config;

$| = 1;

use strict;

use Devscripts::Uscan::Output;
use Dpkg::IPC;
use Exporter 'import';
use File::HomeDir;
use Getopt::Long qw(:config bundling permute no_getopt_compat);
use Moo;

our $CURRENT_WATCHFILE_VERSION = 4;

our @EXPORT = (qw($CURRENT_WATCHFILE_VERSION));

# I - ACCESSORS

# Options + default values

has bare                => ( is => 'rw', default => sub { 0 } );
has check_dirname_level => ( is => 'rw', default => sub { 1 } );
has check_dirname_regex => ( is => 'rw', default => sub { 'PACKAGE(-.+)?' } );
has compression         => ( is => 'rw' );
has copyright_file      => ( is => 'rw', default => sub { undef } );
has destdir             => ( is => 'rw', default => sub { '..' } );
has download            => ( is => 'rw', default => sub { 1 } );
has download_current_version => ( is => 'rw' );
has download_debversion      => ( is => 'rw' );
has download_version         => ( is => 'rw' );
has exclusion                => ( is => 'rw', default => sub { 1 } );
has log                      => ( is => 'rw' );
has minversion               => ( is => 'rw', default => sub { '' } );
has orig                     => ( is => 'rw' );
has package                  => ( is => 'rw' );
has passive                  => ( is => 'rw', default => sub { 0 } );

# repack to .tar.$zsuffix if 1
has repack    => ( is => 'rw', default => sub { } );
has safe      => ( is => 'rw', default => sub { 0 } );
has signature => ( is => 'rw', default => sub { 1 } );
has symlink   => ( is => 'rw', default => sub { 'symlink' } );
has timeout   => ( is => 'rw', default => sub { 20 } );
has user_agent => ( is => 'rw' );
has uversion   => ( is => 'rw' );
has watchfile  => ( is => 'rw' );

# Internal attributes

has modified_conf_msg => ( is => 'rw' );

$ENV{HOME} = File::HomeDir->my_home;

=head2 parse()

Launches B<parse_conf_files()> and B<parse_command_line()>

=cut

sub parse {
    my ($self) = @_;

    # 1 - Parse /etc/devscripts.conf and ~/.devscripts
    $self->parse_conf_files;

    # 2 - Parse command line
    $self->parse_command_line;
    return $self;
}

# I - Parse /etc/devscripts.conf and ~/.devscripts
=head2 parse_conf_files()

Reads values in B</etc/devscripts.conf> and B<~/.devscripts>

=cut

sub parse_conf_files {
    my ($self) = @_;

    if ( @ARGV and $ARGV[0] =~ /^--no-?conf$/ ) {
        $self->modified_conf_msg("  (no configuration files read)");
        shift @ARGV;
    }
    else {
        my @config_files =
          grep { -r $_ } ( '/etc/devscripts.conf', "$ENV{HOME}/.devscripts" );
        if (@config_files) {
            my @keys = (
                qw(DEVSCRIPTS_CHECK_DIRNAME_LEVEL DEVSCRIPTS_CHECK_DIRNAME_REGEX
                  USCAN_DEHS_OUTPUT USCAN_DESTDIR USCAN_DOWNLOAD USCAN_EXCLUSION
                  USCAN_PASV USCAN_REPACK USCAN_SAFE USCAN_SYMLINK USCAN_TIMEOUT
                  USCAN_USER_AGENT USCAN_VERBOSE)
            );
            my %config_vars;

            my $shell_cmd =
                'for file in '
              . join( " ", @config_files )
              . '; do . $file; done;';

            # Read back values
            foreach my $var (@keys) {
                $shell_cmd .= "echo \$$var;\n";
            }
            my $shell_out;
            spawn(
                exec       => [ '/bin/bash', '-c', $shell_cmd ],
                wait_child => 1,
                to_string  => \$shell_out
            );
            @config_vars{@keys} = split /\n/, $shell_out, -1;

            # Check validity

            # Ignore bad boolean values
            foreach (
                qw(USCAN_DOWNLOAD USCAN_SAFE USCAN_VERBOSE USCAN_DEHS_OUTPUT
                USCAN_REPACK USCAN_EXCLUSION)
              )
            {
                if ( $config_vars{$_} ) {
                    $config_vars{$_} =~ /^(yes|no)$/
                      or $config_vars{$_} = undef;
                }
            }
            $config_vars{'USCAN_DESTDIR'} =~ /^\s*(\S+)\s*$/
              or $config_vars{'USCAN_DESTDIR'} = undef
              if ( $config_vars{'USCAN_DESTDIR'} );
            (         $config_vars{'USCAN_PASV'}
                  and $config_vars{'USCAN_PASV'} =~ /^(yes|no|default)$/ )
              or $config_vars{'USCAN_PASV'} = 'default';
            $config_vars{'USCAN_TIMEOUT'} =~ m/^\d+$/
              or $config_vars{'USCAN_TIMEOUT'} = undef
              if $config_vars{'USCAN_TIMEOUT'};
            $config_vars{'USCAN_SYMLINK'} =~ /^(yes|no|symlinks?|rename)$/
              or $config_vars{'USCAN_SYMLINK'} = 'yes'
              if $config_vars{'USCAN_SYMLINK'};
            $config_vars{'USCAN_SYMLINK'} = 'symlink'
              if $config_vars{'USCAN_SYMLINK'}
              and ($config_vars{'USCAN_SYMLINK'} eq 'yes'
                or $config_vars{'USCAN_SYMLINK'} =~ /^symlinks?$/ );
            $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} =~ /^[012]$/
              or $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} = undef
              if $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
            $self->{modified_conf_msg} ||= "  (none)\n";
            chomp $self->{modified_conf_msg};

            $verbose = $config_vars{'USCAN_VERBOSE'} eq 'yes' ? 1 : undef;

            foreach (
                qw(USCAN_DESTDIR USCAN_DOWNLOAD USCAN_SAFE USCAN_TIMEOUT
                USCAN_DEHS_OUTPUT DEVSCRIPTS_CHECK_DIRNAME_LEVEL
                DEVSCRIPTS_CHECK_DIRNAME_REGEX USCAN_REPACK USCAN_EXCLUSION
                USCAN_SYMLINK USCAN_USER_AGENT)
              )
            {
                my $name = lc($_);
                $name =~ s/^(?:uscan|devscripts)_//;
                if ( $config_vars{$_} and $config_vars{$_} ne $self->$name ) {
                    $self->{modified_conf_msg} .= "  $_=$config_vars{$_}\n";
                    $self->$name( $config_vars{$_} );
                }
            }

            my $tmp = $self->passive;
            $self->passive(
                  $config_vars{'USCAN_PASV'} eq 'yes' ? 1
                : $config_vars{'USCAN_PASV'} eq 'no'  ? 0
                :                                       'default'
            );
            $self->{modified_conf_msg} .=
              "  USCAN_PASV=$config_vars{USCAN_PASV}\n"
              unless ( $tmp = $self->passive );
        }
    }
    return $self;
}

# II - Parse command line
=head2 parse_command_line()

Parse command line arguments

=cut
sub parse_command_line {
    my ($self) = @_;

    # Now read the command line arguments
    my (
        $opt_h,       $opt_v,           $opt_destdir,
        $opt_safe,    $opt_download,    $opt_signature,
        $opt_passive, $opt_symlink,     $opt_repack,
        $opt_log,     $opt_compression, $opt_exclusion,
        $opt_copyright_file
    );
    my ( $opt_verbose, $opt_level, $opt_regex, $opt_noconf );
    my ( $opt_package, $opt_uversion, $opt_watchfile, $opt_dehs, $opt_timeout );
    my ( $opt_download_version, $opt_download_debversion );
    my $opt_bare;
    my $opt_user_agent;
    my $opt_download_current_version;

    GetOptions(
        "bare"                           => \$opt_bare,
        "check-dirname-level=s"          => \$opt_level,
        "check-dirname-regex=s"          => \$opt_regex,
        "compression=s"                  => \$opt_compression,
        "copy"                           => sub { $opt_symlink = 'copy'; },
        "copyright-file=s"               => \$opt_copyright_file,
        "debug"                          => sub { $verbose = 2; },
        "dehs!"                          => \$opt_dehs,
        "destdir=s"                      => \$opt_destdir,
        "d|download+"                    => \$opt_download,
        "download-current-version"       => \$opt_download_current_version,
        "download-version=s"             => \$opt_download_version,
        "dversion|download-debversion=s" => \$opt_download_debversion,
        "exclusion!"                     => \$opt_exclusion,
        "force-download"                 => sub { $opt_download = 2; },
        "help"                           => \$opt_h,
        "log"                            => \$opt_log,
        "noconf|no-conf"                 => \$opt_noconf,
        "nodownload|no-download"         => sub { $opt_download = 0; },
        "noverbose|no-verbose"           => sub { $verbose = 0; },
        "overwrite-download"             => sub { $opt_download = 3; },
        "package=s"                      => \$opt_package,
        "passive|pasv!"                  => \$opt_passive,
        "rename"                         => sub { $opt_symlink = 'rename'; },
        "repack"                         => sub { $opt_repack = 1; },
        "report|safe"                    => \$opt_safe,
        "report-status" =>
          sub { $opt_safe = 1; $verbose = 1 unless ($verbose); },
        "signature!"    => \$opt_signature,
        "symlink!"      => sub { $opt_symlink = $_[1] ? 'symlink' : 'no'; },
        "skipsignature|skip-signature" => sub { $opt_signature = -1; },
        "timeout=i"                    => \$opt_timeout,
        "user-agent|useragent=s"       => \$opt_user_agent,
        "uversion|upstream-version=s"  => \$opt_uversion,
        "v|verbose+" => sub { $verbose = 1 unless ($verbose); },
        "version"                      => \$opt_v,
        "watchfile=s"                  => \$opt_watchfile,
      )
      or uscan_die
"Usage: $progname [options] [directories]\nRun $progname --help for more details";

    if ($opt_noconf) {
        die
"$progname: --no-conf is only acceptable as the first command-line option!";
    }
    if ($opt_h) { $self->usage();   exit 0; }
    if ($opt_v) { $self->version(); exit 0; }
    $verbose //= $opt_verbose // 0;

    # Now we can set the other variables according to the command line options

    $dehs = $opt_dehs if ( defined($opt_dehs) );
    foreach (
        qw(bare compression copyright_file destdir download_current_version
        download_debversion download_version exclusion log package passive repack
        signature symlink timeout user_agent uversion watchfile)
      )
    {

        # Local variables can't be used in a ${"opt_$_"}, so using eval
        no strict 'refs';
        my $v = eval "\$opt_$_";
        $self->{$_} = $v if defined($v);
    }
    no strict;

    if ( !-d $self->destdir ) {
        uscan_die
"The directory to store downloaded files is missing: $self->{destdir}";
    }

    uscan_verbose
      "The directory to store downloaded files(\$destdir): $self->{destdir}";

    if ( defined $opt_package ) {
        $self->download(0);    # compatibility
        uscan_die
          "The --package option requires to set the --watchfile option, too."
          unless defined $opt_watchfile;
    }
    $self->safe(1) if defined $opt_safe;
    $self->download(0) if $self->safe == 1;

    # $download:   0 = no-download,
    #              1 = download (default, only-new),
    #              2 = force-download (even if file is up-to-date version),
    #              3 = overwrite-download (even if file exists)
    $self->download($opt_download) if defined $opt_download;

    # $signature: -1 = no downloading signature and no verifying signature,
    #              0 = no downloading signature but verifying signature,
    #              1 = downloading signature and verifying signature
    $self->signature(-1) if $self->download == 0;    # Change default 1 -> -1
    $self->timeout = 20
      unless ( defined $self->timeout and $self->timeout > 0 );

    if ( defined $opt_level ) {
        if ( $opt_level =~ /^[012]$/ ) {
            $self->check_dirname_level($opt_level);
        }
        else {
            uscan_die
"Unrecognised --check-dirname-level value (allowed are 0,1,2): $opt_level";
        }
    }

    $self->{check_dirname_regex} = $opt_regex if defined $opt_regex;

    uscan_verbose
      "$progname (version $main::uscan_version) See $progname(1) for help";
    if ($dehs) {
        uscan_verbose "The --dehs option enabled.\n"
          . "        STDOUT = XML output for use by other programs\n"
          . "        STDERR = plain text output for human\n"
          . "        Use the redirection of STDOUT to a file to get the clean XML data";
    }
    if ( defined $self->watchfile and @ARGV ) {
        uscan_die "Can't have directory arguments if using --watchfile";
    }
    return $self;
}

# help methods
sub usage {
    my ($self) = @_;
    print <<"EOF";
Usage: $progname [options] [dir ...]
  Process watch files in all .../debian/ subdirs of those listed (or the
  current directory if none listed) to check for upstream releases.
Options:
    --no-conf, --noconf
                   Don\'t read devscripts config files;
                   must be the first option given
    --no-verbose   Don\'t report verbose information.
    --verbose, -v  Report verbose information.
    --debug, -vv   Report verbose information including the downloaded
                   web pages as processed to STDERR for debugging.
    --dehs         Send DEHS style output (XML-type) to STDOUT, while
                   send all other uscan output to STDERR.
    --no-dehs      Use only traditional uscan output format (default)
    --download, -d
                   Download the new upstream release (default)
    --force-download, -dd
                   Download the new upstream release, even if up-to-date
                   (may not overwrite the local file)
    --overwrite-download, -ddd
                   Download the new upstream release, even if up-to-date
                  (may overwrite the local file)
    --no-download, --nodownload
                   Don\'t download and report information.
		   Previously downloaded tarballs may be used.
                   Change default to --skip-signature.
    --signature    Download signature and verify (default)
    --no-signature Don\'t download signature but verify if already downloaded.
    --skip-signature
                   Don\'t bother download signature nor verify it.
    --safe, --report
                   avoid running unsafe scripts by skipping both the repacking
                   of the downloaded package and the updating of the new
                   source tree.  Change default to --no-download and
                   --skip-signature.
    --report-status (= --safe --verbose)
    --download-version VERSION
                   Specify the version which the upstream release must
                   match in order to be considered, rather than using the
                   release with the highest version
    --download-debversion VERSION
		   Specify the Debian package version to download the
		   corresponding upstream release version.  The
		   dversionmangle and uversionmangle rules are
		   considered.
    --download-current-version
                   Download the currently packaged version
    --check-dirname-level N
                   Check parent directory name?
                   N=0   never check parent directory name
                   N=1   only when $progname changes directory (default)
                   N=2   always check parent directory name
    --check-dirname-regex REGEX
                   What constitutes a matching directory name; REGEX is
                   a Perl regular expression; the string \`PACKAGE\' will
                   be replaced by the package name; see manpage for details
                   (default: 'PACKAGE(-.+)?')
    --destdir      Path of directory to which to download.
    --package PACKAGE
                   Specify the package name rather than examining
                   debian/changelog; must use --upstream-version and
                   --watchfile with this option, no directory traversing
                   will be performed, no actions (even downloading) will be
                   carried out
    --upstream-version VERSION
                   Specify the current upstream version in use rather than
                   parsing debian/changelog to determine this
    --watchfile FILE
                   Specify the watch file rather than using debian/watch;
                   no directory traversing will be done in this case
    --bare         Disable all site specific special case codes to perform URL
                   redirections and page content alterations.
    --no-exclusion Disable automatic exclusion of files mentioned in
                   debian/copyright field Files-Excluded and Files-Excluded-*
    --pasv         Use PASV mode for FTP connections
    --no-pasv      Don\'t use PASV mode for FTP connections (default)
    --no-symlink   Don\'t rename nor repack upstream tarball
    --timeout N    Specifies how much time, in seconds, we give remote
                   servers to respond (default 20 seconds)
    --user-agent, --useragent
                   Override the default user agent string
    --log          Record md5sum changes of repackaging
    --help         Show this message
    --version      Show version information

Options passed on to mk-origtargz:
    --symlink      Create a correctly named symlink to downloaded file (default)
    --rename       Rename instead of symlinking
    --copy         Copy instead of symlinking
    --repack       Repack downloaded archives to change compression
    --compression [ gzip | bzip2 | lzma | xz ]
                   When the upstream sources are repacked, use compression COMP
                   for the resulting tarball (default: gzip)
    --copyright-file FILE
                   Remove files matching the patterns found in FILE

Default settings modified by devscripts configuration files:
$self->{modified_conf_msg}
EOF
}

sub version {
    print <<"EOF";
This is $progname, from the Debian devscripts package, version $main::uscan_version
This code is copyright 1999-2006 by Julian Gilbey and 2018 by Xavier Guimard,
all rights reserved.
Original code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later.
EOF
}

1;
__END__
=head1 SEE ALSO

L<uscan>

=head1 AUTHOR

B<uscan> was originally written by Christoph Lameter
E<lt>clameter@debian.orgE<gt> (I believe), modified by Julian Gilbey
E<lt>jdg@debian.orgE<gt>. HTTP support was added by Piotr Roszatycki
E<lt>dexter@debian.orgE<gt>. B<uscan> was rewritten in Perl by Julian Gilbey.
Xavier Guimard E<lt>yadd@debian.orgE<gt> rewrote uscan in object
oriented Perl.

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2006 by Julian Gilbey <jdg@debian.org>,
2018 by Xavier Guimard <yadd@debian.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
