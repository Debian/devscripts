package Devscripts::Uscan::ftp;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::_xtp;
use Moo::Role;

#######################################################################
# search $newfile $newversion (ftp mode)
#######################################################################
sub ftp_search {
    my ($self) = @_;

    # FTP site
    uscan_verbose "Requesting URL:\n   $self->{parse_result}->{base}";
    my $request  = HTTP::Request->new('GET', $self->parse_result->{base});
    my $response = $self->downloader->user_agent->request($request);
    if (!$response->is_success) {
        uscan_warn
"In watch file $self->{watchfile}, reading FTP directory\n  $self->{parse_result}->{base} failed: "
          . $response->status_line . "";
        return undef;
    }

    my $content = $response->content;
    uscan_debug
      "received content:\n$content\n[End of received content] by FTP";

    # FTP directory listings either look like:
    # info info ... info filename [ -> linkname]
    # or they're HTMLised (if they've been through an HTTP proxy)
    # so we may have to look for <a href="filename"> type patterns
    uscan_verbose "matching pattern $self->{parse_result}->{pattern}";
    my (@files);

    # We separate out HTMLised listings from standard listings, so
    # that we can target our search correctly
    if ($content =~ /<\s*a\s+[^>]*href/i) {
        uscan_verbose "HTMLized FTP listing by the HTTP proxy";
        while ($content
            =~ m/(?:<\s*a\s+[^>]*href\s*=\s*\")((?-i)$self->{parse_result}->{pattern})\"/gi
        ) {
            my $file = fix_href($1);
            my $mangled_version
              = join(".", $file =~ m/^$self->{parse_result}->{pattern}$/);
            if (
                mangle(
                    $self->watchfile,  \$self->line,
                    'uversionmangle:', \@{ $self->uversionmangle },
                    \$mangled_version
                )
            ) {
                return undef;
            }
            my $match = '';
            if (defined $self->shared->{download_version}) {
                if ($mangled_version eq $self->shared->{download_version}) {
                    $match = "matched with the download version";
                }
            }
            my $priority = $mangled_version . '-' . get_priority($file);
            push @files, [$priority, $mangled_version, $file, $match];
        }
    } else {
        uscan_verbose "Standard FTP listing.";

        # they all look like:
        # info info ... info filename [ -> linkname]
        for my $ln (split(/\n/, $content)) {
            $ln =~ s/^d.*$//;            # FTP listing of directory, '' skipped
            $ln =~ s/\s+->\s+\S+$//;     # FTP listing for link destination
            $ln =~ s/^.*\s(\S+)$/$1/;    # filename only
            if ($ln and $ln =~ m/^($self->{parse_result}->{filepattern})$/) {
                my $file            = $1;
                my $mangled_version = join(".",
                    $file =~ m/^$self->{parse_result}->{filepattern}$/);
                if (
                    mangle(
                        $self->watchfile,  \$self->line,
                        'uversionmangle:', \@{ $self->uversionmangle },
                        \$mangled_version
                    )
                ) {
                    return undef;
                }
                my $match = '';
                if (defined $self->shared->{download_version}) {
                    if ($mangled_version eq $self->shared->{download_version})
                    {
                        $match = "matched with the download version";
                    }
                }
                my $priority = $mangled_version . '-' . get_priority($file);
                push @files, [$priority, $mangled_version, $file, $match];
            }
        }
    }
    if (@files) {
        @files = Devscripts::Versort::versort(@files);
        my $msg
          = "Found the following matching files on the web page (newest first):\n";
        foreach my $file (@files) {
            $msg .= "   $$file[2] ($$file[1]) index=$$file[0] $$file[3]\n";
        }
        uscan_verbose $msg;
    }
    my ($newversion, $newfile);
    if (defined $self->shared->{download_version}) {

        # extract ones which has $match in the above loop defined
        my @vfiles = grep { $$_[3] } @files;
        if (@vfiles) {
            (undef, $newversion, $newfile, undef) = @{ $vfiles[0] };
        } else {
            uscan_warn
"In $self->{watchfile} no matching files for version $self->{shared}->{download_version}"
              . " in watch line\n  $self->{line}";
            return undef;
        }
    } else {
        if (@files) {
            (undef, $newversion, $newfile, undef) = @{ $files[0] };
        } else {
            uscan_warn
"In $self->{watchfile} no matching files for watch line\n  $self->{line}";
            return undef;
        }
    }
    return ($newversion, $newfile);
}

sub ftp_upstream_url {
    my ($self) = @_;
    return $self->parse_result->{base} . $self->search_result->{newfile};
}

*ftp_newfile_base = \&Devscripts::Uscan::_xtp::_xtp_newfile_base;

sub ftp_newdir {
    my ($downloader, $site, $dir, $pattern, $dirversionmangle, $watchfile,
        $lineptr, $download_version)
      = @_;

    my ($request, $response, $newdir);
    my ($download_version_short1, $download_version_short2,
        $download_version_short3)
      = partial_version($download_version);
    my $base = $site . $dir;
    $request  = HTTP::Request->new('GET', $base);
    $response = $downloader->user_agent->request($request);
    if (!$response->is_success) {
        uscan_warn
          "In watch file $watchfile, reading webpage\n  $base failed: "
          . $response->status_line;
        return '';
    }

    my $content = $response->content;
    uscan_debug
      "received content:\n$content\n[End of received content] by FTP";

    # FTP directory listings either look like:
    # info info ... info filename [ -> linkname]
    # or they're HTMLised (if they've been through an HTTP proxy)
    # so we may have to look for <a href="filename"> type patterns
    uscan_verbose "matching pattern $pattern";
    my (@dirs);
    my $match = '';

    # We separate out HTMLised listings from standard listings, so
    # that we can target our search correctly
    if ($content =~ /<\s*a\s+[^>]*href/i) {
        uscan_verbose "HTMLized FTP listing by the HTTP proxy";
        while (
            $content =~ m/(?:<\s*a\s+[^>]*href\s*=\s*\")((?-i)$pattern)\"/gi) {
            my $dir = $1;
            uscan_verbose "Matching target for dirversionmangle:   $dir";
            my $mangled_version = join(".", $dir =~ m/^$pattern$/);
            if (
                mangle(
                    $watchfile,          $lineptr,
                    'dirversionmangle:', \@{$dirversionmangle},
                    \$mangled_version
                )
            ) {
                return 1;
            }
            $match = '';
            if (defined $download_version
                and $mangled_version eq $download_version) {
                $match = "matched with the download version";
            }
            if (defined $download_version_short3
                and $mangled_version eq $download_version_short3) {
                $match = "matched with the download version (partial 3)";
            }
            if (defined $download_version_short2
                and $mangled_version eq $download_version_short2) {
                $match = "matched with the download version (partial 2)";
            }
            if (defined $download_version_short1
                and $mangled_version eq $download_version_short1) {
                $match = "matched with the download version (partial 1)";
            }
            push @dirs, [$mangled_version, $dir, $match];
        }
    } else {
        # they all look like:
        # info info ... info filename [ -> linkname]
        uscan_verbose "Standard FTP listing.";
        foreach my $ln (split(/\n/, $content)) {
            $ln =~ s/^-.*$//;            # FTP listing of file, '' skipped
            $ln =~ s/\s+->\s+\S+$//;     # FTP listing for link destination
            $ln =~ s/^.*\s(\S+)$/$1/;    # filename only
            if ($ln =~ m/^($pattern)(\s+->\s+\S+)?$/) {
                my $dir = $1;
                uscan_verbose "Matching target for dirversionmangle:   $dir";
                my $mangled_version = join(".", $dir =~ m/^$pattern$/);
                if (
                    mangle(
                        $watchfile,          $lineptr,
                        'dirversionmangle:', \@{$dirversionmangle},
                        \$mangled_version
                    )
                ) {
                    return 1;
                }
                $match = '';
                if (defined $download_version
                    and $mangled_version eq $download_version) {
                    $match = "matched with the download version";
                }
                if (defined $download_version_short3
                    and $mangled_version eq $download_version_short3) {
                    $match = "matched with the download version (partial 3)";
                }
                if (defined $download_version_short2
                    and $mangled_version eq $download_version_short2) {
                    $match = "matched with the download version (partial 2)";
                }
                if (defined $download_version_short1
                    and $mangled_version eq $download_version_short1) {
                    $match = "matched with the download version (partial 1)";
                }
                push @dirs, [$mangled_version, $dir, $match];
            }
        }
    }

    # extract ones which has $match in the above loop defined
    my @vdirs = grep { $$_[2] } @dirs;
    if (@vdirs) {
        @vdirs  = Devscripts::Versort::upstream_versort(@vdirs);
        $newdir = $vdirs[0][1];
    }
    if (@dirs) {
        @dirs = Devscripts::Versort::upstream_versort(@dirs);
        my $msg
          = "Found the following matching FTP directories (newest first):\n";
        foreach my $dir (@dirs) {
            $msg .= "   $$dir[1] ($$dir[0]) $$dir[2]\n";
        }
        uscan_verbose $msg;
        $newdir //= $dirs[0][1];
    } else {
        uscan_warn
          "In $watchfile no matching dirs for pattern\n  $base$pattern";
        $newdir = '';
    }
    return $newdir;
}

# Nothing to clean here
sub ftp_clean { 0 }

1;
