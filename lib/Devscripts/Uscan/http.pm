package Devscripts::Uscan::http;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Exporter qw(import);
use Devscripts::Uscan::_xtp;

our @EXPORT = qw(http_search http_upstream_url http_newfile_base http_clean
  html_search parse_href);

*http_newfile_base = \&Devscripts::Uscan::_xtp::_xtp_newfile_base;

##################################
# search $newversion (http mode)
##################################
sub http_search {
    my ($self) = @_;

    # $content: web page to be scraped to find the URLs to be downloaded
    if ( defined($1) and $self->downloader->ssl ) {
        uscan_die
"you must have the liblwp-protocol-https-perl package installed\nto use https URLs";
    }
    uscan_verbose "Requesting URL:\n   $self->{parse_result}->{base}";
    my $request = HTTP::Request->new( 'GET', $self->parse_result->{base} );
    my $response = $self->downloader->user_agent->request($request);
    if ( !$response->is_success ) {
        uscan_warn
"In watchfile $self->{watchfile}, reading webpage\n  $self->{parse_result}->{base} failed: "
          . $response->status_line;
        return undef;
    }

    my @redirections = @{ $self->downloader->user_agent->get_redirections };

    uscan_verbose "redirections: @redirections" if @redirections;

    foreach my $_redir (@redirections) {
        my $base_dir = $_redir;

        $base_dir =~ s%^\w+://[^/]+/%/%;
        if ( $_redir =~ m%^(\w+://[^/]+)% ) {
            my $base_site = $1;

            push @{ $self->patterns },
                "(?:(?:$base_site)?"
              . quotemeta($base_dir)
              . ")?$self->{parse_result}->{filepattern}";
            push @{ $self->sites },    $base_site;
            push @{ $self->basedirs }, $base_dir;

            # remove the filename, if any
            my $base_dir_orig = $base_dir;
            $base_dir =~ s%/[^/]*$%/%;
            if ( $base_dir ne $base_dir_orig ) {
                push @{ $self->patterns },
                    "(?:(?:$base_site)?"
                  . quotemeta($base_dir)
                  . ")?$self->{parse_result}->{filepattern}";
                push @{ $self->sites },    $base_site;
                push @{ $self->basedirs }, $base_dir;
            }
        }
    }

    my $content = $response->decoded_content;
    uscan_debug
      "received content:\n$content\n[End of received content] by HTTP";

    my @hrefs = $self->html_search($content);
    if (@hrefs) {
        @hrefs = Devscripts::Versort::versort(@hrefs);
        my $msg =
"Found the following matching hrefs on the web page (newest first):\n";
        foreach my $href (@hrefs) {
            $msg .= "   $$href[2] ($$href[1]) index=$$href[0] $$href[3]\n";
        }
        uscan_verbose $msg;
    }
    my ( $newversion, $newfile );
    if ( defined $self->shared->{download_version} ) {

        # extract ones which has $match in the above loop defined
        my @vhrefs = grep { $$_[3] } @hrefs;
        if (@vhrefs) {
            ( undef, $newversion, $newfile, undef ) = @{ $vhrefs[0] };
        }
        else {
            uscan_warn
"In $self->{watchfile} no matching hrefs for version $self->{shared}->{download_version}"
              . " in watch line\n  $self->{line}";
            return undef;
        }
    }
    else {
        if (@hrefs) {
            ( undef, $newversion, $newfile, undef ) = @{ $hrefs[0] };
        }
        else {
            uscan_warn
"In $self->{watchfile} no matching files for watch line\n  $self->{line}";
            return undef;
        }
    }
    return ( $newversion, $newfile );
}

#######################################################################
# determine $upstream_url (http mode)
#######################################################################
# http is complicated due to absolute/relative URL issue
sub http_upstream_url {
    my ($self) = @_;
    my $upstream_url;
    my $newfile = $self->search_result->{newfile};
    if ( $newfile =~ m%^\w+://% ) {
        $upstream_url = $newfile;
    }
    elsif ( $newfile =~ m%^//% ) {
        $upstream_url = $self->parse_result->{site};
        $upstream_url =~ s/^(https?:).*/$1/;
        $upstream_url .= $newfile;
    }
    elsif ( $newfile =~ m%^/% ) {

        # absolute filename
        # Were there any redirections? If so try using those first
        if ( $#{ $self->patterns } > 0 ) {

            # replace $site here with the one we were redirected to
            foreach my $index ( 0 .. $#{ $self->patterns } ) {
                if ( "$self->{sites}->[$index]$newfile" =~
                    m&^$self->{patterns}->[$index]$& )
                {
                    $upstream_url = "$self->{sites}->[$index]$newfile";
                    last;
                }
            }
            if ( !defined($upstream_url) ) {
                uscan_verbose
                  "Unable to determine upstream url from redirections,\n"
                  . "defaulting to using site specified in watch file";
                $upstream_url = "$self->{sites}->[0]$newfile";
            }
        }
        else {
            $upstream_url = "$self->{sites}->[0]$newfile";
        }
    }
    else {
        # relative filename, we hope
        # Were there any redirections? If so try using those first
        if ( $#{ $self->patterns } > 0 ) {

            # replace $site here with the one we were redirected to
            foreach my $index ( 0 .. $#{ $self->patterns } ) {

                # skip unless the basedir looks like a directory
                next unless $self->{basedirs}->[$index] =~ m%/$%;
                my $nf = "$self->{basedirs}->[$index]$newfile";
                if ( "$self->{sites}->[$index]$nf" =~
                    m&^$self->{patterns}->[$index]$& )
                {
                    $upstream_url = "$self->{sites}->[$index]$nf";
                    last;
                }
            }
            if ( !defined($upstream_url) ) {
                uscan_verbose
                  "Unable to determine upstream url from redirections,\n"
                  . "defaulting to using site specified in watch file";
                $upstream_url = "$self->{parse_result}->{urlbase}$newfile";
            }
        }
        else {
            $upstream_url = "$self->{parse_result}->{urlbase}$newfile";
        }
    }

    # mangle if necessary
    $upstream_url =~ s/&amp;/&/g;
    uscan_verbose "Matching target for downloadurlmangle: $upstream_url";
    if ( @{ $self->downloadurlmangle } ) {
        if (
            mangle(
                $self->watchfile,     \$self->line,
                'downloadurlmangle:', \@{ $self->downloadurlmangle },
                \$upstream_url
            )
          )
        {
            $self->status(1);
            return undef;
        }
    }
    return $upstream_url;
}

sub http_newdir {
    my (
        $https,     $downloader, $site,
        $dir,       $pattern,    $dirversionmangle,
        $watchfile, $lineptr,    $download_version
    ) = @_;

    my ( $request, $response, $newdir );
    my ( $download_version_short1, $download_version_short2,
        $download_version_short3 )
      = partial_version($download_version);
    my $base = $site . $dir;

    if ( defined($https) and !$downloader->ssl ) {
        uscan_die
"$progname: you must have the liblwp-protocol-https-perl package installed\n"
          . "to use https URLs";
    }
    $request = HTTP::Request->new( 'GET', $base );
    $response = $downloader->user_agent->request($request);
    if ( !$response->is_success ) {
        uscan_warn
          "In watch file $watchfile, reading webpage\n  $base failed: "
          . $response->status_line;
        return '';
    }

    my $content = $response->content;
    uscan_debug
      "received content:\n$content\n[End of received content] by HTTP";

    clean_content( \$content );

    my $dirpattern = "(?:(?:$site)?" . quotemeta($dir) . ")?$pattern";

    uscan_verbose "Matching pattern:\n   $dirpattern";
    my @hrefs;
    my $match = '';
    while ( $content =~ m/<\s*a\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/gi ) {
        my $href = fix_href($2);
        uscan_verbose "Matching target for dirversionmangle:   $href";
        if ( $href =~ m&^$dirpattern/?$& ) {
            my $mangled_version =
              join( ".", map { $_ // '' } $href =~ m&^$dirpattern/?$& );
            if (
                mangle(
                    $watchfile,          $lineptr,
                    'dirversionmangle:', \@{$dirversionmangle},
                    \$mangled_version
                )
              )
            {
                return 1;
            }
            $match = '';
            if ( defined $download_version
                and $mangled_version eq $download_version )
            {
                $match = "matched with the download version";
            }
            if ( defined $download_version_short3
                and $mangled_version eq $download_version_short3 )
            {
                $match = "matched with the download version (partial 3)";
            }
            if ( defined $download_version_short2
                and $mangled_version eq $download_version_short2 )
            {
                $match = "matched with the download version (partial 2)";
            }
            if ( defined $download_version_short1
                and $mangled_version eq $download_version_short1 )
            {
                $match = "matched with the download version (partial 1)";
            }
            push @hrefs, [ $mangled_version, $href, $match ];
        }
    }

    # extract ones which has $match in the above loop defined
    my @vhrefs = grep { $$_[2] } @hrefs;
    if (@vhrefs) {
        @vhrefs = Devscripts::Versort::upstream_versort(@vhrefs);
        $newdir = $vhrefs[0][1];
    }
    if (@hrefs) {
        @hrefs = Devscripts::Versort::upstream_versort(@hrefs);
        my $msg = "Found the following matching directories (newest first):\n";
        foreach my $href (@hrefs) {
            $msg .= "   $$href[1] ($$href[0]) $$href[2]\n";
        }
        uscan_verbose $msg;
        $newdir //= $hrefs[0][1];
    }
    else {
        uscan_warn
"In $watchfile,\n  no matching hrefs for pattern\n  $site$dir$pattern";
        return '';
    }

    # just give the final directory component
    $newdir =~ s%/$%%;
    $newdir =~ s%^.*/%%;
    return ($newdir);
}

# Nothing to clean here
sub http_clean { 0 }

sub clean_content {
    my ($content) = @_;

    # We need this horrid stuff to handle href=foo type
    # links.  OK, bad HTML, but we have to handle it nonetheless.
    # It's bug #89749.
    $$content =~ s/href\s*=\s*(?=[^\"\'])([^\s>]+)/href="$1"/ig;

    # Strip comments
    $$content =~ s/<!-- .*?-->//sg;
    return $content;
}

sub html_search {
    my ( $self, $content ) = @_;

    # pagenmangle: should not abuse this slow operation
    if (
        mangle(
            $self->watchfile, \$self->line,
            'pagemangle:\n', [ @{ $self->pagemangle } ],
            \$content
        )
      )
    {
        return undef;
    }
    if (   !$self->shared->{bare}
        and $content =~ m%^<[?]xml%i
        and $content =~ m%xmlns="http://s3.amazonaws.com/doc/2006-03-01/"%
        and $content !~ m%<Key><a\s+href% )
    {
     # this is an S3 bucket listing.  Insert an 'a href' tag
     # into the content for each 'Key', so that it looks like html (LP: #798293)
        uscan_warn
"*** Amazon AWS special case code is deprecated***\nUse opts=pagemangle rule, instead";
        $content =~ s%<Key>([^<]*)</Key>%<Key><a href="$1">$1</a></Key>%g;
        uscan_debug
"processed content:\n$content\n[End of processed content] by Amazon AWS special case code";
    }
    clean_content( \$content );

    # Is there a base URL given?
    if ( $content =~ /<\s*base\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/i ) {

        # Ensure it ends with /
        $self->parse_result->{urlbase} = "$2/";
        $self->parse_result->{urlbase} =~ s%//$%/%;
    }
    else {
        # May have to strip a base filename
        ( $self->parse_result->{urlbase} = $self->parse_result->{base} ) =~
          s%/[^/]*$%/%;
    }
    uscan_debug
"processed content:\n$content\n[End of processed content] by fix bad HTML code";

# search hrefs in web page to obtain a list of uversionmangled version and matching download URL
    {
        local $, = ',';
        uscan_verbose "Matching pattern:\n   @{$self->{patterns}}";
    }
    my @hrefs;
    while ( $content =~ m/<\s*a\s+[^>]*(?<=\s)href\s*=\s*([\"\'])(.*?)\1/sgi ) {
        my $href = $2;
        $href = fix_href($href);
        if ( defined $self->hrefdecode ) {
            if ( $self->hrefdecode eq 'percent-encoding' ) {
                uscan_debug "... Decoding from href: $href";
                $href =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg;
            }
            else {
                uscan_warn "Illegal value for hrefdecode: "
                  . "$self->{hrefdecode}";
                return undef;
            }
        }
        uscan_debug "Checking href $href";
        foreach my $_pattern ( @{ $self->patterns } ) {
            if ( $href =~ /^$_pattern$/ ) {
                push @hrefs, $self->parse_href( $href, $_pattern, $1 );
            }
        }
    }
    return @hrefs;
}

sub parse_href {
    my ( $self, $href, $_pattern, $match ) = @_;
    my $mangled_version;
    if ( $self->watch_version == 2 ) {

        # watch_version 2 only recognised one group; the code
        # below will break version 2 watch files with a construction
        # such as file-([\d\.]+(-\d+)?) (bug #327258)
        $mangled_version = $match;
    }
    else {
        # need the map { ... } here to handle cases of (...)?
        # which may match but then return undef values
        if ( $self->versionless ) {

            # exception, otherwise $mangled_version = 1
            $mangled_version = '';
        }
        else {
            $mangled_version =
              join( ".", map { $_ if defined($_) } $href =~ m&^$_pattern$& );
        }

        if (
            mangle(
                $self->watchfile,  \$self->line,
                'uversionmangle:', \@{ $self->uversionmangle },
                \$mangled_version
            )
          )
        {
            return ();
        }
    }
    my $match = '';
    if ( defined $self->shared->{download_version} ) {
        if ( $mangled_version eq $self->shared->{download_version} ) {
            $match = "matched with the download version";
        }
    }
    my $priority = $mangled_version . '-' . get_priority($href);
    return [ $priority, $mangled_version, $href, $match ];
}

1;
