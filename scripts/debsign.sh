#!/bin/sh

# This program is designed to GPG sign .dsc, .buildinfo, or .changes
# files (or any combination of these) in the form needed for a legal
# Debian upload.  It is based in part on dpkg-buildpackage.

# Debian GNU/Linux debsign.  Copyright (C) 1999 Julian Gilbey.
# Modifications to work with GPG by Joseph Carter and Julian Gilbey
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

# Abort if anything goes wrong
set -e

PRECIOUS_FILES=0
PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'
HAVE_SIGNED=""
NUM_SIGNED=0

# Temporary directories
signingdir=""
remotefilesdir=""

trap cleanup_tmpdir EXIT

# --- Functions

mksigningdir () {
    if [ -z "$signingdir" ]; then
	signingdir="$(mktemp -dt debsign.XXXXXXXX)" || {
	    echo "$PROGNAME: Can't create temporary directory" >&2
	    echo "Aborting..." >&2
	    exit 1
	}
    fi
}

mkremotefilesdir () {
    if [ -z "$remotefilesdir" ]; then
	remotefilesdir="$(mktemp -dt debsign.XXXXXXXX)" || {
	    echo "$PROGNAME: Can't create temporary directory" >&2
	    echo "Aborting..." >&2
	    exit 1
	}
    fi
}

