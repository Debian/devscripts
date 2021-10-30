package Devscripts::Uscan::http;

use strict;
use Cwd qw/abs_path/;
use Devscripts::Uscan::Output;
use Devscripts::Uscan::Utils;
use Devscripts::Uscan::_xtp;
use Moo::Role;

*http_newfile_base = \&Devscripts::Uscan::_xtp::_xtp_newfile_base;

##################################
# search $newversion (http mode)
##################################

#returns (\@patterns, \@base_sites, \@base_dirs)
sub handle_redirection {
    my ($self, $pattern, @additional_bases) = @_;
    my @redirections = @{ $self->downloader->user_agent->get_redirections };
    my (@patterns, @base_sites, @base_dirs);

    uscan_verbose "redirections: @redirections" if @redirections;

    foreach my $_redir (@redirections, @additional_bases) {
        my $base_dir = $_redir;

        $base_dir =~ s%^\w+://[^/]+/%/%;
        $base_dir =~ s%/[^/]*(?:[#?].*)?$%/%;
        if ($_redir =~ m%^(\w+://[^/]+)%) {
            my $base_site = $1;

            push @patterns,
              quotemeta($base_site) . quotemeta($base_dir) . "$pattern";
            push @base_sites, $base_site;
            push @base_dirs,  $base_dir;

            # remove the filename, if any
            my $base_dir_orig = $base_dir;
            $base_dir =~ s%/[^/]*$%/%;
            if ($base_dir ne $base_dir_orig) {
                push @patterns,
                  quotemeta($base_site) . quotemeta($base_dir) . "$pattern";
                push @base_sites, $base_site;
                push @base_dirs,  $base_dir;
            }
        }
    }
    return (\@patterns, \@base_sites, \@base_dirs);
}

sub http_search {
    my ($self) = @_;

    # $content: web page to be scraped to find the URLs to be downloaded
    if ($self->{parse_result}->{base} =~ /^https/ and !$self->downloader->ssl)
    {
        uscan_die
"you must have the liblwp-protocol-https-perl package installed\nto use https URLs";
    }
    uscan_verbose "Requesting URL:\n   $self->{parse_result}->{base}";
    my $request = HTTP::Request->new('GET', $self->parse_result->{base});
    foreach my $k (keys %{ $self->downloader->headers }) {
        if ($k =~ /^(.*?)@(.*)$/) {
            my $baseUrl = $1;
            my $hdr     = $2;
            if ($self->parse_result->{base} =~ m#^\Q$baseUrl\E(?:/.*)?$#) {
                $request->header($hdr => $self->headers->{$k});
                uscan_verbose "Set per-host custom header $hdr for "
                  . $self->parse_result->{base};
            } else {
                uscan_debug
                  "$self->parse_result->{base} does not start with $1";
            }
        } else {
            uscan_warn "Malformed http-header: $k";
        }
    }
    $request->header('Accept-Encoding' => 'gzip');
    $request->header('Accept'          => '*/*');
    my $response = $self->downloader->user_agent->request($request);
    if (!$response->is_success) {
        uscan_warn
"In watchfile $self->{watchfile}, reading webpage\n  $self->{parse_result}->{base} failed: "
          . $response->status_line;
        return undef;
    }

    my ($patterns, $base_sites, $base_dirs)
      = handle_redirection($self, $self->{parse_result}->{filepattern});
    push @{ $self->patterns }, @$patterns;
    push @{ $self->sites },    @$base_sites;
    push @{ $self->basedirs }, @$base_dirs;

    my $content = $response->decoded_content;
    uscan_extra_debug
      "received content:\n$content\n[End of received content] by HTTP";

    my @hrefs;
    if (!$self->searchmode or $self->searchmode eq 'html') {
        @hrefs = $self->html_search($content, $self->patterns);
    } elsif ($self->searchmode eq 'plain') {
        @hrefs = $self->plain_search($content);
    } else {
        uscan_warn 'Unknown searchmode "' . $self->searchmode . '", skipping';
        return undef;
    }

    if (@hrefs) {
        @hrefs = Devscripts::Versort::versort(@hrefs);
        my $msg
          = "Found the following matching hrefs on the web page (newest first):\n";
        foreach my $href (@hrefs) {
            $msg .= "   $$href[2] ($$href[1]) index=$$href[0] $$href[3]\n";
        }
        uscan_verbose $msg;
    }
    my ($newversion, $newfile);
    if (defined $self->shared->{download_version}
        and not $self->versionmode eq 'ignore') {

        # extract ones which has $match in the above loop defined
        my @vhrefs = grep { $$_[3] } @hrefs;
        if (@vhrefs) {
            (undef, $newversion, $newfile, undef) = @{ $vhrefs[0] };
        } else {
            uscan_warn
"In $self->{watchfile} no matching hrefs for version $self->{shared}->{download_version}"
              . " in watch line\n  $self->{line}";
            return undef;
        }
    } else {
        if (@hrefs) {
            (undef, $newversion, $newfile, undef) = @{ $hrefs[0] };
        } else {
            uscan_warn
"In $self->{watchfile} no matching files for watch line\n  $self->{line}";
            return undef;
        }
    }
    return ($newversion, $newfile);
}

#######################################################################
# determine $upstream_url (http mode)
#######################################################################
# http is complicated due to absolute/relative URL issue
sub http_upstream_url {
    my ($self) = @_;
    my $upstream_url;
    my $newfile = $self->search_result->{newfile};
    if ($newfile =~ m%^\w+://%) {
        $upstream_url = $newfile;
    } elsif ($newfile =~ m%^//%) {
        $upstream_url = $self->parse_result->{site};
        $upstream_url =~ s/^(https?:).*/$1/;
        $upstream_url .= $newfile;
    } elsif ($newfile =~ m%^/%) {

        # absolute filename
        # Were there any redirections? If so try using those first
        if ($#{ $self->patterns } > 0) {

            # replace $site here with the one we were redirected to
            foreach my $index (0 .. $#{ $self->patterns }) {
                if ("$self->{sites}->[$index]$newfile"
                    =~ m&^$self->{patterns}->[$index]$&) {
                    $upstream_url = "$self->{sites}->[$index]$newfile";
                    last;
                }
            }
            if (!defined($upstream_url)) {
                uscan_verbose
                  "Unable to determine upstream url from redirections,\n"
                  . "defaulting to using site specified in watch file";
                $upstream_url = "$self->{sites}->[0]$newfile";
            }
        } else {
            $upstream_url = "$self->{sites}->[0]$newfile";
        }
    } else {
        # relative filename, we hope
        # Were there any redirections? If so try using those first
        if ($#{ $self->patterns } > 0) {

            # replace $site here with the one we were redirected to
            foreach my $index (0 .. $#{ $self->patterns }) {

                # skip unless the basedir looks like a directory
                next unless $self->{basedirs}->[$index] =~ m%/$%;
                my $nf = "$self->{basedirs}->[$index]$newfile";
                if ("$self->{sites}->[$index]$nf"
                    =~ m&^$self->{patterns}->[$index]$&) {
                    $upstream_url = "$self->{sites}->[$index]$nf";
                    last;
                }
            }
            if (!defined($upstream_url)) {
                uscan_verbose
                  "Unable to determine upstream url from redirections,\n"
                  . "defaulting to using site specified in watch file";
                $upstream_url = "$self->{parse_result}->{urlbase}$newfile";
            }
        } else {
            $upstream_url = "$self->{parse_result}->{urlbase}$newfile";
        }
    }

    # mangle if necessary
    $upstream_url =~ s/&amp;/&/g;
    uscan_verbose "Matching target for downloadurlmangle: $upstream_url";
    if (@{ $self->downloadurlmangle }) {
        if (
            mangle(
                $self->watchfile,     \$self->line,
                'downloadurlmangle:', \@{ $self->downloadurlmangle },
                \$upstream_url
            )
        ) {
            $self->status(1);
            return undef;
        }
    }
    return $upstream_url;
}

sub http_newdir {
    my ($https, $line, $site, $dir, $pattern, $dirversionmangle,
        $watchfile, $lineptr, $download_version)
      = @_;

    my $downloader = $line->downloader;
    my ($request, $response, $newdir);
    my ($download_version_short1, $download_version_short2,
        $download_version_short3)
      = partial_version($download_version);
    my $base = $site . $dir;

    $pattern .= "/?";

    if (defined($https) and !$downloader->ssl) {
        uscan_die
"$progname: you must have the liblwp-protocol-https-perl package installed\n"
          . "to use https URLs";
    }
    # At least for now, set base in the line object - other methods need it
    local $line->parse_result->{base} = $base;
    $request  = HTTP::Request->new('GET', $base);
    $response = $downloader->user_agent->request($request);
    if (!$response->is_success) {
        uscan_warn
          "In watch file $watchfile, reading webpage\n  $base failed: "
          . $response->status_line;
        return '';
    }

    my $content = $response->content;
    if (    $response->header('Content-Encoding')
        and $response->header('Content-Encoding') =~ /^gzip$/i) {
        require IO::Uncompress::Gunzip;
        require IO::String;
        uscan_debug "content seems gzip encoded, let's decode it";
        my $out;
        if (IO::Uncompress::Gunzip::gunzip(IO::String->new($content), \$out)) {
            $content = $out;
        } else {
            uscan_warn 'Unable to decode remote content: '
              . $IO::Uncompress::GunzipError;
            return '';
        }
    }
    uscan_extra_debug
      "received content:\n$content\n[End of received content] by HTTP";

    clean_content(\$content);

    my ($dirpatterns, $base_sites, $base_dirs)
      = handle_redirection($line, $pattern, $base);
    $downloader->user_agent->clear_redirections;    # we won't be needing that

    my @hrefs;
    for my $parsed (
        html_search($line, $content, $dirpatterns, 'dirversionmangle')) {
        my ($priority, $mangled_version, $href, $match) = @$parsed;
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
        push @hrefs, [$mangled_version, $href, $match];
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
    } else {
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

sub url_canonicalize_dots {
    my ($base, $url) = @_;

    if ($url !~ m{^[^:#?/]+://}) {
        if ($url =~ m{^//}) {
            $base =~ m{^[^:#?/]+:}
              and $url = $& . $url;
        } elsif ($url =~ m{^/}) {
            $base =~ m{^[^:#?/]+://[^/#?]*}
              and $url = $& . $url;
        } else {
            uscan_debug "Resolving urls with query part unimplemented"
              if ($url =~ m/^[#?]/);
            $base =~ m{^[^:#?/]+://[^/#?]*(?:/(?:[^#?/]*/)*)?} and do {
                my $base_to_path = $&;
                $base_to_path .= '/' unless $base_to_path =~ m|/$|;
                $url = $base_to_path . $url;
            };
        }
    }
    $url =~ s{^([^:#?/]+://[^/#?]*)(/[^#?]*)}{
       my ($h, $p) = ($1, $2);
       $p =~ s{/\.(?:/|$|(?=[#?]))}{/}g;
       1 while $p =~ s{/(?!\.\./)[^/]*/\.\.(?:/|(?=[#?])|$)}{/}g;
       $h.$p;}e;
    $url;
}

sub html_search {
    my ($self, $content, $patterns, $mangle) = @_;

    # pagenmangle: should not abuse this slow operation
    if (
        mangle(
            $self->watchfile, \$self->line,
            'pagemangle:\n',  [@{ $self->pagemangle }],
            \$content
        )
    ) {
        return undef;
    }
    if (   !$self->shared->{bare}
        and $content =~ m%^<[?]xml%i
        and $content =~ m%xmlns="http://s3.amazonaws.com/doc/2006-03-01/"%
        and $content !~ m%<Key><a\s+href%) {
    # this is an S3 bucket listing.  Insert an 'a href' tag
    # into the content for each 'Key', so that it looks like html (LP: #798293)
        uscan_warn
"*** Amazon AWS special case code is deprecated***\nUse opts=pagemangle rule, instead";
        $content =~ s%<Key>([^<]*)</Key>%<Key><a href="$1">$1</a></Key>%g;
        uscan_extra_debug
"processed content:\n$content\n[End of processed content] by Amazon AWS special case code";
    }
    clean_content(\$content);

    # Is there a base URL given?
    if ($content =~ /<\s*base\s+[^>]*href\s*=\s*([\"\'])(.*?)\1/i) {
        $self->parse_result->{urlbase}
          = url_canonicalize_dots($self->parse_result->{base}, $2);
    } else {
        $self->parse_result->{urlbase} = $self->parse_result->{base};
    }
    uscan_extra_debug
"processed content:\n$content\n[End of processed content] by fix bad HTML code";

# search hrefs in web page to obtain a list of uversionmangled version and matching download URL
    {
        local $, = ',';
        uscan_verbose "Matching pattern:\n   @{$self->{patterns}}";
    }
    my @hrefs;
    while ($content =~ m/<\s*a\s+[^>]*(?<=\s)href\s*=\s*([\"\'])(.*?)\1/sgi) {
        my $href = $2;
        $href = fix_href($href);
        my $href_canonical
          = url_canonicalize_dots($self->parse_result->{urlbase}, $href);
        if (defined $self->hrefdecode) {
            if ($self->hrefdecode eq 'percent-encoding') {
                uscan_debug "... Decoding from href: $href";
                $href           =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg;
                $href_canonical =~ s/%([A-Fa-f\d]{2})/chr hex $1/eg;
            } else {
                uscan_warn "Illegal value for hrefdecode: "
                  . "$self->{hrefdecode}";
                return undef;
            }
        }
        uscan_extra_debug "Checking href $href";
        foreach my $_pattern (@$patterns) {
            if (my @match = $href =~ /^$_pattern$/) {
                push @hrefs,
                  parse_href($self, $href_canonical, $_pattern, \@match,
                    $mangle);
            }
            uscan_extra_debug "Checking href $href_canonical";
            if (my @match = $href_canonical =~ /^$_pattern$/) {
                push @hrefs,
                  parse_href($self, $href_canonical, $_pattern, \@match,
                    $mangle);
            }
        }
    }
    return @hrefs;
}

sub plain_search {
    my ($self, $content) = @_;
    my @hrefs;
    foreach my $_pattern (@{ $self->patterns }) {
        while ($content =~ s/.*?($_pattern)//) {
            push @hrefs, $self->parse_href($1, $_pattern, $2);
        }
    }
    return @hrefs;
}

sub parse_href {
    my ($self, $href, $_pattern, $match, $mangle) = @_;
    $mangle //= 'uversionmangle';

    my $mangled_version;
    if ($self->watch_version == 2) {

        # watch_version 2 only recognised one group; the code
        # below will break version 2 watch files with a construction
        # such as file-([\d\.]+(-\d+)?) (bug #327258)
        $mangled_version
          = ref $match eq 'ARRAY'
          ? $match->[0]
          : $match;
    } else {
        # need the map { ... } here to handle cases of (...)?
        # which may match but then return undef values
        if ($self->versionless) {

            # exception, otherwise $mangled_version = 1
            $mangled_version = '';
        } else {
            $mangled_version = join(".",
                map { $_ if defined($_) }
                  ref $match eq 'ARRAY' ? @$match : $href =~ m&^$_pattern$&);
        }

        if (
            mangle(
                $self->watchfile, \$self->line,
                "$mangle:",       \@{ $self->$mangle },
                \$mangled_version
            )
        ) {
            return ();
        }
    }
    $match = '';
    if (defined $self->shared->{download_version}) {
        if ($mangled_version eq $self->shared->{download_version}) {
            $match = "matched with the download version";
        }
    }
    my $priority = $mangled_version . '-' . get_priority($href);
    return [$priority, $mangled_version, $href, $match];
}

1;
