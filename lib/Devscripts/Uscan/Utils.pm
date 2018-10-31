package Devscripts::Uscan::Utils;

use strict;
use Devscripts::Uscan::Output;
use Devscripts::Utils;
use Exporter 'import';

our @EXPORT = (
    qw(fix_href recursive_regex_dir newest_dir get_compression
      get_suffix get_priority quoted_regex_parse safe_replace mangle
      uscan_exec uscan_exec_no_fail)
);

#######################################################################
# {{{ code 5: utility functions (download)
#######################################################################
sub fix_href ($) {
    my ($href) = @_;

    # Remove newline (code moved from outside fix_href)
    $href =~ s/\n//g;

  # Remove whitespace from URLs:
  # https://www.w3.org/TR/html5/links.html#links-created-by-a-and-area-elements
    $href =~ s/^\s+//;
    $href =~ s/\s+$//;

    return $href;
}

sub recursive_regex_dir ($$$$$$) {

    # If return '', parent code to cause return 1
    my ($downloader, $base, $dirversionmangle, $watchfile, $lineptr,
        $download_version)
      = @_;

    $base =~ m%^(\w+://[^/]+)/(.*)$%;
    my $site = $1;
    my @dirs = ();
    if (defined $2) {
        @dirs = split /(\/)/, $2;
    }
    my $dir = '/';

    foreach my $dirpattern (@dirs) {
        if ($dirpattern =~ /\(.*\)/) {
            uscan_verbose "dir=>$dir  dirpattern=>$dirpattern";
            my $newest_dir = newest_dir($downloader, $site, $dir, $dirpattern,
                $dirversionmangle, $watchfile, $lineptr, $download_version);
            uscan_verbose "newest_dir => '$newest_dir'";
            if ($newest_dir ne '') {
                $dir .= "$newest_dir";
            } else {
                uscan_debug "No \$newest_dir";
                return '';
            }
        } else {
            $dir .= "$dirpattern";
        }
    }
    return $site . $dir;
}

# very similar to code above
sub newest_dir ($$$$$$$$) {

    # return string $newdir as success
    # return string '' if error, to cause grand parent code to return 1
    my ($downloader, $site, $dir, $pattern, $dirversionmangle, $watchfile,
        $lineptr, $download_version)
      = @_;
    my ($newdir);
    uscan_verbose "Requesting URL:\n   $site$dir";
    if ($site =~ m%^http(s)?://%) {
        require Devscripts::Uscan::http;
        $newdir = Devscripts::Uscan::http::http_newdir($1, @_);
    } elsif ($site =~ m%^ftp://%) {
        require Devscripts::Uscan::ftp;
        $newdir = Devscripts::Uscan::ftp::ftp_newdir(@_);
    } else {
        # Neither HTTP nor FTP site
        uscan_warn "neither HTTP nor FTP site, impossible case for newdir().";
        $newdir = '';
    }
    return $newdir;
}
#######################################################################
# }}} code 5: utility functions (download)
#######################################################################

#######################################################################
# {{{ code 6: utility functions (compression)
#######################################################################
# Get legal values for compression
sub get_compression ($) {
    my $compression = $_[0];
    my $canonical_compression;

    # be liberal in what you accept...
    my %opt2comp = (
        gz    => 'gzip',
        gzip  => 'gzip',
        bz2   => 'bzip2',
        bzip2 => 'bzip2',
        lzma  => 'lzma',
        xz    => 'xz',
        zip   => 'zip',
    );

    # Normalize compression methods to the names used by Dpkg::Compression
    if (exists $opt2comp{$compression}) {
        $canonical_compression = $opt2comp{$compression};
    } else {
        uscan_die "$progname: invalid compression, $compression given.";
    }
    return $canonical_compression;
}

# Get legal values for compression suffix
sub get_suffix ($) {
    my $compression = $_[0];
    my $canonical_suffix;

    # be liberal in what you accept...
    my %opt2suffix = (
        gz    => 'gz',
        gzip  => 'gz',
        bz2   => 'bz2',
        bzip2 => 'bz2',
        lzma  => 'lzma',
        xz    => 'xz',
        zip   => 'zip',
    );

    # Normalize compression methods to the names used by Dpkg::Compression
    if (exists $opt2suffix{$compression}) {
        $canonical_suffix = $opt2suffix{$compression};
    } elsif ($compression eq 'default') {
        require Devscripts::MkOrigtargz::Config;
        return &Devscripts::MkOrigtargz::Config::default_compression;
    } else {
        uscan_die "$progname: invalid suffix, $compression given.";
    }
    return $canonical_suffix;
}

# Get compression priority
sub get_priority ($) {
    my $href     = $_[0];
    my $priority = 0;
    if ($href =~ m/\.tar\.gz/i) {
        $priority = 1;
    }
    if ($href =~ m/\.tar\.bz2/i) {
        $priority = 2;
    }
    if ($href =~ m/\.tar\.lzma/i) {
        $priority = 3;
    }
    if ($href =~ m/\.tar\.xz/i) {
        $priority = 4;
    }
    return $priority;
}
#######################################################################
# }}} code 6: utility functions (compression)
#######################################################################

#######################################################################
# {{{ code 7: utility functions (regex)
#######################################################################
sub quoted_regex_parse($) {
    my $pattern = shift;
    my %closers = ('{', '}', '[', ']', '(', ')', '<', '>');

    $pattern =~ /^(s|tr|y)(.)(.*)$/;
    my ($sep, $rest) = ($2, $3 || '');
    my $closer = $closers{$sep};

    my $parsed_ok       = 1;
    my $regexp          = '';
    my $replacement     = '';
    my $flags           = '';
    my $open            = 1;
    my $last_was_escape = 0;
    my $in_replacement  = 0;

    for my $char (split //, $rest) {
        if ($char eq $sep and !$last_was_escape) {
            $open++;
            if ($open == 1) {
                if ($in_replacement) {

                    # Separator after end of replacement
                    uscan_warn "Extra \"$sep\" after end of replacement.";
                    $parsed_ok = 0;
                    last;
                } else {
                    $in_replacement = 1;
                }
            } else {
                if ($open > 1) {
                    if ($in_replacement) {
                        $replacement .= $char;
                    } else {
                        $regexp .= $char;
                    }
                }
            }
        } elsif ($char eq $closer and !$last_was_escape) {
            $open--;
            if ($open > 0) {
                if ($in_replacement) {
                    $replacement .= $char;
                } else {
                    $regexp .= $char;
                }
            } elsif ($open < 0) {
                uscan_warn "Extra \"$closer\" after end of replacement.";
                $parsed_ok = 0;
                last;
            }
        } else {
            if ($in_replacement) {
                if ($open) {
                    $replacement .= $char;
                } else {
                    $flags .= $char;
                }
            } else {
                if ($open) {
                    $regexp .= $char;
                } elsif ($char !~ m/\s/) {
                    uscan_warn
                      "Non-whitespace between <...> and <...> (or similars).";
                    $parsed_ok = 0;
                    last;
                }

                # skip if blanks between <...> and <...> (or similars)
            }
        }

        # Don't treat \\ as an escape
        $last_was_escape = ($char eq '\\' and !$last_was_escape);
    }

    unless ($in_replacement and $open == 0) {
        uscan_warn "Empty replacement string.";
        $parsed_ok = 0;
    }

    return ($parsed_ok, $regexp, $replacement, $flags);
}

sub safe_replace($$) {
    my ($in, $pat) = @_;
    eval "uscan_debug \"safe_replace input=\\\"\$\$in\\\"\\n\"";
    $pat =~ s/^\s*(.*?)\s*$/$1/;

    $pat =~ /^(s|tr|y)(.)/;
    my ($op, $sep) = ($1, $2 || '');
    my $esc = "\Q$sep\E";
    my ($parsed_ok, $regexp, $replacement, $flags);

    if ($sep eq '{' or $sep eq '(' or $sep eq '[' or $sep eq '<') {
        ($parsed_ok, $regexp, $replacement, $flags) = quoted_regex_parse($pat);

        unless ($parsed_ok) {
            uscan_warn "stop mangling: rule=\"$pat\"\n"
              . "  mangling rule with <...>, (...), {...} failed.";
            return 0;
        }
    } elsif ($pat
        !~ /^(?:s|tr|y)$esc((?:\\.|[^\\$esc])*)$esc((?:\\.|[^\\$esc])*)$esc([a-z]*)$/
    ) {
        $sep = "/" if $sep eq '';
        uscan_warn "stop mangling: rule=\"$pat\"\n"
          . "   rule doesn't match \"(s|tr|y)$sep.*$sep.*$sep\[a-z\]*\" (or similar).";
        return 0;
    } else {
        ($regexp, $replacement, $flags) = ($1, $2, $3);
    }

    uscan_debug
"safe_replace with regexp=\"$regexp\", replacement=\"$replacement\", and flags=\"$flags\"";
    my $safeflags = $flags;
    if ($op eq 'tr' or $op eq 'y') {
        $safeflags =~ tr/cds//cd;
        if ($safeflags ne $flags) {
            uscan_warn "stop mangling: rule=\"$pat\"\n"
              . "   flags must consist of \"cds\" only.";
            return 0;
        }

        $regexp =~ s/\\(.)/$1/g;
        $replacement =~ s/\\(.)/$1/g;

        $regexp =~ s/([^-])/'\\x'  . unpack 'H*', $1/ge;
        $replacement =~ s/([^-])/'\\x'  . unpack 'H*', $1/ge;

        eval "\$\$in =~ tr<$regexp><$replacement>$flags;";

        if ($@) {
            uscan_warn "stop mangling: rule=\"$pat\"\n"
              . "   mangling \"tr\" or \"y\" rule execution failed.";
            return 0;
        } else {
            return 1;
        }
    } else {
        $safeflags =~ tr/gix//cd;
        if ($safeflags ne $flags) {
            uscan_warn "stop mangling: rule=\"$pat\"\n"
              . "   flags must consist of \"gix\" only.";
            return 0;
        }

        my $global = ($flags =~ s/g//);
        $flags = "(?$flags)" if length $flags;

        my $slashg;
        if ($regexp =~ /(?<!\\)(\\\\)*\\G/) {
            $slashg = 1;

            # if it's not initial, it is too dangerous
            if ($regexp =~ /^.*[^\\](\\\\)*\\G/) {
                uscan_warn "stop mangling: rule=\"$pat\"\n"
                  . "   dangerous use of \\G with regexp=\"$regexp\".";
                return 0;
            }
        }

        # Behave like Perl and treat e.g. "\." in replacement as "."
        # We allow the case escape characters to remain and
        # process them later
        $replacement =~ s/(^|[^\\])\\([^luLUE])/$1$2/g;

        # Unescape escaped separator characters
        $replacement =~ s/\\\Q$sep\E/$sep/g;

        # If bracketing quotes were used, also unescape the
        # closing version
        ### {{ ### (FOOL EDITOR for non-quoted kets)
        $replacement =~ s/\\\Q}\E/}/g if $sep eq '{';
        $replacement =~ s/\\\Q]\E/]/g if $sep eq '[';
        $replacement =~ s/\\\Q)\E/)/g if $sep eq '(';
        $replacement =~ s/\\\Q>\E/>/g if $sep eq '<';

        # The replacement below will modify $replacement so keep
        # a copy. We'll need to restore it to the current value if
        # the global flag was set on the input pattern.
        my $orig_replacement = $replacement;

        my ($first, $last, $pos, $zerowidth, $matched, @captures) = (0, -1, 0);
        while (1) {
            eval {
                # handle errors due to unsafe constructs in $regexp
                no re 'eval';

                # restore position
                pos($$in) = $pos if $pos;

                if ($zerowidth) {

                    # previous match was a zero-width match, simulate it to set
                    # the internal flag that avoids the infinite loop
                    $$in =~ /()/g;
                }

                # Need to use /g to make it use and save pos()
                $matched = ($$in =~ /$flags$regexp/g);

                if ($matched) {

                    # save position and size of the match
                    my $oldpos = $pos;
                    $pos = pos($$in);
                    ($first, $last) = ($-[0], $+[0]);

                    if ($slashg) {

                        # \G in the match, weird things can happen
                        $zerowidth = ($pos == $oldpos);

                        # For example, matching without a match
                        $matched = 0
                          if ( not defined $first
                            or not defined $last);
                    } else {
                        $zerowidth = ($last - $first == 0);
                    }
                    for my $i (0 .. $#-) {
                        $captures[$i] = substr $$in, $-[$i], $+[$i] - $-[$i];
                    }
                }
            };
            if ($@) {
                uscan_warn "stop mangling: rule=\"$pat\"\n"
                  . "   mangling \"s\" rule execution failed.";
                return 0;
            }

            # No match; leave the original string  untouched but return
            # success as there was nothing wrong with the pattern
            return 1 unless $matched;

            # Replace $X
            $replacement
              =~ s/[\$\\](\d)/defined $captures[$1] ? $captures[$1] : ''/ge;
            $replacement
              =~ s/\$\{(\d)\}/defined $captures[$1] ? $captures[$1] : ''/ge;
            $replacement =~ s/\$&/$captures[0]/g;

            # Make \l etc escapes work
            $replacement =~ s/\\l(.)/lc $1/e;
            $replacement =~ s/\\L(.*?)(\\E|\z)/lc $1/e;
            $replacement =~ s/\\u(.)/uc $1/e;
            $replacement =~ s/\\U(.*?)(\\E|\z)/uc $1/e;

            # Actually do the replacement
            substr $$in, $first, $last - $first, $replacement;

            # Update position
            $pos += length($replacement) - ($last - $first);

            if ($global) {
                $replacement = $orig_replacement;
            } else {
                last;
            }
        }

        return 1;
    }
}

# call this as
#    if mangle($watchfile, \$line, 'uversionmangle:',
#	    \@{$options{'uversionmangle'}}, \$version) {
#	return 1;
#    }
sub mangle($$$$$) {
    my ($watchfile, $lineptr, $name, $rulesptr, $verptr) = @_;
    foreach my $pat (@{$rulesptr}) {
        if (!safe_replace($verptr, $pat)) {
            uscan_warn "In $watchfile, potentially"
              . " unsafe or malformed $name"
              . " pattern:\n  '$pat'"
              . " found. Skipping watchline\n"
              . "  $$lineptr";
            return 1;
        }
        uscan_debug "After $name $$verptr";
    }
    return 0;
}

*uscan_exec_no_fail = \&ds_exec_no_fail;

*uscan_exec = \&ds_exec;

#######################################################################
# }}} code 7: utility functions (regex)
#######################################################################

1;