usage () {
    echo \
"Usage: debsign [options] [changes, buildinfo, dsc or commands file]
  Options:
    -r [username@]remotehost
                    The machine on which the files live. If given, then a
                    changes file with full pathname (or relative to the
                    remote home directory) must be given as the main
                    argument in the rest of the command line.
    -k<keyid>       The key to use for signing
    -p<sign-command>  The command to use for signing
    -e<maintainer>  Sign using key of <maintainer> (takes precedence over -m)
    -m<maintainer>  The same as -e
    -S              Use changes file made for source-only upload
    -a<arch>        Use changes file made for Debian target architecture <arch>
    -t<target>      Use changes file made for GNU target architecture <target>
    --multi         Use most recent multiarch .changes file found
    --re-sign       Re-sign if the file is already signed.
    --no-re-sign    Don't re-sign if the file is already signed.
    --debs-dir <directory>
                    The location of the files to be signed when called from
                    within a source tree (default "..")
    --no-conf, --noconf
                    Don't read devscripts config files;
                    must be the first option given
    --help          Show this message
    --version       Show version and copyright information
  If an explicit filename is specified, it along with any child .buildinfo and
  .dsc files are signed. Otherwise, debian/changelog is parsed to find the
  changes file.

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is debsign, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999 by Julian Gilbey, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

temp_filename() {
    local filename

    if ! [ -w "$(dirname "$1")" ]; then
	filename=`mktemp -t "$(basename "$1").$2.XXXXXXXXXX"` || {
	    echo "$PROGNAME: Unable to create temporary file; aborting" >&2
	    exit 1
	}
    else
	filename="$1.$2"
    fi

    echo "$filename"
}

to_bool() {
    if "$@"; then echo true; else echo false; fi
}

movefile() {
    if [ -w "$(dirname "$2")" ]; then
	mv -f -- "$1" "$2"
    else
	cat "$1" > "$2"
	rm -f "$1"
    fi
}

cleanup_tmpdir () {
    if [ -n "$remotefilesdir" ] && [ -d "$remotefilesdir" ]; then
	if [ "$PRECIOUS_FILES" -gt 0 ]; then
	    echo "$PROGNAME: aborting with $PRECIOUS_FILES signed files in $remotefilesdir" >&2
	    # Only produce the warning once...
	    PRECIOUS_FILES=0
	else
	    cd ..
	    rm -rf "$remotefilesdir"
	fi
    fi

    if [ -n "$signingdir" ] && [ -d "$signingdir" ]; then
	rm -rf "$signingdir"
    fi
}

mustsetvar () {
    if [ "x$2" = x ]
    then
	echo >&2 "$PROGNAME: unable to determine $3"
	exit 1
    else
	# echo "$PROGNAME: $3 is $2"
	eval "$1=\"\$2\""
    fi
}

# This takes two arguments: the name of the file to sign and the
# key or maintainer name to use.  NOTE: this usage differs from that
# of dpkg-buildpackage, because we do not know all of the necessary
# information when this function is read first.
signfile () {
    local type="$1"
    local file="$2"
    local signas="$3"
    local savestty=$(stty -g 2>/dev/null) || true
    mksigningdir
    UNSIGNED_FILE="$signingdir/$(basename "$file")"
    ASCII_SIGNED_FILE="${UNSIGNED_FILE}.asc"
    (cat "$file" ; echo "") > "$UNSIGNED_FILE"

    gpgversion=`$signcommand --version | head -n 1 | cut -d' ' -f3`
    gpgmajorversion=`echo $gpgversion | cut -d. -f1`
    gpgminorversion=`echo $gpgversion | cut -d. -f2`

    if [ $gpgmajorversion -gt 1 -o $gpgminorversion -ge 4 ]
    then
	    $signcommand --local-user "$signas" --clearsign \
		--list-options no-show-policy-urls \
		--armor --textmode --output "$ASCII_SIGNED_FILE"\
		"$UNSIGNED_FILE" || \
	    { SAVESTAT=$?
	      echo "$PROGNAME: $signcommand error occurred!  Aborting...." >&2
	      stty $savestty 2>/dev/null || true
	      exit $SAVESTAT
	    }
    else
	    $signcommand --local-user "$signas" --clearsign \
		--no-show-policy-url \
		--armor --textmode --output "$ASCII_SIGNED_FILE" \
		"$UNSIGNED_FILE" || \
	    { SAVESTAT=$?
	      echo "$PROGNAME: $signcommand error occurred!  Aborting...." >&2
	      stty $savestty 2>/dev/null || true
	      exit $SAVESTAT
	    }
    fi
    stty $savestty 2>/dev/null || true
    echo
    PRECIOUS_FILES=$(($PRECIOUS_FILES + 1))
    HAVE_SIGNED="${HAVE_SIGNED:+${HAVE_SIGNED}, }$type"
    NUM_SIGNED=$((NUM_SIGNED + 1))
    movefile "$ASCII_SIGNED_FILE" "$file"
}

withecho () {
    echo " $@"
    "$@"
}

file_is_already_signed() {
    test "$(head -n 1 "$1")" = "-----BEGIN PGP SIGNED MESSAGE-----"
}

unsignfile() {
    UNSIGNED_FILE="$(temp_filename "$1" "unsigned")"

    sed -e '1,/^$/d; /^$/,$d' "$1" > "$UNSIGNED_FILE"
    movefile "$UNSIGNED_FILE" "$1"
}

# Has the dsc file already been signed, perhaps from a previous, partially
# successful invocation of debsign?  We give the user the option of
# resigning the file or accepting it as is.  Returns success if already
# and failure if the file needs signing.  Parameters: $1=filename,
# $2=file type for message (e.g. "changes", "commands")
check_already_signed () {
    file_is_already_signed "$1" || return 1

    local resign
    if [ "$opt_re_sign" = "true" ]; then
	resign="true"
    elif [ "$opt_re_sign" = "false" ]; then
	resign="false"
    else
	response=n
	if [ -z "$DEBSIGN_ALWAYS_RESIGN" ]; then
	    printf "The .$2 file is already signed.\nWould you like to use the current signature? [Yn]"
	    read response
	fi
	case $response in
	[Nn]*) resign="true" ;;
	*)     resign="false" ;;
	esac
    fi

    [ "$resign" = "true" ] || \
	return 0

    withecho unsignfile "$1"
    return 1
}

# --- main script

# Unset GREP_OPTIONS for sanity
unset GREP_OPTIONS

# Boilerplate: set config variables
DEFAULT_DEBSIGN_ALWAYS_RESIGN=
DEFAULT_DEBSIGN_PROGRAM=
DEFAULT_DEBSIGN_MAINT=
DEFAULT_DEBSIGN_KEYID=
DEFAULT_DEBRELEASE_DEBS_DIR=..
VARS="DEBSIGN_ALWAYS_RESIGN DEBSIGN_PROGRAM DEBSIGN_MAINT"
VARS="$VARS DEBSIGN_KEYID DEBRELEASE_DEBS_DIR"

