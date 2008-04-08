#! /bin/bash

# This program is designed to PGP sign a .dsc and .changes file pair
# in the form needed for a legal Debian upload.  It is based in part
# on dpkg-buildpackage.  It takes one argument: the name of the
# .changes file.  It also takes some options:
#  -e<maintainer>  Sign using key of <maintainer> (takes precedence over -m)
#  -m<maintainer>  Sign using key of <maintainer>
#  -k<key>     The PGP/GPG key ID to use; overrides -m
#  -p<type>    <type> is either pgp or gpg to specify which to use
#  -spgp,-sgpg The program takes arguments like pgp or gpg respectively
#  -S          Source-only .changes file
#  -a<arch>    Debian architecture
#  -t<type>    GNU machine type
#  --multi     Search for multiarch .changes files
#  -r [username@]remotehost  The changes (and dsc) files live on remotehost
#  --no-conf, --noconf  Don't read configuration files
#  --help, --version

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
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Abort if anything goes wrong
set -e

PRECIOUS_FILES=0
PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

# --- Functions

usage () {
    echo \
"Usage: debsign [options] [changes, dsc or commands file]
  Options:
    -r [username@]remotehost
                    The machine on which the changes/dsc files live.
                    A changes file with full pathname (or relative
                    to the remote home directory) must be given in
                    such a case
    -k<keyid>       The key to use for signing
    -p<sign-command>  The command to use for signing
    -sgpg           The sign-command is called like GPG
    -spgp           The sign-command is called like PGP
    -e<maintainer>  Sign using key of <maintainer> (takes precedence over -m)
    -m<maintainer>  The same as -e
    -S              Use changes file made for source-only upload
    -a<arch>        Use changes file made for Debian target architecture <arch>
    -t<target>      Use changes file made for GNU target architecture <target>
    --multi         Use most recent multiarch .changes file found
    --no-conf, --noconf
                    Don't read devscripts config files;
                    must be the first option given
    --help          Show this message
    --version       Show version and copyright information
  If a commands or dsc or changes file is specified, it and any .dsc files in
  the changes file are signed, otherwise debian/changelog is parsed to find
  the changes file.

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

cleanup_tmpdir () {
    if [ "$PRECIOUS_FILES" -gt 0 ]; then
        echo "$PROGNAME: aborting with $PRECIOUS_FILES signed files in `pwd`" >&2
    else
        cd ..; rm -rf debsign.$$
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
    local savestty=$(stty -g 2>/dev/null) || true
    if [ $signinterface = gpg ]
    then
	gpgversion=`gpg --version | head -n 1 | cut -d' ' -f3`
	gpgmajorversion=`echo $gpgversion | cut -d. -f1`
	gpgminorversion=`echo $gpgversion | cut -d. -f2`
	if [ $gpgmajorversion -gt 1 -o $gpgminorversion -ge 4 ]
	then
		(cat "$1" ; echo "") | \
		    $signcommand --local-user "$2" --clearsign \
		    --list-options no-show-policy-urls \
		    --armor --textmode --output - - > "$1.asc" || \
		{ SAVESTAT=$?
		  echo "$PROGNAME: gpg error occurred!  Aborting...." >&2
		  stty $savestty 2>/dev/null || true
		  exit $SAVESTAT
		}
	else
		(cat "$1" ; echo "") | \
		    $signcommand --local-user "$2" --clearsign \
		        --no-show-policy-url \
			--armor --textmode --output - - > "$1.asc" || \
		{ SAVESTAT=$?
		  echo "$PROGNAME: gpg error occurred!  Aborting...." >&2
		  stty $savestty 2>/dev/null || true
		  exit $SAVESTAT
		}
	fi
    else
	$signcommand -u "$2" +clearsig=on -fast < "$1" > "$1.asc"
    fi
    stty $savestty 2>/dev/null || true
    echo
    PRECIOUS_FILES=$(($PRECIOUS_FILES + 1))
    mv -f -- "$1.asc" "$1"
}

withecho () {
    echo " $@"
    "$@"
}

# Has the dsc file already been signed, perhaps from a previous, partially
# successful invocation of debsign?  We give the user the option of
# resigning the file or accepting it as is.  Returns success if already
# and failure if the file needs signing.  Parameters: $1=filename,
# $2=file description for message (dsc or changes)
check_already_signed () {
    if [ "`head -n 1 \"$1\"`" != "-----BEGIN PGP SIGNED MESSAGE-----" ]
    then
	return 1
    else
	printf "The .$2 file is already signed.\nWould you like to use the current signature? [Yn]"
	read response
	case $response in
	[Nn]*)
	    sed -e '1,/^$/d; /^$/,$d' "$1" > "$1.unsigned"
	    mv "$1.unsigned" "$1"
	    return 1
	    ;;
	*) return 0;;
	esac
    fi
}

