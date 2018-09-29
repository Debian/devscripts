
=pod

=head1 NAME

Devscripts::Uscan::WatchLine - watch line object for L<uscan>

=head1 DESCRIPTION

Uscan class to parse watchfiles.

=head1 MAIN METHODS

=cut

package Devscripts::Uscan::WatchLine;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Keyring;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Dpkg::IPC;
use Dpkg::Version;
use File::Basename;
use File::Spec::Functions qw/catfile/;
use HTTP::Headers;
use Moo;
use Text::ParseWords;

#################
### ACCESSORS ###
#################

=head2 new() I<(Constructor)>

=head3 Required parameters

=over

=item B<shared>: ref to hash containing line options shared between lines. See
L<Devscripts::Uscan::WatchFile> code to see required keys.

=item B<keyring>: L<Devscripts::Uscan::Keyring> object

=item B<config>: L<Devscripts::Uscan::Config> object

=item B<downloader>: L<Devscripts::Uscan::Downloader> object

=item B<line>: search line (assembled in one line)

=item B<pkg>: Debian package name

=item B<pkg_dir>: Debian package source directory

=item B<pkg_version>: Debian package version

=item B<watchfile>: Current watchfile

=item B<watch_version>: Version of current watchfile

=back

=cut

foreach (

    # Shared attributes stored in WatchFile object (ref to WatchFile value)
    'shared', 'keyring', 'config',

    # Other
    'downloader',    # Devscripts::Uscan::Downloader object
    'line',          # watch line string (concatenated line over the tailing \ )
    'pkg',           # source package name found in debian/changelog
    'pkg_dir',       # usually .
    'pkg_version',   # last source package version
                     # found in debian/changelog
    'watchfile',        # usually debian/watch
    'watch_version',    # usually 4 (or 3)
  )
{
    has $_ => ( is => 'rw', required => 1 );
}

has repack => (
    is => 'rw',
    lazy => 1,
    default => sub { $_[0]->config->{repack} },
);

has safe => (
    is => 'rw',
    lazy => 1,
    default => sub { $_[0]->config->{safe} },
);

has symlink => (
    is => 'rw',
    lazy => 1,
    default => sub { $_[0]->config->{symlink} },
);

has versionmode => (
    is => 'rw',
    lazy => 1,
    default => sub { 'newer' },
);

# 2 - Line options read/write attributes

foreach (
    qw(
    component hrefdecode repacksuffix unzipopt
    dirversionmangle downloadurlmangle dversionmangle filenamemangle pagemangle
    oversionmangle oversionmanglepagemangle pgpsigurlmangle uversionmangle
    versionmangle
    )
  )
{
    has $_ => (
        is => 'rw',
        ( /mangle/ ? ( default => sub { [] } ) : () )
    );
}

has compression => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        $_[0]->config->compression
          ? get_compression( $_[0]->config->compression )
          : undef;
    },
);
has versionless => ( is => 'rw' );

# 4 - Internal attributes
has style  => ( is => 'rw', default => sub { 'new' } );
has status => ( is => 'rw', default => sub { 0 } );
foreach (
    qw(badversion
    signature_available must_download)
  )
{
    has $_ => ( is => 'rw', default => sub { 0 } );
}
foreach (qw(mangled_version)) {
    has $_ => ( is => 'rw' );
}
foreach (qw(sites basedirs patterns)) {
    has $_ => ( is => 'rw', default => sub { [] } );
}

# 5 - Results
foreach (qw(parse_result search_result)) {
    has $_ => ( is => 'rw', default => sub { {} } );
}
foreach (qw(upstream_url newfile_base)) {
    has $_ => ( is => 'rw' );
}

# 3.1 - Attributes initialized with default value, modified by line content
has date => (
    is      => 'rw',
    default => sub { '%Y%m%d' },
);
has decompress => (
    is      => 'rw',
    default => sub { 0 },
);
has gitmode => (
    is      => 'rw',
    default => sub { 'shallow' },
);
has mode => (
    is      => 'rw',
    default => sub { 'LWP' },
);
has pgpmode => (
    is      => 'rw',
    default => sub { 'default' },
);
has pretty => (
    is      => 'rw',
    default => sub { '0.0~git%cd.%h' },
);

# 3.2 - Self build attributes

has gitrepo_dir => (    # Working repository used only within uscan.
    is      => 'ro',
    lazy    => 1,
    default => sub {
        $_[0]->{pkg} . "-temporary.$$.git";
    }
);
has headers => (
    is      => 'ro',
    default => sub {
        my $h = HTTP::Headers->new;
        $h->header(
            'X-uscan-features' => 'enhanced-matching',
            'Accept'           => '*/*'
        );
        return $h;
    },
);

###############
# Main method #
###############
=head2 process()

Launches all needed methods in this order: parse(), search(),
get_upstream_url(), get_newfile_base(), cmp_versions(),
download_file_and_sig(), mkorigtargz(), clean()

If one method returns a non 0 value, it stops and return this error code.

=cut

sub process {
    my ($self) = @_;

    #  - parse line
    $self->parse

      #  - search newfile and newversion
      or $self->search

      #  - determine upstream_url
      or $self->get_upstream_url

      #  - determine newfile_base
      or $self->get_newfile_base

      #  - compare versions
      or $self->cmp_versions

      #  - download
      or $self->download_file_and_sig

      #  - make orig.tar.gz
      or $self->mkorigtargz

      #  - clean (used by git)
      or $self->clean;
    return $self->status;
}

#########
# STEPS #
#########
=head2 Steps

=cut

# I - parse
=head3 parse()

Parse the line and return 0 if nothing bad happen. It populates
C<$self-E<gt>parse_result> accessor with a hash that contains the
following keys:

=over

=item base
=item filepattern
=item lastversion
=item action
=item site
=item basedir
=item mangled_lastversion
=item pattern

=back

=cut

# watch_version=1: Lines have up to 5 parameters which are:
#
# $1 = Remote site
# $2 = Directory on site
# $3 = Pattern to match, with (...) around version number part
# $4 = Last version we have (or 'debian' for the current Debian version)
# $5 = Actions to take on successful retrieval
#
# watch_version=2:
#
# For ftp sites:
#   ftp://site.name/dir/path/pattern-(.+)\.tar\.gz [version [action]]
#
# For http sites:
#   http://site.name/dir/path/pattern-(.+)\.tar\.gz [version [action]]
#
# watch_version=3 and 4: See details in POD.
#
# For ftp sites:
#   ftp://site.name/dir/path pattern-(.+)\.tar\.gz [version [action]]
#
# For http sites:
#   http://site.name/dir/path pattern-(.+)\.tar\.gz [version [action]]
#
# For git sites:
#   http://site.name/dir/path/project.git refs/tags/v([\d\.]+) [version [action]]
# or
#   http://site.name/dir/path/project.git HEAD [version [action]]
#
# watch_version=3 and 4: See POD for details.
#
# Lines can be prefixed with opts=<opts> but can be folded for readability.
#
# Then the patterns matched will be checked to find the one with the
# greatest version number (as determined by the (...) group), using the
# Debian version number comparison algorithm described below.