if [ "$1" = "--no-conf" -o "$1" = "--noconf" ]; then
    shift
    MODIFIED_CONF_MSG="$MODIFIED_CONF_MSG
  (no configuration files read)"

    # set defaults
    for var in $VARS; do
	eval "$var=\$DEFAULT_$var"
    done
else
    # Run in a subshell for protection against accidental errors
    # in the config files
    eval $(
	set +e
	for var in $VARS; do
	    eval "$var=\$DEFAULT_$var"
	done

	for file in /etc/devscripts.conf ~/.devscripts
	  do
	  [ -r $file ] && . $file
	done

	set | egrep '^(DEBSIGN|DEBRELEASE|DEVSCRIPTS)_')

    # We do not replace this with a default directory to avoid accidentally
    # signing a broken package
    DEBRELEASE_DEBS_DIR="$(echo "${DEBRELEASE_DEBS_DIR%/}" | sed -e 's%/\+%/%g')"

    # set config message
    MODIFIED_CONF=''
    for var in $VARS; do
	eval "if [ \"\$$var\" != \"\$DEFAULT_$var\" ]; then
	    MODIFIED_CONF_MSG=\"\$MODIFIED_CONF_MSG
  $var=\$$var\";
	MODIFIED_CONF=yes;
	fi"
    done

    if [ -z "$MODIFIED_CONF" ]; then
	MODIFIED_CONF_MSG="$MODIFIED_CONF_MSG
  (none)"
    fi
fi

maint="$DEBSIGN_MAINT"
signkey="$DEBSIGN_KEYID"
debsdir="$DEBRELEASE_DEBS_DIR"
debsdir_warning="config file specified DEBRELEASE_DEBS_DIR directory $DEBRELEASE_DEBS_DIR does not exist!"

signcommand=''
if [ -n "$DEBSIGN_PROGRAM" ]; then
    signcommand="$DEBSIGN_PROGRAM"
else
    if command -v gpg > /dev/null 2>&1; then
	signcommand=gpg
    elif command -v gpg2 > /dev/null 2>&1; then
	signcommand=gpg2
    fi
fi

TEMP=$(getopt -n "$PROGNAME" -o 'p:m:e:k:Sa:t:r:h' \
	      -l 'multi,re-sign,no-re-sign,debs-dir:' \
	      -l 'noconf,no-conf,help,version' \
	      -- "$@") || (rc=$?; usage >&2; exit $rc)

eval set -- "$TEMP"

while true
do
    case "$1" in
	-p) signcommand="$2"; shift ;;
	-m) maint="$2"; shift ;;
	-e) maint="$2"; shift ;;
	-k) signkey="$2"; shift ;;
	-S) sourceonly="true" ;;
	-a) targetarch="$2"; shift ;;
	-t) targetgnusystem="$2"; shift ;;
	--multi) multiarch="true" ;;
	--re-sign)    opt_re_sign="true" ;;
	--no-re-sign) opt_re_sign="false" ;;
	-r)	remotehost=$2; shift
		# Allow for the [user@]host:filename format
		hostpart="${remotehost%:*}"
		filepart="${remotehost#*:}"
		if [ -n "$filepart" -a "$filepart" != "$remotehost" ]; then
		    remotehost="$hostpart"
		    set -- "$@" "$filepart"
		fi
		;;
	--debs-dir)
	    shift
	    opt_debsdir="$(echo "${1%/}" | sed -e 's%/\+%/%g')"
	    debsdir_warning="could not find directory $opt_debsdir!"
	    ;;
	--no-conf|--noconf)
		echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
		exit 1 ;;
	-h|--help)
		usage; exit 0 ;;
	--version)
		version; exit 0 ;;
	--)	shift; break ;;
    esac
    shift
done

debsdir=${opt_debsdir:-$debsdir}

if [ -z "$signcommand" ]; then
    echo "Could not find a signing program!" >&2
    exit 1
fi

if echo "${signkey}" | grep -E -qs '^(0x)?[a-zA-Z0-9]{8}$'; then
    echo "Refusing to sign with short key ID '$signkey'!" >&2
    exit 1