# --- main script

# Boilerplate: set config variables
DEFAULT_DEBSIGN_PROGRAM=
DEFAULT_DEBSIGN_SIGNLIKE=
DEFAULT_DEBSIGN_MAINT=
DEFAULT_DEBSIGN_KEYID=
VARS="DEBSIGN_PROGRAM DEBSIGN_SIGNLIKE DEBSIGN_MAINT DEBSIGN_KEYID"

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

	set | egrep '^(DEBSIGN|DEVSCRIPTS)_')

    # check sanity
    case "$DEBSIGN_SIGNLIKE" in
	gpg|pgp) ;;
	*) DEBSIGN_SIGNLIKE= ;;
    esac

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

signcommand=''
if [ -n "$DEBSIGN_PROGRAM" ]; then
    signcommand="$DEBSIGN_PROGRAM"
else
    if [ \( -n "$GNUPGHOME" -a -e "$GNUPGHOME" \) -o -e $HOME/.gnupg ] && \
	command -v gpg > /dev/null 2>&1; then
	signcommand=gpg
    elif command -v pgp > /dev/null 2>&1; then
	signcommand=pgp
    fi
fi

if [ -n "$DEBSIGN_SIGNLIKE" ]; then
    forcesigninterface="$DEBSIGN_SIGNLIKE"
fi

while [ $# != 0 ]
do
    value="`echo x\"$1\" | sed -e 's/^x-.//'`"
    case "$1" in
	-spgp)	forcesigninterface=pgp ;;
	-sgpg)	forcesigninterface=gpg ;;
	-p*)	signcommand="$value" ;;
	-m*)	maint="$value" ;;
	-e*)	maint="$value" ;;     # Order matters: -m before -e!
	-k*)	signkey="$value" ;;
	-S)	sourceonly="true" ;;
	-a*)	targetarch="$value" ;;
	-t*)	targetgnusystem="$value" ;;
	--multi) multiarch="true" ;;
	-r*)	if [ -n "$value" ]; then remotehost=$value;
		elif [ $# -lt 1 ]; then
		    echo "$PROGNAME: -r option missing argument!" >&2
		    usage >&2; exit 1;
		else shift; remotehost=$1;
		fi
		# Allow for the [user@]host:filename format
		hostpart="`echo $remotehost | sed -e 's/:.*//'`"
		filepart="`echo $remotehost | sed -e 's/[^:]*:\?//'`"
		if [ -n "$filepart" ]; then
		    remotehost="$hostpart"
		    set -- "$@" "$filepart"
		fi
		;;
	--no-conf|--noconf)
		echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
		exit 1 ;;
	-h|--help)
		usage; exit 0 ;;
	--version)
		version; exit 0 ;;
	-*)	echo "$PROGNAME: Unrecognised option: $1" >&2
		usage >&2; exit 1 ;;
	*)	break ;;
    esac
    shift
done

if [ -z "$signcommand" ]; then
    echo "Could not find a signing program (pgp or gpg)!" >&2
    exit 1
fi

if test -n "$forcesigninterface" ; then
    signinterface=$forcesigninterface
else
    signinterface=$signcommand
fi

if [ "$signinterface" != gpg -a "$signinterface" != pgp ]; then
    echo "Unknown signing interface $signinterface; please specify -spgp or -sgpg" >&2
    exit 1
fi

