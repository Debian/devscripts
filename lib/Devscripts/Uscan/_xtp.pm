# Common sub shared between http and ftp
package Devscripts::Uscan::_xtp;

use strict;
use File::Basename;
use Exporter 'import';
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;

our @EXPORT = ('partial_version');

sub _xtp_newfile_base {
    my ($self) = @_;
    my $newfile_base;
    if (@{ $self->filenamemangle }) {

        # HTTP or FTP site (with filenamemangle)
        if ($self->versionless) {
            $newfile_base = $self->upstream_url;
        } else {
            $newfile_base = $self->search_result->{newfile};
        }
        uscan_verbose "Matching target for filenamemangle: $newfile_base";
        if (
            mangle(
                $self->watchfile,  \$self->line,
                'filenamemangle:', \@{ $self->filenamemangle },
                \$newfile_base
            )
        ) {
            $self->status(1);
            return undef;
        }
        unless ($self->search_result->{newversion}) {

            # uversionmanglesd version is '', make best effort to set it
            $newfile_base
              =~ m/^.+?[-_]?(\d[\-+\.:\~\da-zA-Z]*)(?:\.tar\.(gz|bz2|xz)|\.zip)$/i;
            $self->search_result->{newversion} = $1;
            unless ($self->search_result->{newversion}) {
                uscan_warn
"Fix filenamemangle to produce a filename with the correct version";
                $self->status(1);
                return undef;
            }
            uscan_verbose
"Newest upstream tarball version from the filenamemangled filename: $self->{search_result}->{newversion}";
        }
    } else {
        # HTTP or FTP site (without filenamemangle)
        $newfile_base = basename($self->search_result->{newfile});
        if ($self->mode eq 'http') {

            # Remove HTTP header trash
            $newfile_base =~ s/[\?#].*$//;    # PiPy
                 # just in case this leaves us with nothing
            if ($newfile_base eq '') {
                uscan_warn
"No good upstream filename found after removing tailing ?... and #....\n   Use filenamemangle to fix this.";
                $self->status(1);
                return undef;
            }
        }
    }
    return $newfile_base;
}

sub partial_version {
    my ($download_version) = @_;
    my ($d1, $d2, $d3);
    if (defined $download_version) {
        uscan_verbose "download version requested: $download_version";
        if ($download_version
            =~ m/^([-~\+\w]+)(\.[-~\+\w]+)?(\.[-~\+\w]+)?(\.[-~\+\w]+)?$/) {
            $d1 = "$1"     if defined $1;
            $d2 = "$1$2"   if defined $2;
            $d3 = "$1$2$3" if defined $3;
        }
    }
    return ($d1, $d2, $d3);
}

1;