fi

if echo "${signkey}" | grep -E -qs '^(0x)?[a-zA-Z0-9]{16}$'; then
    echo "long key IDs are discouraged; please use key fingerprints instead" >&2
fi

ensure_local_copy() {
    local remotehost="$1"
    local remotefile="$2"
    local file="$3"
    local type="$4"
    if [ -n "$remotehost" ]
    then
	if [ ! -f "$file" ]
	then
	    withecho scp "$remotehost:$remotefile" "$file"
	fi
    fi

    if [ ! -f "$file" -o ! -r "$file" ]
    then
	echo "$PROGNAME: Can't find or can't read $type file $file!" >&2
	exit 1
    fi
}

fixup_control() {
    local filter_out="$1"
    local childtype="$2"
    local parenttype="$3"
    local child="$4"
    local parent="$5"
    test -r "$child" || {
	echo "$PROGNAME: Can't read .$childtype file $child!" >&2
	return 1
    }

    local md5=$(md5sum "$child" | cut -d' ' -f1)
    local sha1=$(sha1sum "$child" | cut -d' ' -f1)
    local sha256=$(sha256sum "$child" | cut -d' ' -f1)
    perl -i -pe 'BEGIN {
    '" \$file='$child'; \$md5='$md5'; "'
    '" \$sha1='$sha1'; \$sha256='$sha256'; "'
    $size=(-s $file); ($base=$file) =~ s|.*/||;
    $infiles=0; $inmd5=0; $insha1=0; $insha256=0; $format="";
    }
    if(/^Format:\s+(.*)/) {
	$format=$1;
	die "Unrecognised .$parenttype format: $format\n"
	    unless $format =~ /^\d+(\.\d+)*$/;
	($major, $minor) = split(/\./, $format);
	$major+=0;$minor+=0;
	die "Unsupported .$parenttype format: $format\n"
	    if('"$filter_out"');
    }
    /^Files:/i && ($infiles=1,$inmd5=0,$insha1=0,$insha256=0);
    if(/^Checksums-Sha1:/i) {$insha1=1;$infiles=0;$inmd5=0;$insha256=0;}
    elsif(/^Checksums-Sha256:/i) {
	$insha256=1;$infiles=0;$inmd5=0;$insha1=0;
    } elsif(/^Checksums-Md5:/i) {
	$inmd5=1;$infiles=0;$insha1=0;$insha256=0;
    } elsif(/^Checksums-.*?:/i) {
	die "Unknown checksum format: $_\n";
    }
    /^\s*$/ && ($infiles=0,$inmd5=0,$insha1=0,$insha256=0);
    if ($infiles &&
	/^ (\S+) (\d+) (\S+) (\S+) \Q$base\E\s*$/) {
	$_ = " $md5 $size $3 $4 $base\n";
	$infiles=0;
    }
    if ($inmd5 &&
	/^ (\S+) (\d+) \Q$base\E\s*$/) {
        $_ = " $md5 $size $base\n";
        $inmd5=0;
    }
    if ($insha1 &&
	/^ (\S+) (\d+) \Q$base\E\s*$/) {
	$_ = " $sha1 $size $base\n";
	$insha1=0;
    }
    if ($insha256 &&
	/^ (\S+) (\d+) \Q$base\E\s*$/) {
	$_ = " $sha256 $size $base\n";
	$insha256=0;
    }' "$parent"
}

fixup_buildinfo() {
    fixup_control '($major != 0 or $minor > 2) and ($major != 1 or $minor > 0)' dsc buildinfo "$@"
}

fixup_changes() {
    local childtype="$1"
    shift
    fixup_control '$major!=1 or $minor > 8 or $minor < 7' $childtype changes "$@"
}

withtempfile() {
    local filetype="$1"
    local mainfile="$2"
    shift 2
    local temp_file="$(temp_filename "$mainfile" "temp")"
    cp "$mainfile" "$temp_file"
    if "$@" "$temp_file"; then
	if ! cmp -s "$mainfile" "$temp_file"; then
	    # emulate output of "withecho" but on the mainfile
	    echo " $@" "$mainfile" >&2
	fi
	movefile "$temp_file" "$mainfile"
    else
	rm "$temp_file"
	echo "$PROGNAME: Error processing .$filetype file (see above)" >&2
	exit 1
    fi
}

