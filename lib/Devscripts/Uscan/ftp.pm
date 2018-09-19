package Devscripts::Uscan::ftp;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Exporter qw(import);
use Devscripts::Uscan::_xtp;

our @EXPORT = qw(ftp_search ftp_upstream_url ftp_newfile_base);

#######################################################################
# search $newfile $newversion (ftp mode)
#######################################################################
sub ftp_search {
    my ($self) = @_;

    # FTP site
    if ( $self->downloader->passive ) {
        $ENV{'FTP_PASSIVE'} = $self->downloader->passive;
    }
    uscan_verbose "Requesting URL:\n   $self->{parse_result}->{base}\n";
    my $request = HTTP::Request->new( 'GET', $self->parse_result->{base} );
    my $response = $self->downloader->user_agent->request($request);
    if ( $self->downloader->passive ) {
        $ENV{'FTP_PASSIVE'} = $self->downloader->passive;
    }
    else {
        delete $ENV{'FTP_PASSIVE'};
    }
    if ( !$response->is_success ) {
        uscan_warn
"In watch file $self->{watchfile}, reading FTP directory\n  $self->{parse_result}->{base} failed: "
          . $response->status_line . "\n";
        return undef;
    }

    my $content = $response->content;
    uscan_debug
      "received content:\n$content\n[End of received content] by FTP\n";

    # FTP directory listings either look like:
    # info info ... info filename [ -> linkname]
    # or they're HTMLised (if they've been through an HTTP proxy)
    # so we may have to look for <a href="filename"> type patterns
    uscan_verbose "matching pattern $self->{parse_result}->{pattern}\n";
    my (@files);

    # We separate out HTMLised listings from standard listings, so
    # that we can target our search correctly
    if ( $content =~ /<\s*a\s+[^>]*href/i ) {
        uscan_verbose "HTMLized FTP listing by the HTTP proxy\n";
        while ( $content =~
m/(?:<\s*a\s+[^>]*href\s*=\s*\")((?-i)$self->{parse_result}->{pattern})\"/gi
          )
        {
            my $file = fix_href($1);
            my $mangled_version =
              join( ".", $file =~ m/^$self->{parse_result}->{pattern}$/ );
            if (
                mangle(
                    $self->watchfile,  \$self->line,
                    'uversionmangle:', \@{ $self->uversionmangle },
                    \$mangled_version
                )
              )
            {
                return undef;
            }
            my $match = '';
            if ( defined $self->shared->{download_version} ) {
                if ( $mangled_version eq $self->shared->{download_version} ) {
                    $match = "matched with the download version";
                }
            }
            my $priority = $mangled_version . '-' . get_priority($file);
            push @files, [ $priority, $mangled_version, $file, $match ];
        }
    }
    else {
        uscan_verbose "Standard FTP listing.\n";

        # they all look like:
        # info info ... info filename [ -> linkname]
        for my $ln ( split( /\n/, $content ) ) {
            $ln =~
              s/^d.*$//;    # FTP listing of directory, '' skiped by if ($ln...
            $ln =~ s/\s+->\s+\S+$//;     # FTP listing for link destination
            $ln =~ s/^.*\s(\S+)$/$1/;    # filename only
            if ( $ln and $ln =~ m/^($self->{parse_result}->{filepattern})$/ ) {
                my $file            = $1;
                my $mangled_version = join( ".",
                    $file =~ m/^$self->{parse_result}->{filepattern}$/ );
                if (
                    mangle(
                        $self->watchfile,  \$self->line,
                        'uversionmangle:', \@{ $self->uversionmangle },
                        \$mangled_version
                    )
                  )
                {
                    return undef;
                }
                my $match = '';
                if ( defined $self->shared->{download_version} ) {
                    if ( $mangled_version eq $self->shared->{download_version} )
                    {
                        $match = "matched with the download version";
                    }
                }
                my $priority = $mangled_version . '-' . get_priority($file);
                push @files, [ $priority, $mangled_version, $file, $match ];
            }
        }
    }
    if (@files) {
        @files = Devscripts::Versort::versort(@files);
        my $msg =
"Found the following matching files on the web page (newest first):\n";
        foreach my $file (@files) {
            $msg .= "   $$file[2] ($$file[1]) index=$$file[0] $$file[3]\n";
        }
        uscan_verbose $msg;
    }
    my ( $newversion, $newfile );
    if ( defined $self->shared->{download_version} ) {

        # extract ones which has $match in the above loop defined
        my @vfiles = grep { $$_[3] } @files;
        if (@vfiles) {
            ( undef, $newversion, $newfile, undef ) = @{ $vfiles[0] };
        }
        else {
            uscan_warn
"In $self->{watchfile} no matching files for version $self->{shared}->{download_version}"
              . " in watch line\n  $self->{line}\n";
            return undef;
        }
    }
    else {
        if (@files) {
            ( undef, $newversion, $newfile, undef ) = @{ $files[0] };
        }
        else {
            uscan_warn
"In $self->{watchfile} no matching files for watch line\n  $self->{line}\n";
            return undef;
        }
    }
    return ( $newversion, $newfile );
}

sub ftp_upstream_url {
    my ($self) = @_;
    return $self->parse_result->{base} . $self->search_result->{newfile};
}

*ftp_newfile_base = \&Devscripts::Uscan::_xtp::_xtp_newfile_base;

1;