dosigning() {
    # Do we have to download the changes file?
    if [ -n "$remotehost" ]
    then
	cd ${TMPDIR:-/tmp}
	mkdir debsign.$$ || { echo "$PROGNAME: Can't mkdir!" >&2; exit 1; }
	trap "cleanup_tmpdir" 0 1 2 3 7 10 13 15
	cd debsign.$$

	remotechanges=$changes
	remotedsc=$dsc
	remotecommands=$commands
	remotedir="`perl -e 'chomp($_="'"$dsc"'"); m%/% && s%/[^/]*$%% && print'`"
	changes=`basename "$changes"`
	dsc=`basename "$dsc"`
	commands=`basename "$commands"`

	if [ -n "$changes" ]
	then withecho scp "$remotehost:$remotechanges" "$changes"
	elif [ -n "$dsc" ]
	then withecho scp "$remotehost:$remotedsc" "$dsc"
	else withecho scp "$remotehost:$remotecommands" "$commands"
	fi
    fi

    if [ -n "$changes" ]
    then
	if [ ! -f "$changes" -o ! -r "$changes" ]
	then
	    echo "$PROGNAME: Can't find or can't read changes file $changes!" >&2
	    exit 1
	fi

	check_already_signed "$changes" "changes" && {
	   echo "Leaving current signature unchanged." >&2
	    exit 0
	}
	if [ -n "$maint" ]
	then maintainer="$maint"
	# Try the "Changed-By:" field first
	else maintainer=`sed -n 's/^Changed-By: //p' $changes`
	fi
	if [ -z "$maintainer" ]
	then maintainer=`sed -n 's/^Maintainer: //p' $changes`
	fi

	signas="${signkey:-$maintainer}"

	# Is there a dsc file listed in the changes file?
	if grep -q `basename "$dsc"` "$changes"
	then
	    if [ -n "$remotehost" ]
	    then
		withecho scp "$remotehost:$remotedsc" "$dsc"
	    fi

	    if [ ! -f "$dsc" -o ! -r "$dsc" ]
	    then
		echo "$PROGNAME: Can't find or can't read dsc file $dsc!" >&2
		exit 1
	    fi
	    check_already_signed "$dsc" "dsc" || withecho signfile "$dsc" "$signas"
	    dsc_md5=`md5sum $dsc | cut -d' ' -f1`
	    dsc_sha1=`sha1sum $dsc | cut -d' ' -f1`
	    dsc_sha256=`sha256sum $dsc | cut -d' ' -f1`

	    temp_changes=`mktemp` || {
		echo "$PROGNAME: Unable to create temporary changes file; aborting" >&2
		exit 1
	    }
	    cp "$changes" "$temp_changes"
	    if perl -i -pe 'BEGIN {
		'" \$dsc_file=\"$dsc\"; \$dsc_md5=\"$dsc_md5\"; "'
		'" \$dsc_sha1=\"$dsc_sha1\"; \$dsc_sha256=\"$dsc_sha256\"; "'
		$dsc_size=(-s $dsc_file); ($dsc_base=$dsc_file) =~ s|.*/||;
		$infiles=0; $insha1=0; $insha256=0; $format="";
		}
		if(/^Format:\s+(.*)/) {
		    $format=$1;
		    die "Unrecognised .changes format: $format\n"
			unless $format =~ /^\d+(\.\d+)*$/;
		    $format+=0;
		    die "Unsupported .changes format: $format\n"
			if($format > 1.8 or $format < 1.5);
		}
		/^Files:/ && ($infiles=1,$insha1=0,$insha256=0);
		if(/^Checksums-Sha1:/) {$insha1=1;$infiles=0;$insha256=0;}
		elsif(/^Checksums-Sha256:/) {
		    $insha256=1;$infiles=0;$insha1=0;
		} elsif(/^Checksums-.*?:/) {
		    die "Unknown checksum format: $_\n";
		}
		/^\s*$/ && ($infiles=0,$insha1=0,$insha256=0);
		if ($infiles &&
		    /^ (\S+) (\d+) (\S+) (\S+) \Q$dsc_base\E\s*$/) {
		    $_ = " $dsc_md5 $dsc_size $3 $4 $dsc_base\n";
		    $infiles=0;
		}
		if ($insha1 &&
		    /^ (\S+) (\d+) \Q$dsc_base\E\s*$/) {
		    $_ = " $dsc_sha1 $dsc_size $dsc_base\n";
		    $insha1=0;
		}
		if ($insha256 &&
		    /^ (\S+) (\d+) \Q$dsc_base\E\s*$/) {
		    $_ = " $dsc_sha256 $dsc_size $dsc_base\n";
		    $insha256=0;
		}' "$temp_changes"
	    then
		mv "$temp_changes" "$changes"
	    else
		rm "$temp_changes"
		echo "$PROGNAME: Error processing .changes file (see above)" >&2
		exit 1
	    fi
	    
	    withecho signfile "$changes" "$signas"
	
	    if [ -n "$remotehost" ]
	    then
		withecho scp "$changes" "$dsc" "$remotehost:$remotedir"
		PRECIOUS_FILES=$(($PRECIOUS_FILES - 2))
	    fi

	    echo "Successfully signed dsc and changes files"
	else
	    withecho signfile "$changes" "$signas"

	    if [ -n "$remotehost" ]
	    then
		withecho scp "$changes" "$remotehost:$remotechanges"
		PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	    fi

	    echo "Successfully signed changes file"
	fi
    elif [ -n "$commands" ] # sign .commands file
    then
	if [ ! -f "$commands" -o ! -r "$commands" ]
	then
	    echo "$PROGNAME: Can't find or can't read commands file $commands!" >&2
	    exit 1
	fi

	check_already_signed "$commands" commands && {
	    echo "Leaving current signature unchanged." >&2
	    exit 0
	}
    
    
	# simple validator for .commands files, see
	# ftp://ftp-master.debian.org/pub/UploadQueue/README
	perl -ne 'BEGIN { $uploader = 0; $incommands = 0; }
              END { exit $? if $?;
                    if ($uploader && $incommands) { exit 0; }
                    else { die ".commands file missing Uploader or Commands field\n"; }
                  }
              sub checkcommands {
                  chomp($line=$_[0]);
                  if ($line =~ m%^\s*mv(\s+[^\s/]+){2}\s*$%) { return 0; }
                  if ($line =~ m%^\s*rm(\s+[^\s/]+)+\s*$%) { return 0; }
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
ftp://ftp-master.debian.org/pub/UploadQueue/README
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

	withecho signfile "$commands" "$signas"

	if [ -n "$remotehost" ]
	then
	    withecho scp "$commands" "$remotehost:$remotecommands"
	    PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	fi

	echo "Successfully signed commands file"
    else # only a dsc file to sign; much easier
	if [ ! -f "$dsc" -o ! -r "$dsc" ]
	then
	    echo "$PROGNAME: Can't find or can't read dsc file $dsc!" >&2
	    exit 1
	fi

	check_already_signed "$dsc" dsc && {
	    echo "Leaving current signature unchanged." >&2
	    exit 0
	}
	if [ -n "$maint" ]
	then maintainer="$maint"
	# Try the new "Changed-By:" field first
	else maintainer=`sed -n 's/^Changed-By: //p' $dsc`
	fi
	if [ -z "$maint" ]
	then maintainer=`sed -n 's/^Maintainer: //p' $dsc`
	 fi

	signas="${signkey:-$maintainer}"

	withecho signfile "$dsc" "$signas"

	if [ -n "$remotehost" ]
	then
	    withecho scp "$dsc" "$remotehost:$remotedsc"
	    PRECIOUS_FILES=$(($PRECIOUS_FILES - 1))
	fi

	echo "Successfully signed dsc file"
    fi
}