guess_signas() {
    if [ -n "$maint" ]
    then maintainer="$maint"
    # Try the new "Changed-By:" field first
    else maintainer=`sed -n 's/^Changed-By: //p' $1`
    fi
    if [ -z "$maintainer" ]
    then maintainer=`sed -n 's/^Maintainer: //p' $1`
    fi

    echo "${signkey:-$maintainer}"
}

maybesign_dsc() {
    local signas="$1"
    local remotehost="$2"
    local dsc="$3"

    if check_already_signed "$dsc" dsc; then
	echo "Leaving current signature unchanged." >&2
	return
    fi

    withecho signfile dsc "$dsc" "$signas"

    if [ -n "$remotehost" ]
    then
	withecho scp "$dsc" "$remotehost:$remotedir"
	PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
    fi
}

maybesign_buildinfo() {
    local signas="$1"
    local remotehost="$2"
    local buildinfo="$3"
    local dsc="$4"

    if check_already_signed "$buildinfo" "buildinfo"; then
       echo "Leaving current signature unchanged." >&2
       return
    fi

    if [ -n "$dsc" ]; then
	maybesign_dsc "$signas" "$remotehost" "$dsc"
	withtempfile buildinfo "$buildinfo" fixup_buildinfo "$dsc"
    fi

    withecho signfile buildinfo "$buildinfo" "$signas"

    if [ -n "$remotehost" ]
    then
	withecho scp "$buildinfo" "$remotehost:$remotedir"
	PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
    fi
}

maybesign_changes() {
    local signas="$1"
    local remotehost="$2"
    local changes="$3"
    local buildinfo="$4"
    local dsc="$5"

    if check_already_signed "$changes" "changes"; then
	echo "Leaving current signature unchanged." >&2
	return
    fi

    hasdsc="$(to_bool [ -n "$dsc" ])"
    hasbuildinfo="$(to_bool [ -n "$buildinfo" ])"

    if $hasbuildinfo; then
	# assume that this will also sign the same dsc if it's available
	maybesign_buildinfo "$signas" "$remotehost" "$buildinfo" "$dsc"
    elif $hasdsc; then
	maybesign_dsc "$signas" "$remotehost" "$dsc"
    fi

    if $hasdsc; then
	withtempfile changes "$changes" fixup_changes dsc "$dsc"
    fi
    if $hasbuildinfo; then
	withtempfile changes "$changes" fixup_changes buildinfo "$buildinfo"
    fi
    withecho signfile changes "$changes" "$signas"

    if [ -n "$remotehost" ]
    then
	withecho scp "$changes" "$remotehost:$remotedir"
	PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
    fi
}

report_signed() {
    if [ $NUM_SIGNED -eq 1 ]; then
	echo "Successfully signed $HAVE_SIGNED file"
    elif [ $NUM_SIGNED -gt 0 ]; then
	echo "Successfully signed $HAVE_SIGNED files"
    fi
}

