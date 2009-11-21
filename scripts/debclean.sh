#! /bin/bash

PROGNAME=`basename $0`
MODIFIED_CONF_MSG='Default settings modified by devscripts configuration files:'

usage () {
    echo \
"Usage: $PROGNAME [options]
  Clean all debian build trees under current directory.

  Options:
    --cleandebs    Also remove all .deb, .changes and .build
                   files from the parent of each build tree

    --nocleandebs  Don't remove the .deb etc. files (default)

    --check-dirname-level N
                   How much to check directory names before cleaning trees:
                   N=0   never
                   N=1   only if program changes directory (default)
                   N=2   always

    --check-dirname-regex REGEX
                   What constitutes a matching directory name; REGEX is
                   a Perl regular expression; the string \`PACKAGE' will
                   be replaced by the package name; see manpage for details
                   (default: 'PACKAGE(-.+)?')

    --no-conf, --noconf
                   Do not read devscripts config files;
                   must be the first option given

    -d             Do not run dpkg-checkbuilddeps to check build dependencies

    --help         Display this help message and exit

    --version      Display version information

$MODIFIED_CONF_MSG"
}

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999 by Julian Gilbey, all rights reserved.
Original code by Christoph Lameter.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License, version 2 or later."
}

# Boilerplate: set config variables
DEFAULT_DEBCLEAN_CLEANDEBS=no
DEFAULT_DEVSCRIPTS_CHECK_DIRNAME_LEVEL=1
DEFAULT_DEVSCRIPTS_CHECK_DIRNAME_REGEX='PACKAGE(-.+)?'
VARS="DEBCLEAN_CLEANDEBS DEVSCRIPTS_CHECK_DIRNAME_LEVEL DEVSCRIPTS_CHECK_DIRNAME_REGEX"


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

	set | egrep '^(DEBCLEAN|DEVSCRIPTS)_')

    # check sanity
    case "$DEBCLEAN_CLEANDEBS" in
	yes|no) ;;
	*) DEBCLEAN_CLEANDEBS=no ;;
    esac
    case "$DEVSCRIPTS_CHECK_DIRNAME_LEVEL" in
	0|1|2) ;;
	*) DEVSCRIPTS_CHECK_DIRNAME_LEVEL=1 ;;
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

# synonyms
CHECK_DIRNAME_LEVEL="$DEVSCRIPTS_CHECK_DIRNAME_LEVEL"
CHECK_DIRNAME_REGEX="$DEVSCRIPTS_CHECK_DIRNAME_REGEX"

# Need -o option to getopt or else it doesn't work
TEMP=$(getopt -s bash -o "" -o d \
	--long cleandebs,nocleandebs,no-cleandebs \
	--long no-conf,noconf \
	--long check-dirname-level:,check-dirname-regex: \
	--long help,version -n "$PROGNAME" -- "$@")
if [ $? != 0 ] ; then exit 1 ; fi

eval set -- $TEMP

# Process Parameters
while [ "$1" ]; do
    case $1 in
    --cleandebs) DEBCLEAN_CLEANDEBS=yes ;;
    --nocleandebs|--no-cleandebs) DEBCLEAN_CLEANDEBS=no ;;
    --check-dirname-level)
	shift
        case "$1" in
	0|1|2) CHECK_DIRNAME_LEVEL=$1 ;;
	*) echo "$PROGNAME: unrecognised --check-dirname-level value (allowed are 0,1,2)" >&2
	   exit 1 ;;
        esac
	;;
    -d)
    	CHECKBUILDDEP="-d" ;;
    --check-dirname-regex)
	shift; 	CHECK_DIRNAME_REGEX="$1" ;;
    --no-conf|--noconf)
	echo "$PROGNAME: $1 is only acceptable as the first command-line option!" >&2
	exit 1 ;;
    --help) usage; exit 0 ;;
    --version) version; exit 0 ;;
    --)	shift; break ;;
    *) echo "$PROGNAME: bug in option parser, sorry!" >&2 ; exit 1 ;;
    esac
    shift
done

# Still going?
if [ $# -gt 0 ]; then
    echo "$PROGNAME takes no non-option arguments;" >&2
    echo "try $PROGNAME --help for usage information" >&2
    exit 1
fi


# Script to clean up debian directories

OPWD="`pwd`"
for i in `find . -type d -name "debian"`; do
    (  # subshell to not lose where we are
    DIR=${i%/debian}
    echo "Cleaning in directory $DIR"
    cd $DIR

    # Clean up the source package, but only if the directory looks like
    # a genuine build tree
    if [ ! -f debian/changelog ]; then
	echo "Directory $DIR: contains no debian/changelog, skipping" >&2
	exit
    fi
    package="`dpkg-parsechangelog | sed -n 's/^Source: //p'`"
    if [ -z "$package" ]; then
	echo "Directory $DIR: unable to determine package name, skipping" >&2
	exit
    fi

    # let's test the directory name if appropriate
    if [ $CHECK_DIRNAME_LEVEL -eq 2 -o \
	\( $CHECK_DIRNAME_LEVEL -eq 1 -a "$OPWD" != "`pwd`" \) ]; then
	if ! perl -MFile::Basename -w \
	    -e "\$pkg='$package'; \$re='$CHECK_DIRNAME_REGEX';" \
	    -e '$re =~ s/PACKAGE/\\Q$pkg\\E/g; $pwd=`pwd`; chomp $pwd;' \
	    -e 'if ($re =~ m%/%) { eval "exit (\$pwd =~ /^$re\$/ ? 0:1);"; }' \
	    -e 'else { eval "exit (basename(\$pwd) =~ /^$re\$/ ? 0:1);"; }'
	then
	    echo "Full directory path `pwd` does not match package name, skipping." >&2
	    echo "Run $progname --help for more information on directory name matching." >&2
	    exit
	fi
    fi

    # We now know we're OK and debuild won't complain about the dirname
    debuild $CHECKBUILDDEP clean

    # Clean up the package related files
    if [ "$DEBCLEAN_CLEANDEBS" = yes ]; then
	cd ..
	rm -f *.changes *.deb *.build
    fi
    )
done