sub parse {
    my ($self) = @_;
    uscan_debug "parse line $self->{line}";

    # Need to clear remembered redirection URLs so we don't try to build URLs
    # from previous watch files or watch lines
    $self->downloader->user_agent->clear_redirections;

    my $watchfile = $self->watchfile;
    my ( $action, $base, $basedir, $filepattern, $lastversion, $pattern,
        $site );
    $dehs_tags = { package => $self->pkg };

    # Start parsing the watch line
    if ( $self->watch_version == 1 ) {
        my ($dir);
        ( $site, $dir, $filepattern, $lastversion, $action ) = split ' ',
          $self->line, 5;
        if (  !$lastversion
            or $site =~ /\(.*\)/
            or $dir =~ /\(.*\)/ )
        {
            uscan_warn <<EOF;
there appears to be a version 2 format line in
the version 1 watch file $watchfile;
Have you forgotten a 'version=2' line at the start, perhaps?
Skipping the line: $self->{line}
EOF
            return $self->status(1);
        }
        if ( $site !~ m%\w+://% ) {
            $site = "ftp://$site";
            if ( $filepattern !~ /\(.*\)/ ) {

                # watch_version=1 and old style watch file;
                # pattern uses ? and * shell wildcards; everything from the
                # first to last of these metachars is the pattern to match on
                $filepattern =~ s/(\?|\*)/($1/;
                $filepattern =~ s/(\?|\*)([^\?\*]*)$/$1)$2/;
                $filepattern =~ s/\./\\./g;
                $filepattern =~ s/\?/./g;
                $filepattern =~ s/\*/.*/g;
                $self->style('old');
                uscan_warn
                  "Using very old style of filename pattern in $watchfile\n"
                  . "  (this might lead to incorrect results): $3";
            }
        }

        # Merge site and dir
        $base = "$site/$dir/";
        $base =~ s%(?<!:)//%/%g;
        $base =~ m%^(\w+://[^/]+)%;
        $site    = $1;
        $pattern = $filepattern;

        # Check $filepattern is OK
        if ( $filepattern !~ /\(.*\)/ ) {
            uscan_warn "Filename pattern missing version delimiters ()\n"
              . "  in $watchfile, skipping:\n  $self->{line}";
            return $self->status(1);
        }
    }
    else {
        # version 2/3/4 watch file
        if ( $self->{line} =~ s/^opt(?:ion)?s\s*=\s*// ) {
            my $opts;
            if ( $self->{line} =~ s/^"(.*?)"(?:\s+|$)// ) {
                $opts = $1;
            }
            elsif ( $self->{line} =~ s/^([^"\s]\S*)(?:\s+|$)// ) {
                $opts = $1;
            }
            else {
                uscan_warn
"malformed opts=... in watch file, skipping line:\n$self->{line}";
                return $self->status(1);
            }

            # $opts	string extracted from the argument of opts=
            uscan_verbose "opts: $opts";

            # $self->line watch line string without opts=... part
            uscan_verbose "line: $self->{line}";

            # user-agent strings has ,;: in it so special handling
            if (   $opts =~ /^\s*user-agent\s*=\s*(.+?)\s*$/
                or $opts =~ /^\s*useragent\s*=\s*(.+?)\s*$/ )
            {
                my $user_agent_string = $1;
                $user_agent_string = $self->config->user_agent
                  if $self->config->user_agent;
                $self->downloader->user_agent->agent($user_agent_string);
                uscan_verbose "User-agent: $user_agent_string";
                $opts = '';
            }
            my @opts = split /,/, $opts;
            foreach my $opt (@opts) {
                uscan_verbose "Parsing $opt";
                if ( $opt =~ /^\s*pasv\s*$/ or $opt =~ /^\s*passive\s*$/ ) {
                    $self->downloader->passive(1);
                }
                elsif ($opt =~ /^\s*active\s*$/
                    or $opt =~ /^\s*nopasv\s*$/
                    or $opt =~ /^s*nopassive\s*$/ )
                {
                    $self->downloader->passive(0);
                }

                # Line option "compression" is ignored if "--compression"
                # was set in command-line
                elsif ( $opt =~ /^\s*compression\s*=\s*(.+?)\s*$/
                    and not $self->compression )
                {
                    $self->compression( get_compression($1) );
                }
                elsif ( $opt =~ /^\s*bare\s*$/ ) {

                    # persistent $bare
                    ${ $self->shared->{bare} } = 1;
                }

                # Boolean line parameter
                #
                # $ regexp-assemble <<EOF
                # decompress
                # repack
                # EOF
                elsif ( $opt =~ /^\s*(decompress|repack)\s*$/ ) {
                    $self->$1(1);
                }

                # Line parameter with a value
                #
                # $ regexp-assemble <<EOF
                # component
                # date
                # gitmode
                # hrefdecode
                # mode
                # pgpmode
                # pretty
                # repacksuffix
                # unzipopt
                # EOF
                elsif ( $opt =~
/^\s*((?:(?:(?:git)?m|hrefdec)od|dat)e|(?:componen|unzipop)t|p(?:gpmode|retty)|repacksuffix)\s*=\s*(.+?)\s*$/
                  )
                {
                    $self->$1($2);
                }
                elsif ( $opt =~ /^\s*versionmangle\s*=\s*(.+?)\s*$/ ) {
                    $self->uversionmangle( [ split /;/, $1 ] );
                    $self->dversionmangle( [ split /;/, $1 ] );
                }
                elsif ( $opt =~ /^\s*pgpsigurlmangle\s*=\s*(.+?)\s*$/ ) {
                    $self->pgpsigurlmangle( [ split /;/, $1 ] );
                    $self->pgpmode('mangle');
                }
                elsif ( $opt =~ /^\s*dversionmangle\s*=\s*(.+?)\s*$/ ) {

                    $self->dversionmangle(
                        [
                            map {

                                # If dversionmangle is "auto", replace it by
                                # DEB_EXT removal
                                $_ eq 'auto'
                                  ? ( 's/'
                                      . &Devscripts::Uscan::WatchFile::DEB_EXT
                                      . '//' )
                                  : ($_)
                            } split /;/,
                            $1
                        ]
                    );
                }

                # Handle other *mangle:
                #
                # $ regexp-assemble <<EOF
                # pagemangle
                # dirversionmangle
                # uversionmangle
                # downloadurlmangle
                # filenamemangle
                # oversionmangle
                # EOF
                elsif ( $opt =~
/^\s*((?:d(?:ownloadurl|irversion)|(?:filenam|pag)e|[ou]version)mangle)\s*=\s*(.+?)\s*$/
                  )
                {
                    $self->$1( [ split /;/, $2 ] );
                }
                else {
                    uscan_warn "unrecognized option $opt";
                }
            }

            # $self->line watch line string when no opts=...
            uscan_verbose "line: $self->{line}";
        }

        if ( $self->line eq '' ) {
            uscan_verbose "watch line only with opts=\"...\" and no URL";
            return $self->status(1);
        }

        # 4 parameter watch line
        ( $base, $filepattern, $lastversion, $action ) = split /\s+/,
          $self->line, 4;

        # 3 parameter watch line (override)
        if ( $base =~ s%/([^/]*\([^/]*\)[^/]*)$%/% ) {

            # Last component of $base has a pair of parentheses, so no
            # separate filepattern field; we remove the filepattern from the
            # end of $base and rescan the rest of the line
            $filepattern = $1;
            ( undef, $lastversion, $action ) = split /\s+/, $self->line, 3;
        }

        # Always define "" if not defined
        $lastversion //= '';
        $action      //= '';
        if ( $self->mode eq 'LWP' ) {
            if ( $base =~ m%^https?://% ) {
                $self->mode('http');
            }
            elsif ( $base =~ m%^ftp://% ) {
                $self->mode('ftp');
            }
            else {
                uscan_warn "unknown protocol for LWP: $base";
                return $self->status(1);
            }
        }

        # compression is persistent
        $self->compression(
            (
                     $self->mode eq 'http'
                  or $self->mode eq 'ftp'
            )
            ? get_compression('gzip')    # keep backward compat
            : get_compression('xz')
        ) unless ( $self->compression );

        # Set $lastversion to the numeric last version
        # Update $self->versionmode (its default "newer")
        if ( !length($lastversion) or $lastversion eq 'debian' ) {
            if ( !defined $self->pkg_version ) {
                uscan_warn "Unable to determine the current version\n"
                  . "  in $watchfile, skipping:\n  $self->{line}";
                return $self->status(1);
            }
            $lastversion = $self->pkg_version;
        }
        elsif ( $lastversion eq 'ignore' ) {
            $self->versionmode('ignore');
            $lastversion = $self->config->minversion;
        }
        elsif ( $lastversion eq 'same' ) {
            $self->versionmode('same');
            $lastversion = $self->config->minversion;
        }
        elsif ( $lastversion =~ m/^prev/ ) {
            $self->versionmode('previous');

            # set $lastversion = $previous_newversion later
        }

        # Check $filepattern has ( ...)
        if ( $filepattern !~ /\([^?].*\)/ ) {
            if ( $self->mode eq 'git' and $filepattern eq 'HEAD' ) {
                $self->versionless(1);
            }
            elsif ( $self->mode eq 'git'
                and $filepattern =~ m&^heads/& )
            {
                $self->versionless(1);
            }
            elsif ( $self->mode eq 'http'
                and @{ $self->filenamemangle } )
            {
                $self->versionless(1);
            }
            else {
                uscan_warn
                  "Tag pattern missing version delimiters () in $watchfile"
                  . ", skipping:\n  $self->{line}";
                return $self->status(1);
            }
        }

        # Check validity of options
        if ( $self->mode eq 'ftp'
            and @{ $self->downloadurlmangle } )
        {
            uscan_warn "downloadurlmangle option invalid for ftp sites,\n"
              . "  ignoring downloadurlmangle in $watchfile:\n"
              . "  $self->{line}";
            return $self->status(1);
        }

        # Limit use of opts="repacksuffix" to the single upstream package
        if ( $self->repacksuffix and @{ $self->shared->{components} } ) {
            uscan_warn
"repacksuffix is not compatible with the multiple upstream tarballs;\n"
              . "  use oversionmangle";
            return $self->status(1);
        }

        # Allow 2 char shorthands for opts="pgpmode=..." and check
        if ( $self->pgpmode =~ m/^au/ ) {
            $self->pgpmode('auto');
            if ( @{ $self->pgpsigurlmangle } ) {
                uscan_warn "Ignore pgpsigurlmangle because pgpmode=auto";
                $self->pgpsigurlmangle( [] );
            }
        }
        elsif ( $self->pgpmode =~ m/^ma/ ) {
            $self->pgpmode('mangle');
            if ( not @{ $self->pgpsigurlmangle } ) {
                uscan_warn "Missing pgpsigurlmangle.  Setting pgpmode=default";
                $self->pgpmode('default');
            }
        }
        elsif ( $self->pgpmode =~ m/^no/ ) {
            $self->pgpmode('none');
        }
        elsif ( $self->pgpmode =~ m/^ne/ ) {
            $self->pgpmode('next');
        }
        elsif ( $self->pgpmode =~ m/^pr/ ) {
            $self->pgpmode('previous');
            $self->versionmode('previous');    # no other value allowed
                # set $lastversion = $previous_newversion later
        }
        elsif ( $self->pgpmode =~ m/^se/ ) {
            $self->pgpmode('self');
        }
        elsif ( $self->pgpmode =~ m/^git/ ) {
            $self->pgpmode('gittag');
        }
        else {
            $self->pgpmode('default');
        }

        # If PGP used, check required programs and generate files
        if ( @{ $self->pgpsigurlmangle } ) {
            my $pgpsigurlmanglestring =
              join( ";", @{ $self->pgpsigurlmangle } );
            uscan_debug "\$self->{'pgpmode'}=$self->{'pgpmode'}, "
              . "\$self->{'pgpsigurlmangle'}=$pgpsigurlmanglestring";
        }
        else {
            uscan_debug "\$self->{'pgpmode'}=$self->{'pgpmode'}, "
              . "\$self->{'pgpsigurlmangle'}=undef";
        }

        # Check component for duplication and set $orig to the proper
        # extension string
        if ( $self->pgpmode ne 'previous' ) {
            if ( $self->component ) {
                if ( grep { $_ eq $self->component }
                    @{ $self->shared->{components} } )
                {
                    uscan_warn "duplicate component name: $self->{component}";
                    return $self->status(1);
                }
                push @{ $self->shared->{components} }, $self->component;
            }
            else {
                $self->shared->{origcount}++;
                if ( $self->shared->{origcount} > 1 ) {
                    uscan_warn "more than one main upstream tarballs listed.";

                    # reset variables
                    @{ $self->shared->{components} } = ();
                    $self->{shared}->{common_newversion}           = undef;
                    $self->{shared}->{common_mangled_newversion}   = undef;
                    $self->{shared}->{previous_newversion}         = undef;
                    $self->{shared}->{previous_newfile_base}       = undef;
                    $self->{shared}->{previous_sigfile_base}       = undef;
                    $self->{shared}->{previous_download_available} = undef;
                    $self->{shared}->{uscanlog}                    = undef;
                }
            }
        }

        # Allow 2 char shorthands for opts="gitmode=..." and check
        if ( $self->gitmode =~ m/^sh/ ) {
            $self->gitmode('shallow');
        }
        elsif ( $self->gitmode =~ m/^fu/ ) {
            $self->gitmode('full');
        }
        else {
            uscan_warn
              "Override strange manual gitmode '$self->gitmode --> 'shallow'";
            $self->gitmode('shallow');
        }

        # Handle sf.net addresses specially
        if ( !$self->shared->{bare} and $base =~ m%^https?://sf\.net/% ) {
            uscan_verbose "sf.net redirection to qa.debian.org/watch/sf.php";
            $base =~ s%^https?://sf\.net/%https://qa.debian.org/watch/sf.php/%;
            $filepattern .= '(?:\?.*)?';
        }

        # Handle pypi.python.org addresses specially
        if (   !$self->shared->{bare}
            and $base =~ m%^https?://pypi\.python\.org/packages/source/% )
        {
            uscan_verbose "pypi.python.org redirection to pypi.debian.net";
            $base =~
s%^https?://pypi\.python\.org/packages/source/./%https://pypi.debian.net/%;
        }

        # Handle pkg-ruby-extras gemwatch addresses specially
        if ( $base =~
            m%^https?://pkg-ruby-extras\.alioth\.debian\.org/cgi-bin/gemwatch% )
        {
            uscan_warn
"redirecting DEPRECATED pkg-ruby-extras.alioth.debian.org/cgi-bin/gemwatch"
              . " to gemwatch.debian.net";
            $base =~
s%^https?://pkg-ruby-extras\.alioth\.debian\.org/cgi-bin/gemwatch%https://gemwatch.debian.net%;
        }

    }

    # End parsing the watch line for all version=1/2/3/4
    # all options('...') variables have been set

    # Override the last version with --download-debversion
    if ( $self->config->download_debversion ) {
        $lastversion = $self->config->download_debversion;
        $lastversion =~ s/-[^-]+$//;    # revision
        $lastversion =~ s/^\d+://;      # epoch
        uscan_verbose
"specified --download-debversion to set the last version: $lastversion";
    }
    elsif ( $self->versionmode eq 'previous' ) {
        $lastversion = $self->shared->{previous_newversion};
        uscan_verbose "Previous version downloaded: $lastversion";
    }
    else {
        uscan_verbose
"Last orig.tar.* tarball version (from debian/changelog): $lastversion";
    }

    # And mangle it if requested
    my $mangled_lastversion = $lastversion;
    if (
        mangle(
            $watchfile,        \$self->line,
            'dversionmangle:', \@{ $self->dversionmangle },
            \$mangled_lastversion
        )
      )
    {
        return $self->status(1);
    }

    # Set $download_version etc. if already known
    if ( $self->config->download_version ) {
        $self->shared->{download_version} = $self->config->download_version;
        $self->shared->{download}         = 2
          if $self->shared->{download} == 1;    # Change default 1 -> 2
        $self->badversion(1);
        uscan_verbose "Download the --download-version specified version: "
          . "$self->{shared}->{download_version}";
    }
    elsif ( $self->config->download_debversion ) {
        $self->shared->{download_version} = $mangled_lastversion;
        $self->shared->{download}         = 2
          if $self->shared->{download} == 1;    # Change default 1 -> 2
        $self->badversion(1);
        uscan_verbose "Download the --download-debversion specified version "
          . "(dversionmangled): $self->{shared}->{download_version}";
    }
    elsif ( $self->config->download_current_version ) {
        $self->shared->{download_version} = $mangled_lastversion;
        $self->shared->{download}         = 2
          if $self->shared->{download} == 1;    # Change default 1 -> 2
        $self->badversion(1);
        uscan_verbose
          "Download the --download-current-version specified version: "
          . "$self->{shared}->{download_version}";
    }
    elsif ( $self->versionmode eq 'same' ) {
        unless ( defined $self->shared->{common_newversion} ) {
            uscan_warn
"Unable to set versionmode=prev for the line without opts=pgpmode=prev\n"
              . "  in $watchfile, skipping:\n"
              . "  $self->{line}";
            return $self->status(1);
        }
        $self->shared->{download_version} = $self->shared->{common_newversion};
        $self->shared->{download}         = 2
          if $self->shared->{download} == 1;    # Change default 1 -> 2
        $self->badversion(1);
        uscan_verbose "Download secondary tarball with the matching version: "
          . "$self->{shared}->{download_version}";
    }
    elsif ( $self->versionmode eq 'previous' ) {
        unless ( $self->pgpmode eq 'previous'
            and defined $self->shared->{previous_newversion} )
        {
            uscan_warn
"Unable to set versionmode=prev for the line without opts=pgpmode=prev\n"
              . "  in $watchfile, skipping:\n  $self->{line}";
            return $self->status(1);
        }
        $self->shared->{download_version} =
          $self->shared->{previous_newversion};
        $self->shared->{download} = 2
          if $self->shared->{download} == 1;    # Change default 1 -> 2
        $self->badversion(1);
        uscan_verbose
          "Download the signature file with the previous tarball's version:"
          . " $self->{shared}->{download_version}";
    }
    else {
        # $options{'versionmode'} should be debian or ignore
        if ( defined $self->shared->{download_version} ) {
            uscan_die
              "\$download_version defined after dversionmangle ... strange";
        }
        else {
            uscan_verbose "Last orig.tar.* tarball version (dversionmangled):"
              . " $mangled_lastversion";
        }
    }

    if ( $self->watch_version != 1 ) {
        if ( $self->mode eq 'http' or $self->mode eq 'ftp' ) {
            if ( $base =~ m%^(\w+://[^/]+)% ) {
                $site = $1;
            }
            else {
                uscan_warn "Can't determine protocol and site in\n"
                  . "  $watchfile, skipping:\n"
                  . "  $self->{line}";
                return $self->status(1);
            }

            # Find the path with the greatest version number matching the regex
            $base =
              recursive_regex_dir( $self->downloader, $base,
                $self->dirversionmangle, $watchfile, \$self->line,
                $self->shared->{download_version} );
            if ( $base eq '' ) {
                return $self->status(1);
            }

            # We're going to make the pattern
            # (?:(?:http://site.name)?/dir/path/)?base_pattern
            # It's fine even for ftp sites
            $basedir = $base;
            $basedir =~ s%^\w+://[^/]+/%/%;
            $pattern = "(?:(?:$site)?" . quotemeta($basedir) . ")?$filepattern";
        }
        else {
            # git tag match is simple
            $site    = $base;          # dummy
            $basedir = '';             # dummy
            $pattern = $filepattern;
        }
    }

    push @{ $self->sites },    $site;
    push @{ $self->basedirs }, $basedir;
    push @{ $self->patterns }, $pattern;

    my $match = '';

# Start Checking $site and look for $filepattern which is newer than $lastversion
    uscan_debug "watch file has:\n"
      . "    \$base        = $base\n"
      . "    \$filepattern = $filepattern\n"
      . "    \$lastversion = $lastversion\n"
      . "    \$action      = $action\n"
      . "    mode         = $self->{mode}\n"
      . "    pgpmode      = $self->{pgpmode}\n"
      . "    versionmode  = $self->{versionmode}\n"
      . "    \$site        = $site\n"
      . "    \$basedir     = $basedir";

    $self->parse_result(
        {
            base                => $base,
            filepattern         => $filepattern,
            lastversion         => $lastversion,
            action              => $action,
            site                => $site,
            basedir             => $basedir,
            mangled_lastversion => $mangled_lastversion,
            pattern             => $pattern,
        }
    );

# What is the most recent file, based on the filenames?
# We first have to find the candidates, then we sort them using
# Devscripts::Versort::upstream_versort (if it is real upstream version string) or
# Devscripts::Versort::versort (if it is suffixed upstream version string)
    return $self->status;
}

# II - search
=head3 search()

Search new file link and new version on the remote site using either:

=over

=item L<Devscripts::Uscan::http>::http_search()
=item L<Devscripts::Uscan::ftp>::ftp_search()
=item L<Devscripts::Uscan::git>::git_search()

=back

It populates B<$self-E<gt>search_result> hash ref with the following keys:

=over

=item B<newversion>: URL/tag pointing to the file to be downloaded
=item B<newfile>: version number to be used for the downloaded file

=back

=cut

sub search {
    my ($self) = @_;
    uscan_debug "line: search()";
    my ( $newversion, $newfile ) = $self->_do('search');
    unless ( $newversion and $newfile ) {
        return $self->status(1);
    }
    $self->status and return $self->status;
    uscan_verbose "Looking at \$base = $self->{parse_result}->{base} with\n"
      . "    \$filepattern = $self->{parse_result}->{filepattern} found\n"
      . "    \$newfile     = $newfile\n"
      . "    \$newversion  = $newversion which is newer than\n"
      . "    \$lastversion = $self->{parse_result}->{lastversion}";
    $self->search_result(
        {
            newversion => $newversion,
            newfile    => $newfile,
        }
    );

    # The original version of the code didn't use (...) in the watch
    # file to delimit the version number; thus if there is no (...)
    # in the pattern, we will use the old heuristics, otherwise we
    # use the new.

    if ( $self->style eq 'old' ) {

        # Old-style heuristics
        if ( $newversion =~ /^\D*(\d+\.(?:\d+\.)*\d+)\D*$/ ) {
            $newversion = $1;
        }
        else {
            uscan_warn <<"EOF";
$progname warning: In $self->{watchfile}, couldn\'t determine a
  pure numeric version number from the file name for watch line
  $self->{line}
  and file name $newfile
  Please use a new style watch file instead!
EOF
            $self->status(1);
        }
    }
    return $self->status;
}

# III - get_upstream_url
=head3 get_upstream_url()

Transform newfile/newversion into upstream url using either:

=over

=item L<Devscripts::Uscan::http>::http_upstream_url()
=item L<Devscripts::Uscan::ftp>::ftp_upstream_url()
=item L<Devscripts::Uscan::git>::git_upstream_url()

=back

Result is stored in B<$self-E<gt>upstream_url> accessor.

=cut

sub get_upstream_url {
    my ($self) = @_;
    uscan_debug "line: get_upstream_url()";
    if ( $self->parse_result->{site} =~ m%^https?://%
        and not $self->mode eq 'git' )
    {
        $self->mode('http');
    }
    elsif ( not $self->mode ) {
        $self->mode('ftp');
    }
    $self->upstream_url( $self->_do('upstream_url') );
    $self->status and return $self->status;
    uscan_verbose "Upstream URL(+tag) to download is identified as"
      . "    $self->{upstream_url}";
    return $self->status;
}

# IV - get_newfile_base
=head3 get_newfile_base()

Calculates the filename (filenamemangled) for downloaded file using either:

=over

=item L<Devscripts::Uscan::http>::http_newfile_base()
=item L<Devscripts::Uscan::ftp>::ftp_newfile_base()
=item L<Devscripts::Uscan::git>::git_newfile_base()

=back

Result is stored in B<$self-E<gt>newfile_base> accessor.

=cut

sub get_newfile_base {
    my ($self) = @_;
    uscan_debug "line: get_newfile_base()";
    $self->newfile_base( $self->_do('newfile_base') );
    return $self->status if ( $self->status );
    uscan_verbose
      "Filename (filenamemangled) for downloaded file: $self->{newfile_base}";
    return $self->status;
}

# V - cmp_versions
=head3 cmp_versions()

Compare available and local versions.

=cut

sub cmp_versions {
    my ($self) = @_;
    uscan_debug "line: cmp_versions()";
    my $mangled_lastversion = $self->parse_result->{mangled_lastversion};
    unless ( defined $self->shared->{common_newversion} ) {
        $self->shared->{common_newversion} = $self->search_result->{newversion};
    }

    $dehs_tags->{'debian-uversion'} = $self->parse_result->{lastversion};
    $dehs_tags->{'debian-mangled-uversion'} = $mangled_lastversion;
    $dehs_tags->{'upstream-version'} = $self->search_result->{newversion};
    $dehs_tags->{'upstream-url'}     = $self->upstream_url;

    my $mangled_ver =
      Dpkg::Version->new( "1:${mangled_lastversion}-0", check => 0 );
    my $upstream_ver =
      Dpkg::Version->new( "1:$self->{search_result}->{newversion}-0",
        check => 0 );
    my $compver;
    if ( $mangled_ver == $upstream_ver ) {
        $compver = 'same';
    }
    elsif ( $mangled_ver > $upstream_ver ) {
        $compver = 'older';
    }
    else {
        $compver = 'newer';
    }

    # Version dependent $download adjustment
    if ( defined $self->shared->{download_version} ) {

        # Pretend to find a newer upstream version to exit without error
        uscan_msg "Newest version of $self->{pkg} on remote site is "
          . "$self->{search_result}->{newversion}, "
          . "specified download version is $self->{shared}->{download_version}";
        $main::found++;
    }
    elsif ( $self->versionmode eq 'newer' ) {
        if ( $compver eq 'newer' ) {
            uscan_msg "Newest version of $self->{pkg} on remote site is "
              . "$self->{search_result}->{newversion}, "
              . "local version is $self->{parse_result}->{lastversion}\n"
              . (
                $mangled_lastversion eq $self->parse_result->{lastversion}
                ? ""
                : " (mangled local version is $mangled_lastversion)\n"
              );

            # There's a newer upstream version available, which may already
            # be on our system or may not be
            uscan_msg "   => Newer package available from\n"
              . "      $self->{upstream_url}";
            $dehs_tags->{'status'} = "newer package available";
            $main::found++;
        }
        elsif ( $compver eq 'same' ) {
            uscan_verbose "Newest version of $self->{pkg} on remote site is "
              . $self->search_result->{newversion}
              . ", local version is $self->{parse_result}->{lastversion}\n"
              . (
                $mangled_lastversion eq $self->parse_result->{lastversion}
                ? ""
                : " (mangled local version is $mangled_lastversion)\n"
              );
            uscan_verbose "   => Package is up to date for from\n"
              . "      $self->{upstream_url}";
            $dehs_tags->{'status'} = "up to date";
            if ( $self->shared->{download} > 1 ) {

                # 2=force-download or 3=overwrite-download
                uscan_verbose "   => Forcing download as requested";
                $main::found++;
            }
            else {
                # 0=no-download or 1=download
                $self->shared->{download} = 0;
            }
        }
        else {    # $compver eq 'old'
            uscan_verbose "Newest version of $self->{pkg} on remote site is "
              . $self->search_result->{newversion}
              . ", local version is $self->{parse_result}->{lastversion}\n"
              . (
                $mangled_lastversion eq $self->parse_result->{lastversion}
                ? ""
                : " (mangled local version is $mangled_lastversion)\n"
              );
            uscan_verbose "   => Only older package available from\n"
              . "      $self->{upstream_url}";
            $dehs_tags->{'status'} = "only older package available";
            if ( $self->shared->{download} > 1 ) {
                uscan_verbose "   => Forcing download as requested";
                $main::found++;
            }
            else {
                $self->shared->{download} = 0;
            }
        }
    }
    elsif ( $self->versionmode eq 'ignore' ) {
        uscan_msg "Newest version of $self->{pkg} on remote site is "
          . $self->search_result->{newversion}
          . ", ignore local version";
        $dehs_tags->{'status'} = "package available";
        $main::found++;
    }
    else {    # same/previous -- secondary-tarball or signature-file
        uscan_die "strange ... <version> stanza = same/previous "
          . "should have defined \$download_version";
    }
    return 0;
}

# VI - download_file_and_sig
=head3 download_file_and_sig()

Download file and, if available and needed, signature files.

=cut

sub download_file_and_sig {
    my ($self) = @_;
    uscan_debug "line: download_file_and_sig()";
    my $skip_git_vrfy;

    # If we're not downloading or performing signature verification, we can
    # stop here
    if ( !$self->shared->{download} || $self->shared->{signature} == -1 ) {
        return 0;
    }

    # 6.1 download tarball
    my $download_available = 0;
    $self->signature_available(0);
    my $sigfile;
    my $sigfile_base = $self->newfile_base;
    if ( $self->pgpmode ne 'previous' ) {

        # try download package
        if ( $self->shared->{download} == 3
            and -e "$self->{config}->{destdir}/$self->{newfile_base}" )
        {
            uscan_verbose
"Downloading and overwriting existing file: $self->{newfile_base}";
            $download_available = $self->downloader->download(
                $self->upstream_url,
                "$self->{config}->{destdir}/$self->{newfile_base}",
                $self,
                $self->parse_result->{base},
                $self->pkg_dir,
                $self->mode
            );
            if ($download_available) {
                dehs_verbose
                  "Successfully downloaded package: $self->{newfile_base}\n";
            }
            else {
                dehs_verbose
"Failed to download upstream package: $self->{newfile_base}\n";
            }
        }
        elsif ( -e "$self->{config}->{destdir}/$self->{newfile_base}" ) {
            $download_available = 1;
            dehs_verbose
              "Not downloading, using existing file: $self->{newfile_base}\n";
            $skip_git_vrfy = 1;
        }
        elsif ( $self->shared->{download} > 0 ) {
            uscan_verbose "Downloading upstream package: $self->{newfile_base}";
            $download_available = $self->downloader->download(
                $self->upstream_url,
                "$self->{config}->{destdir}/$self->{newfile_base}",
                $self,
                $self->parse_result->{base},
                $self->pkg_dir,
                $self->mode,
            );
            if ($download_available) {
                dehs_verbose
                  "Successfully downloaded package: $self->{newfile_base}\n";
            }
            else {
                dehs_verbose
"Failed to download upstream package: $self->{newfile_base}\n";
            }
        }
        else {    # $download = 0,
            $download_available = 0;
            dehs_verbose
              "Not downloading upstream package: $self->{newfile_base}\n";
        }
    }
    if ( $self->pgpmode eq 'self' ) {
        $sigfile_base =~ s/^(.*?)\.[^\.]+$/$1/;    # drop .gpg, .asc, ...
        if ( $self->shared->{signature} == -1 ) {
            uscan_warn("SKIP Checking OpenPGP signature (by request).\n");
            $download_available =
              -1;    # can't proceed with self-signature archive
            $self->signature_available(0);
        }
        elsif ( !$self->keyring ) {
            uscan_die("FAIL Checking OpenPGP signature (no keyring).\n");
        }
        elsif ( $download_available == 0 ) {
            uscan_warn
"FAIL Checking OpenPGP signature (no signed upstream tarball downloaded).";
            return $self->status(1);
        }
        else {
            $self->keyring->verify(
                "$self->{config}->{destdir}/$sigfile_base",
                "$self->{config}->{destdir}/$self->{newfile_base}"
            );

# XXX FIXME XXX extract signature as detached signature to $self->{config}->{destdir}/$sigfile
            $sigfile = $self->{newfile_base};    # XXX FIXME XXX place holder
            $self->{newfile_base} = $sigfile_base;
            $self->signature_available(3);
        }
    }
    if ( $self->pgpmode ne 'previous' ) {

        # Decompress archive if requested and applicable
        if ( $download_available == 1 and $self->{'decompress'} ) {
            my $suffix_gz = $sigfile_base;
            $suffix_gz =~ s/.*?(\.gz|\.xz|\.bz2|\.lzma)?$/$1/;
            if ( $suffix_gz eq '.gz' ) {
                if ( -x '/bin/gunzip' ) {
                    uscan_exec( '/bin/gunzip', "--keep",
                        "$self->{config}->{destdir}/$sigfile_base" );
                    $sigfile_base =~ s/(.*?)\.gz/$1/;
                }
                else {
                    uscan_warn("Please install gzip.\n");
                    return $self->status(1);
                }
            }
            elsif ( $suffix_gz eq '.xz' ) {
                if ( -x '/usr/bin/unxz' ) {
                    uscan_exec( '/usr/bin/unxz', "--keep",
                        "$self->{config}->{destdir}/$sigfile_base" );
                    $sigfile_base =~ s/(.*?)\.xz/$1/;
                }
                else {
                    uscan_warn("Please install xz-utils.\n");
                    return $self->status(1);
                }
            }
            elsif ( $suffix_gz eq '.bz2' ) {
                if ( -x '/bin/bunzip2' ) {
                    uscan_exec( '/bin/bunzip2', "--keep",
                        "$self->{config}->{destdir}/$sigfile_base" );
                    $sigfile_base =~ s/(.*?)\.bz2/$1/;
                }
                else {
                    uscan_warn("Please install bzip2.\n");
                    return $self->status(1);
                }
            }
            elsif ( $suffix_gz eq '.lzma' ) {
                if ( -x '/usr/bin/unlzma' ) {
                    uscan_exec( '/usr/bin/unlzma', "--keep",
                        "$self->{config}->{destdir}/$sigfile_base" );
                    $sigfile_base =~ s/(.*?)\.lzma/$1/;
                }
                else {
                    uscan_warn "Please install xz-utils or lzma.";
                    return $self->status(1);
                }
            }
            else {
                uscan_warn "Unknown type file to decompress: $sigfile_base";
                exit 1;
            }
        }
    }

    # 6.2 download signature
    my $pgpsig_url;
    my $suffix_sig;
    if ( ( $self->pgpmode eq 'default' or $self->pgpmode eq 'auto' )
        and $self->shared->{signature} == 1 )
    {
        uscan_verbose
          "Start checking for common possible upstream OpenPGP signature files";
        foreach $suffix_sig (qw(asc gpg pgp sig sign)) {
            my $sigrequest =
              HTTP::Request->new(
                'HEAD' => "$self->{upstream_url}.$suffix_sig" );
            my $sigresponse =
              $self->downloader->user_agent->request($sigrequest);
            if ( $sigresponse->is_success() ) {
                if ( $self->pgpmode eq 'default' ) {
                    uscan_warn "Possible OpenPGP signature found at:\n"
                      . "   $self->{upstream_url}.$suffix_sig\n"
                      . " * Add opts=pgpsigurlmangle=s/\$/.$suffix_sig/ or "
                      . "opts=pgpmode=auto to debian/watch\n"
                      . " * Add debian/upstream/signing-key.asc.\n"
                      . " See uscan(1) for more details";
                    $self->pgpmode('none');
                }
                else {    # auto
                    $self->pgpmode('mangle');
                    $self->pgpsigurlmangle( [ 's/$/.' . $suffix_sig . '/', ] );
                }
                last;
            }
        }
        uscan_verbose
          "End checking for common possible upstream OpenPGP signature files";
        $self->signature_available(0);
    }
    if ( $self->pgpmode eq 'mangle' ) {
        $pgpsig_url = $self->upstream_url;
        if (
            mangle(
                $self->watchfile,   \$self->line,
                'pgpsigurlmangle:', \@{ $self->pgpsigurlmangle },
                \$pgpsig_url
            )
          )
        {
            return $self->status(1);
        }
        if ( !$suffix_sig ) {
            $suffix_sig = $pgpsig_url;
            $suffix_sig =~ s/^.*\.//;
            if ( $suffix_sig and $suffix_sig !~ m/^[a-zA-Z]+$/ )
            {    # strange suffix
                $suffix_sig = "pgp";
            }
            uscan_debug "Add $suffix_sig suffix based on $pgpsig_url.";
        }
        $sigfile = "$sigfile_base.$suffix_sig";
        if ( $self->shared->{signature} == 1 ) {
            uscan_verbose "Downloading OpenPGP signature from\n"
              . "   $pgpsig_url (pgpsigurlmangled)\n   as $sigfile";
            $self->signature_available(
                $self->downloader->download(
                    $pgpsig_url,    "$self->{config}->{destdir}/$sigfile",
                    $self,          $self->parse_result->{base},
                    $self->pkg_dir, $self->mode
                )
            );
        }
        else {    # -1, 0
            uscan_verbose "Not downloading OpenPGP signature from\n"
              . "   $pgpsig_url (pgpsigurlmangled)\n   as $sigfile";
            $self->signature_available(
                ( -e "$self->{config}->{destdir}/$sigfile" ) ? 1 : 0 );
        }
    }
    elsif ( $self->pgpmode eq 'previous' ) {
        $pgpsig_url = $self->upstream_url;
        $sigfile    = $self->newfile_base;
        if ( $self->shared->{signature} == 1 ) {
            uscan_verbose "Downloading OpenPGP signature from\n"
              . "   $pgpsig_url (pgpmode=previous)\n   as $sigfile";
            $self->signature_available(
                $self->downloader->download(
                    $pgpsig_url,    "$self->{config}->{destdir}/$sigfile",
                    $self,          $self->parse_result->{base},
                    $self->pkg_dir, $self->mode
                )
            );
        }
        else {    # -1, 0
            uscan_verbose "Not downloading OpenPGP signature from\n"
              . "   $pgpsig_url (pgpmode=previous)\n   as $sigfile";
            $self->signature_available(
                ( -e "$self->{config}->{destdir}/$sigfile" ) ? 1 : 0 );
        }
        $download_available   = $self->shared->{previous_download_available};
        $self->{newfile_base} = $self->shared->{previous_newfile_base};
        $sigfile_base         = $self->shared->{previous_sigfile_base};
        uscan_verbose
          "Use $self->{newfile_base} as upstream package (pgpmode=previous)";
    }

    # 6.3 verify signature
    #
    # 6.3.1 pgpmode
    if ( $self->pgpmode eq 'mangle' or $self->pgpmode eq 'previous' ) {
        if ( $self->shared->{signature} == -1 ) {
            uscan_verbose("SKIP Checking OpenPGP signature (by request).\n");
        }
        elsif ( !$self->keyring ) {
            uscan_die("FAIL Checking OpenPGP signature (no keyring).\n");
        }
        elsif ( $download_available == 0 ) {
            uscan_warn
"FAIL Checking OpenPGP signature (no upstream tarball downloaded).";
            return $self->status(1);
        }
        elsif ( $self->signature_available == 0 ) {
            uscan_die(
"FAIL Checking OpenPGP signature (no signature file downloaded).\n"
            );
        }
        else {
            if ( $self->shared->{signature} == 0 ) {
                uscan_verbose "Use the existing file: $sigfile";
            }
            $self->keyring->verifyv(
                "$self->{config}->{destdir}/$sigfile",
                "$self->{config}->{destdir}/$sigfile_base"
            );
        }
        $self->shared->{previous_newfile_base}       = undef;
        $self->shared->{previous_sigfile_base}       = undef;
        $self->shared->{previous_newversion}         = undef;
        $self->shared->{previous_download_available} = undef;
    }
    elsif ( $self->pgpmode eq 'none' or $self->pgpmode eq 'default' ) {
        uscan_verbose "Missing OpenPGP signature.";
        $self->shared->{previous_newfile_base}       = undef;
        $self->shared->{previous_sigfile_base}       = undef;
        $self->shared->{previous_newversion}         = undef;
        $self->shared->{previous_download_available} = undef;
    }
    elsif ( $self->pgpmode eq 'next' ) {
        uscan_verbose "Defer checking OpenPGP signature to the next watch line";
        $self->shared->{previous_newfile_base} = $self->newfile_base;
        $self->shared->{previous_sigfile_base} = $sigfile_base;
        $self->shared->{previous_newversion} =
          $self->search_result->{newversion};
        $self->shared->{previous_download_available} = $download_available;
        uscan_verbose "previous_newfile_base = $self->{newfile_base}";
        uscan_verbose "previous_sigfile_base = $sigfile_base";
        uscan_verbose
          "previous_newversion = $self->{search_result}->{newversion}";
        uscan_verbose "previous_download_available = $download_available";
    }
    elsif ( $self->pgpmode eq 'self' ) {
        $self->shared->{previous_newfile_base}       = undef;
        $self->shared->{previous_sigfile_base}       = undef;
        $self->shared->{previous_newversion}         = undef;
        $self->shared->{previous_download_available} = undef;
    }
    elsif ( $self->pgpmode eq 'auto' ) {
        uscan_verbose "Don't check OpenPGP signature";
    }
    elsif ( $self->pgpmode eq 'gittag' ) {
        if ($skip_git_vrfy) {
            uscan_warn "File already downloaded, skipping gpg verification";
        }
        elsif ( !$self->keyring ) {
            uscan_warn "No keyring file, skipping gpg verification";
            return $self->status(1);
        }
        else {
            my ( $gitrepo, $gitref ) = split /[[:space:]]+/,
              $self->upstream_url;
            $self->keyring->verify_git( $self->pkg . "-temporary.$$.git",
                $gitref );
        }
    }
    else {
        uscan_warn "strange ... unknown pgpmode = $self->{pgpmode}";
        return $self->status(1);
    }
    my $mangled_newversion = $self->search_result->{newversion};
    if (
        mangle(
            $self->watchfile,  \$self->line,
            'oversionmangle:', \@{ $self->oversionmangle },
            \$mangled_newversion
        )
      )
    {
        return $self->status(1);
    }

    if ( !$self->shared->{common_mangled_newversion} ) {

   # $mangled_newversion = version used for the new orig.tar.gz (a.k.a oversion)
        uscan_verbose
"New orig.tar.* tarball version (oversionmangled): $mangled_newversion";

      # MUT package always use the same $common_mangled_newversion
      # MUT disables repacksuffix so it is safe to have this before mk-origtargz
        $self->shared->{common_mangled_newversion} = $mangled_newversion;
    }
    if ( $self->pgpmode eq 'next' ) {
        uscan_verbose "Read the next watch line (pgpmode=next)";
        return 0;
    }
    if ( $self->safe ) {
        uscan_verbose "SKIP generation of orig.tar.* "
          . "and running of script/uupdate (--safe)";
        return 0;
    }
    if ( $download_available == 0 ) {
        uscan_warn "No upstream tarball downloaded."
          . " No further processing with mk_origtargz ...";
        return $self->status(1);
    }
    if ( $download_available == -1 ) {
        uscan_warn "No upstream tarball unpacked from self signature file."
          . " No further processing with mk_origtargz ...";
        return $self->status(1);
    }
    if ( $self->signature_available == 1 and $self->decompress ) {
        $self->signature_available(2);
    }
    $self->search_result->{sigfile} = $sigfile;
    $self->must_download(1);
    return $self->status;
}

# VII - mkorigtargz
=head3 mkorigtargz()

Call L<mk_origtargz> to build source tarball.

=cut

sub mkorigtargz {
    my ($self) = @_;
    uscan_debug "line: mkorigtargz()";
    return 0 unless ( $self->must_download );
    my $mk_origtargz_out;
    my $path   = "$self->{config}->{destdir}/$self->{newfile_base}";
    my $target = $self->newfile_base;
    unless ( $self->symlink eq "no" ) {
        my @cmd = ("mk-origtargz");
        push @cmd, "--package", $self->pkg;
        push @cmd, "--version", $self->shared->{common_mangled_newversion};
        push @cmd, '--repack-suffix', $self->repacksuffix
          if $self->repacksuffix;
        push @cmd, "--rename" if $self->symlink eq "rename";
        push @cmd, "--copy"   if $self->symlink eq "copy";
        push @cmd, "--signature", $self->signature_available
          if ( $self->signature_available != 0 );
        push @cmd, "--signature-file",
          "$self->{config}->{destdir}/$self->{search_result}->{sigfile}"
          if ( $self->signature_available != 0 );
        push @cmd, "--repack" if $self->repack;
        push @cmd, "--component", $self->component
          if $self->component;
        push @cmd, "--compression",    $self->compression;
        push @cmd, "--directory",      $self->config->destdir;
        push @cmd, "--copyright-file", "debian/copyright"
          if ( $self->config->exclusion && -e "debian/copyright" );
        push @cmd, "--copyright-file", $self->config->copyright_file
          if ( $self->config->exclusion && $self->config->copyright_file );
        push @cmd, "--unzipopt", $self->unzipopt
          if $self->unzipopt;
        push @cmd, $path;

        my $actioncmd = join( " ", @cmd );
        uscan_verbose "Executing internal command:\n   $actioncmd";
        spawn(
            exec       => \@cmd,
            to_string  => \$mk_origtargz_out,
            wait_child => 1
        );
        chomp($mk_origtargz_out);
        $path = $1
          if $mk_origtargz_out =~
          /Successfully .* (?:to|as) ([^,]+)(?:,.*)?\.$/;
        $path = $1 if $mk_origtargz_out =~ /Leaving (.*) where it is/;
        $target = basename($path);
        $self->shared->{common_mangled_newversion} = $1
          if $target =~ m/[^_]+_(.+)\.orig(?:-.+)?\.tar\.(?:gz|bz2|lzma|xz)$/;
        uscan_verbose "New orig.tar.* tarball version (after mk-origtargz): "
          . "$self->{shared}->{common_mangled_newversion}";
    }
    push @{ $self->shared->{origtars} }, $target;

    if ( $self->config->log ) {

        # Check pkg-ver.tar.gz and pkg_ver.orig.tar.gz
        if ( !$self->shared->{uscanlog} ) {
            $self->shared->{uscanlog} =
"$self->{config}->{destdir}/$self->{pkg}_$self->{shared}->{common_mangled_newversion}.uscan.log";
            if ( -e "$self->{shared}->{uscanlog}.old" ) {
                unlink "$self->{shared}->{uscanlog}.old"
                  or uscan_die "Can\'t remove old backup log "
                  . "$self->{shared}->{uscanlog}.old: $!";
                uscan_warn "Old backup uscan log found. "
                  . "Remove: $self->{shared}->{uscanlog}.old";
            }
            if ( -e $self->shared->uscanlog ) {
                move( $self->shared->uscanlog,
                    "$self->{shared}->{uscanlog}.old" );
                uscan_warn "Old uscan log found. "
                  . "Moved to: $self->{shared}->{uscanlog}.old";
            }
            open( USCANLOG, ">> $self->{shared}->{uscanlog}" )
              or uscan_die "$progname: could not open "
              . "$self->{shared}->{uscanlog} for append: $!";
            print USCANLOG "# uscan log\n";
        }
        else {
            open( USCANLOG, ">> $self->{shared}->{uscanlog}" )
              or uscan_die "$progname: could not open "
              . "$self->{shared}->{uscanlog} for append: $!";
        }
        if ( $self->symlink ne "rename" ) {
            my $umd5sum = Digest::MD5->new;
            my $omd5sum = Digest::MD5->new;
            open( my $ufh, '<',
                "$self->{config}->{destdir}/$self->{newfile_base}" )
              or uscan_die "Can't open '"
              . "$self->{config}->{destdir}/$self->{newfile_base}" . "': $!";
            open( my $ofh, '<', "$self->{config}->{destdir}/${target}" )
              or uscan_die
              "Can't open '$self->{config}->{destdir}/${target}': $!";
            $umd5sum->addfile($ufh);
            $omd5sum->addfile($ofh);
            close($ufh);
            close($ofh);
            my $umd5hex = $umd5sum->hexdigest;
            my $omd5hex = $omd5sum->hexdigest;

            if ( $umd5hex eq $omd5hex ) {
                print USCANLOG
                  "# == $self->{newfile_base}\t-->\t${target}\t(same)\n";
            }
            else {
                print USCANLOG
                  "# !! $self->{newfile_base}\t-->\t${target}\t(changed)\n";
            }
            print USCANLOG "$umd5hex  $self->{newfile_base}\n";
            print USCANLOG "$omd5hex  ${target}\n";
        }
        close USCANLOG
          or uscan_die
          "$progname: could not close $self->{shared}->{uscanlog} $!";
    }

    dehs_verbose "$mk_origtargz_out\n" if $mk_origtargz_out;
    $dehs_tags->{target} = $target;
    $dehs_tags->{'target-path'} = $path;

#######################################################################
    # code 3.10: call uupdate
#######################################################################
    # Do whatever the user wishes to do
    if ( $self->parse_result->{action} ) {
        my @cmd = shellwords( $self->parse_result->{action} );

        # script invocation changed in $watch_version=4
        if ( $self->watch_version > 3 ) {
            if ( $cmd[0] eq "uupdate" ) {
                push @cmd, "-f";
                if ($verbose) {
                    push @cmd, "--verbose";
                }
                if ( $self->badversion ) {
                    push @cmd, "-b";
                }
            }
            push @cmd, "--upstream-version",
              $self->shared->{common_mangled_newversion};
            if ( abs_path( $self->{config}->{destdir} ) ne abs_path("..") ) {
                foreach my $origtar ( @{ $self->shared->{origtars} } ) {
                    copy( catfile( $self->{config}->{destdir}, $origtar ),
                        catfile( "..", $origtar ) );
                }
            }
        }
        elsif ( $self->watch_version > 1 ) {

            # Any symlink requests are already handled by uscan
            if ( $cmd[0] eq "uupdate" ) {
                push @cmd, "--no-symlink";
                if ($verbose) {
                    push @cmd, "--verbose";
                }
                if ( $self->badversion ) {
                    push @cmd, "-b";
                }
            }
            push @cmd, "--upstream-version",
              $self->shared->{common_mangled_newversion}, $path;
        }
        else {
            push @cmd, $path, $self->shared->{common_mangled_newversion};
        }
        my $actioncmd = join( " ", @cmd );
        my $actioncmdmsg;
        spawn( exec => \@cmd, wait_child => 1, to_string => \$actioncmdmsg );
        local $, = ' ';
        dehs_verbose "Executing user specified script:\n   @cmd\n"
          . $actioncmdmsg;
    }

    return 0;
}

# VIII - clean
=head3 clean()

Clean temporary files using either:

=over

=item L<Devscripts::Uscan::http>::http_clean()
=item L<Devscripts::Uscan::ftp>::ftp_clean()
=item L<Devscripts::Uscan::git>::git_clean()

=back

=cut

sub clean {
    my ($self) = @_;
    $self->_do('clean');
}

# Internal sub to call sub modules (git, http,...)
sub _do {
    my ( $self, $sub ) = @_;
    my $mode = $self->mode;
    $mode =~ s/git-dumb/git/;
    $sub = $mode . "_$sub";
    eval "use Devscripts::Uscan::$mode" unless ( $self->can($sub) );
    if ($@) {
        uscan_warn "Unknown '$mode' mode set in $self->{watchfile} ($@)";
        $self->status(1);
    }
    return $self->$sub;
}

1;

=head1 SEE ALSO

L<uscan>, L<Devscripts::Uscan::WatchFile>, L<Devscripts::Uscan::Config>

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