dosigning() {
    # Do we have to download the changes file?
    if [ -n "$remotehost" ]
    then
	mkremotefilesdir
	cd "$remotefilesdir"

	remotechanges=$changes
	remotebuildinfo=$buildinfo
	remotedsc=$dsc
	remotecommands=$commands
	changes=`basename "$changes"`
	buildinfo=`basename "$buildinfo"`
	dsc=`basename "$dsc"`
	commands=`basename "$commands"`

	if [ -n "$changes" ]; then
	    if [ ! -f "$changes" ]; then
		# Special handling for changes to support supplying a glob
		# and downloading all matching changes files (c.f., #491627)
		withecho scp "$remotehost:$remotechanges" .
	    fi
	fi

	if [ -n "$changes" ] && echo "$changes" | egrep -q '[][*?]'
	then
	    for changes in $changes
	    do
		dsc=
		buildinfo=
		printf "\n"
		dosigning;
	    done
	    exit 0;
	fi
    fi

    if [ -n "$commands" ] # sign .commands file
    then
	ensure_local_copy "$remotehost" "$remotecommands" "$commands" commands
	check_already_signed "$commands" commands && {
	    echo "Leaving current signature unchanged." >&2
	    return
	}

	# simple validator for .commands files, see
	# ftp://ftp.upload.debian.org/pub/UploadQueue/README
	perl -ne 'BEGIN { $uploader = 0; $incommands = 0; }
              END { exit $? if $?;
                    if ($uploader && $incommands) { exit 0; }
                    else { die ".commands file missing Uploader or Commands field\n"; }
                  }
              sub checkcommands {
                  chomp($line=$_[0]);
                  if ($line =~ m%^\s*reschedule\s+[^\s/]+\.changes\s+[0-9]+-day\s*$%) { return 0; }
                  if ($line =~ m%^\s*cancel\s+[^\s/]+\.changes\s*$%) { return 0; }
                  if ($line =~ m%^\s*rm(\s+(?:DELAYED/[0-9]+-day/)?[^\s/]+)+\s*$%) { return 0; }
                  if ($line eq "") { return 0; }
                  die ".commands file has invalid Commands line: $line\n";
              }
              if (/^Uploader:/) {
                  if ($uploader) { die ".commands file has too many Uploader fields!\n"; }
                  $uploader++;
              } elsif (! $incommands && s/^Commands:\s*//) {
                  $incommands=1; checkcommands($_);
              } elsif ($incommands == 1) {
                 if (s/^\s+//) { checkcommands($_); }
                 elsif (/./) { die ".commands file: extra stuff after Commands field!\n"; }
                 else { $incommands = 2; }
              } else {
                 next if /^\s*$/;
                 if (/./) { die ".commands file: extra stuff after Commands field!\n"; }
              }' $commands || {
	echo "$PROGNAME: .commands file appears to be invalid. see:
ftp://ftp.upload.debian.org/pub/UploadQueue/README
for valid format" >&2;
	exit 1; }

	if [ -n "$maint" ]
	then maintainer="$maint"
	else
            maintainer=`sed -n 's/^Uploader: //p' $commands`
            if [ -z "$maintainer" ]
            then
		echo "Unable to parse Uploader, .commands file invalid."
		exit 1
            fi
	fi

	signas="${signkey:-$maintainer}"

	withecho signfile commands "$commands" "$signas"

	if [ -n "$remotehost" ]
	then
	    withecho scp "$commands" "$remotehost:$remotedir"
	    PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	fi

	report_signed

    elif [ -n "$changes" ]
    then
	ensure_local_copy "$remotehost" "$remotechanges" "$changes" changes
	derive_childfile "$changes" dsc
	if [ -n "$dsc" ]
	then
	    ensure_local_copy "$remotehost" "${remotedir}$dsc" "$dsc" dsc
	fi
	derive_childfile "$changes" buildinfo
	if [ -n "$buildinfo" ]
	then
	    ensure_local_copy "$remotehost" "${remotedir}$buildinfo" "$buildinfo" buildinfo
	fi
	signas="$(guess_signas "$changes")"
	maybesign_changes "$signas" "$remotehost" \
	    "$changes" "$buildinfo" "$dsc"
	report_signed

    elif [ -n "$buildinfo" ]
    then
	ensure_local_copy "$remotehost" "$remotebuildinfo" "$buildinfo" buildinfo
	derive_childfile "$buildinfo" dsc
	if [ -n "$dsc" ]
	then
	    ensure_local_copy "$remotehost" "${remotedir}$dsc" "$dsc" dsc
	fi
	signas="$(guess_signas "$buildinfo")"
	maybesign_buildinfo "$signas" "$remotehost" \
	    "$buildinfo" "$dsc"
	report_signed

    else
	ensure_local_copy "$remotehost" "$remotedsc" "$dsc" dsc
	signas="$(guess_signas "$dsc")"
	maybesign_dsc "$signas" "$remotehost" "$dsc"
	report_signed

    fi
}

