#! /bin/bash
# Simple shell script for driving a remote cowbuilder via ssh
#
# Copyright(C) 2007, 2008, Ron <ron@debian.org>
# This script is distributed according to the terms of the GNU GPL.

set -e

#BUILDD_HOST=
#BUILDD_ROOTCMD=
BUILDD_USER="$(id -un 2>/dev/null)"
BUILDD_ARCH="$(dpkg-architecture -qDEB_BUILD_ARCH 2>/dev/null)"

INCOMING_DIR="cowbuilder-incoming"
RESULT_DIR="/var/cache/pbuilder/result"

#SIGN_KEYID=
#UPLOAD_QUEUE="ftp-master"

REMOTE_SCRIPT="cowssh_it"

for f in /etc/cowpoke.conf ~/.cowpoke .cowpoke "$COWPOKE_CONF"; do [ -r "$f" ] && . "$f"; done

PROGNAME=`basename $0`

version () {
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2007-8 by Ron <ron@debian.org>, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License."
   exit 0
}

usage()
{
    cat 1>&2 <<EOF

cowpoke package.dsc [ arch [ buildd-host [ buildd-username ] ] ]

  Uploads a Debian source package to a cowbuilder host and builds it,
  optionally also signing and uploading the result to an incoming queue.
  The current default configuration is:

   BUILDD_HOST = $BUILDD_HOST
   BUILDD_USER = $BUILDD_USER
   BUILDD_ARCH = $BUILDD_ARCH

  The expected remote paths are:

   INCOMING_DIR = ~$BUILDD_USER/$INCOMING_DIR
   RESULT_DIR   = ${RESULT_DIR:-/}

  The cowbuilder image must have already been created on the build host,
  and the expected remote paths must already exist.  You must have ssh
  access to the build host as 'root' and '$BUILDD_USER'.

EOF

    exit $1
}

[ "$1" = "--help" ] && usage 0;
[ "$1" = "--version" ] && version;
[ $# -gt 0 ] && [ $# -lt 4 ] || usage 1

if [ -z "$REMOTE_SCRIPT" ]; then
    echo "No remote script name set.  Aborted."
    exit 1
fi

case "$1" in
    *.dsc) ;;
    *) echo "ERROR: '$1' is not a package .dsc file"
       usage 1 ;;
esac
if ! [ -r "$1" ]; then
    echo "ERROR: '$1' not found."
    exit 1
fi

[ -z "$2" ] || BUILDD_ARCH="$2"
[ -z "$3" ] || BUILDD_HOST="$3"
[ -z "$4" ] || BUILDD_USER="$4"

if [ -z "$BUILDD_ARCH" ]; then
    echo "No BUILDD_ARCH set.  Aborted."
    exit 1
fi
if [ -z "$BUILDD_HOST" ]; then
    echo "No BUILDD_HOST set.  Aborted."
    exit 1
fi
if [ -z "$BUILDD_USER" ]; then
    echo "No BUILDD_USER set.  Aborted."
    exit 1
fi

if [ -e "$REMOTE_SCRIPT" ]; then
    echo "$REMOTE_SCRIPT file already exists and will be overwritten."
    echo -n "Do you wish to continue (Y/n)? "
    read -e yesno
    case "$yesno" in
	N* | n*)
	    echo "Ok, bailing out."
	    echo "You should set the REMOTE_SCRIPT variable to some other value"
	    echo "if this name conflicts with something you already expect to use"
	    exit 1
	    ;;
	*) ;;
    esac
fi

PACKAGE="$(basename $1 .dsc)"
CHANGES="$BUILDD_ARCH.changes"
LOGFILE="build.${PACKAGE}_$BUILDD_ARCH.log"
DATE="$(date +%Y%m%d 2>/dev/null)"