# If there is a command-line parameter, it is the name of a .changes file
# If not, we must be at the top level of a source tree and will figure
# out its name from debian/changelog
case $# in
    0)	# We have to parse debian/changelog to find the current version
	if [ -n "$remotehost" ]; then
	    echo "$PROGNAME: Need to specify a .changes, .dsc or .commands file location with -r!" >&2
	    exit 1
	fi
	if [ ! -r debian/changelog ]; then
	    echo "$PROGNAME: Must be run from top of source dir or a .changes file given as arg" >&2
	    exit 1
	fi

	mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" \
	    "source package"
	mustsetvar version "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" \
	    "source version"

	if [ "x$sourceonly" = x ]
	then
	    mustsetvar arch "`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`" "build architecture"
	else
	    arch=source
	fi

	sversion=`echo "$version" | perl -pe 's/^\d+://'`
	pv="${package}_${sversion}"
	pva="${package}_${sversion}_${arch}"
	dsc="../$pv.dsc"
	changes="../$pva.changes"
	if [ -n "$multiarch" -o ! -r $changes ]; then
	    changes=$(ls "../${package}_${sversion}_*+*.changes" "../${package}_${sversion}_multi.changes" 2>/dev/null | head -1)
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
		echo "../${package}_${sversion}_*.changes" >&2
		exit 1
	    fi
	fi
	dosigning;
	;;

    *)	while [ $# -gt 0 ]; do
	    case "$1" in
		*.dsc)
		    changes=
		    dsc=$1
		    commands=
		    ;;
	        *.changes)
		    changes=$1
		    dsc=`echo $changes | \
			perl -pe 's/\.changes$/.dsc/; s/(.*)_(.*)_(.*)\.dsc/\1_\2.dsc/'`
		    commands=
		    ;;
		*.commands)
		    changes=
		    dsc=
		    commands=$1
		    ;;
		*)
		    echo "$PROGNAME: Only a .changes, .dsc or .commands file is allowed as argument!" >&2
		    exit 1 ;;
	    esac
	    dosigning
	    shift
	done
	;;
esac

exit 0