derive_childfile() {
    local base="$1"
    local ext="$2"

    local fname dir
    fname="$(sed -n '/^\(Checksum\|Files\)/,/^\(Checksum\|Files\)/s/.*[ 	]\([^ ]*\.'"$ext"'\)$/\1/p' "$base" | head -n1)"
    if [ -n "$fname" ]
    then
	get_dirname "$base" dir
	eval "$ext=\"${dir}$fname\""
    else
	eval "$ext="
    fi
}

get_dirname() {
    local path="$1"
    local varname="$2"

    local d
    d="$(dirname "$path")"

    if [ "$d" = "." ]
    then
	d=""
    else
	d="$d/"
    fi

    eval "$varname=\"$d\""
}

# If there is a command-line parameter, it is the name of a .changes file
# If not, we must be at the top level of a source tree and will figure
# out its name from debian/changelog
case $# in
    0)	# We have to parse debian/changelog to find the current version
	# check sanity of debsdir
	if ! [ -d "$debsdir" ]; then
	    echo "$PROGNAME: $debsdir_warning" >&2
	    exit 1
	fi
	if [ -n "$remotehost" ]; then
	    echo "$PROGNAME: Need to specify a remote file location when giving -r!" >&2
	    exit 1
	fi
	if [ ! -r debian/changelog ]; then
	    echo "$PROGNAME: Must be run from top of source dir or a .changes file given as arg" >&2
	    exit 1
	fi

	mustsetvar package "`dpkg-parsechangelog -SSource`" "source package"
	mustsetvar version "`dpkg-parsechangelog -SVersion`" "source version"

	if [ "x$sourceonly" = x ]
	then
	    if [ -n "$targetarch" ] && [ -n "$targetgnusystem" ]; then
		mustsetvar arch "$(dpkg-architecture "-a${targetarch}" "-t${targetgnusystem}" -qDEB_HOST_ARCH)" "build architecture"
	    elif [ -n "$targetarch" ]; then
		mustsetvar arch "$(dpkg-architecture "-a${targetarch}" -qDEB_HOST_ARCH)" "build architecture"
	    elif [ -n "$targetgnusystem" ]; then
		mustsetvar arch "$(dpkg-architecture "-t${targetgnusystem}" -qDEB_HOST_ARCH)" "build architecture"
	    else
		mustsetvar arch "$(dpkg-architecture -qDEB_HOST_ARCH)" "build architecture"
	    fi
	else
	    arch=source
	fi

	sversion=`echo "$version" | perl -pe 's/^\d+://'`
	pva="${package}_${sversion}_${arch}"
	changes="$debsdir/$pva.changes"
	if [ -n "$multiarch" -o ! -r $changes ]; then
	    changes=$(ls "$debsdir/${package}_${sversion}_*+*.changes" "$debsdir/${package}_${sversion}_multi.changes" 2>/dev/null | head -1)
	    # TODO: dpkg-cross does not yet do buildinfo, so don't worry about it here
	    if [ -z "$multiarch" ]; then
		if [ -n "$changes" ]; then
		    echo "$PROGNAME: could not find normal .changes file but found multiarch file:" >&2
		    echo "  $changes" >&2
		    echo "Using this changes file instead." >&2
		else
		    echo "$PROGNAME: Can't find or can't read changes file $changes!" >&2
		    exit 1
		fi
	    elif [ -n "$multiarch" -a -z "$changes" ]; then
		echo "$PROGNAME: could not find any multiarch .changes file with name" >&2
		echo "$debsdir/${package}_${sversion}_*.changes" >&2
		exit 1
	    fi
	fi
	derive_childfile "$changes" dsc
	derive_childfile "$changes" buildinfo
	dosigning;
	;;

    *)	while [ $# -gt 0 ]; do
	    changes=
	    buildinfo=
	    dsc=
	    commands=
	    case "$1" in
		*.dsc)
		    dsc=$1
		    ;;
	        *.buildinfo)
		    buildinfo=$1
		    ;;
	        *.changes)
		    changes=$1
		    ;;
		*.commands)
		    commands=$1
		    ;;
		*)
		    echo "$PROGNAME: Only a .changes, .buildinfo, .dsc or .commands file is allowed as argument!" >&2
		    exit 1 ;;
	    esac
	    get_dirname "$1" remotedir
	    dosigning
	    shift
	done
	;;
esac

exit 0