cat > "$REMOTE_SCRIPT" <<-EOF
	#! /bin/bash
	# cowpoke generated remote worker script.
	# Normally this should have been deleted already, you can safely remove it now.


	# Sort the list of old changes files for this package to try and
	# determine the most recent one preceding this version.  We will
	# debdiff to this revision in the final sanity checks if one exists.
	# This is adapted from the insertion sort trickery in git-debimport.

	OLD_CHANGES="\$(find "$RESULT_DIR/" -maxdepth 1 -type f \\
	                     -name "${PACKAGE%%_*}_*_$CHANGES" 2>/dev/null \\
	                | sort 2>/dev/null)"
	P=( \$OLD_CHANGES )
	count=\${#P[*]}
	COMPARE="dpkg --compare-versions"

	for(( i=1; i < count; ++i )) do
	    j=i
	    #echo "was \$i: \${P[i]}"
	    while ((\$j)) && \$COMPARE "\${P[j-1]%_$CHANGES}" gt "\${P[i]%_$CHANGES}"; do ((--j)); done
	    ((i==j)) || P=( \${P[@]:0:j} \${P[i]} \${P[j]} \${P[@]:j+1:i-(j+1)} \${P[@]:i+1} )
	done
	#for(( i=1; i < count; ++i )) do echo "now \$i: \${P[i]}"; done

	OLD_CHANGES=
	for(( i=count-1; i >= 0; --i )) do
	    if [ "\${P[i]}" != "$RESULT_DIR/${PACKAGE}_$CHANGES" ]; then 
	        OLD_CHANGES="\${P[i]}"
	        break
	    fi
	done


	set -eo pipefail

	if ! [ -e "cowbuilder-update-log-$DATE" ]; then
	    cowbuilder --update 2>&1 | tee "cowbuilder-update-log-$DATE"
	fi
	cowbuilder --build "$(basename $1)" 2>&1 | tee "$LOGFILE"

	set +eo pipefail


	echo >> "$LOGFILE"
	echo "lintian $RESULT_DIR/${PACKAGE}_$CHANGES" >> "$LOGFILE"
	( su "$BUILDD_USER" -c "lintian \"$RESULT_DIR/${PACKAGE}_$CHANGES\"" ) 2>&1 \\
	| tee -a "$LOGFILE"

	if [ -n "\$OLD_CHANGES" ]; then
	    echo >> "$LOGFILE"
	    echo "debdiff \$OLD_CHANGES ${PACKAGE}_$CHANGES" >> "$LOGFILE"
	    ( su "$BUILDD_USER" -c "debdiff \"\$OLD_CHANGES\" \"$RESULT_DIR/${PACKAGE}_$CHANGES\"" ) 2>&1 \\
	    | tee -a "$LOGFILE"
	else
	    echo >> "$LOGFILE"
	    echo "No previous packages for $BUILDD_ARCH to compare" >> "$LOGFILE"
	fi

EOF
chmod 755 "$REMOTE_SCRIPT"

dcmd scp $1 "$REMOTE_SCRIPT" "$BUILDD_USER@$BUILDD_HOST:$INCOMING_DIR"

if [ -z "$BUILDD_ROOTCMD" ]; then
    ssh "root@$BUILDD_HOST" "cd ~$BUILDD_USER/\"$INCOMING_DIR\" && \"./$REMOTE_SCRIPT\" && rm -f \"./$REMOTE_SCRIPT\""
else
    ssh -t "$BUILDD_USER@$BUILDD_HOST" "cd \"$INCOMING_DIR\" && $BUILDD_ROOTCMD \"./$REMOTE_SCRIPT\" && rm -f \"./$REMOTE_SCRIPT\""
fi

echo
echo "Build completed."

if [ -n "$SIGN_KEYID" ]; then
    while true; do
	echo -n "Sign $PACKAGE with key '$SIGN_KEYID' (yes/no)? "
	read -e yesno
	case "$yesno" in
	    YES | yes)
		if [ -z "$BUILDD_ROOTCMD" ] ; then
		    debsign "-k$SIGN_KEYID" -r "root@$BUILDD_HOST" "$RESULT_DIR/${PACKAGE}_$CHANGES"
		else
		    debsign "-k$SIGN_KEYID" -r "$BUILDD_USER@$BUILDD_HOST" "$RESULT_DIR/${PACKAGE}_$CHANGES"
		fi

		if [ -n "$UPLOAD_QUEUE" ]; then
		    while true; do
			echo -n "Upload $PACKAGE to '$UPLOAD_QUEUE' (yes/no)? "
			read -e upload
			case "$upload" in
			    YES | yes)
				ssh "${BUILDD_USER}@$BUILDD_HOST" \
				    "cd \"$RESULT_DIR/\" && dput \"$UPLOAD_QUEUE\" \"${PACKAGE}_$CHANGES\""
				break 2
				;;

			    NO | no)
				echo "Package upload skipped."
				break 2
				;;
			    *)
				echo "Please answer 'yes' or 'no'"
				;;
			esac
		    done
		fi
		break
		;;

	    NO | no)
		echo "Package signing skipped."
		break
		;;
	    *)
		echo "Please answer 'yes' or 'no'"
		;;
	esac
    done
fi

rm -f "$REMOTE_SCRIPT"

# vi:sts=4:sw=4:noet:foldmethod=marker
