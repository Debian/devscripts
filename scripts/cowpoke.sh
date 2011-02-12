#! /bin/bash
# Simple shell script for driving a remote cowbuilder via ssh
#
# Copyright(C) 2007, 2008, 2009, Ron <ron@debian.org>
# This script is distributed according to the terms of the GNU GPL.

set -e

#BUILDD_HOST=
#BUILDD_USER=
BUILDD_ARCH="$(dpkg-architecture -qDEB_BUILD_ARCH 2>/dev/null)"

# The 'default' dist is whatever cowbuilder is locally configured for
BUILDD_DIST="default"

INCOMING_DIR="cowbuilder-incoming"
PBUILDER_BASE="/var/cache/pbuilder"

#SIGN_KEYID=
#UPLOAD_QUEUE="ftp-master"
BUILDD_ROOTCMD="sudo"

REMOTE_SCRIPT="cowssh_it"
DEBOOTSTRAP="cdebootstrap"

for f in /etc/cowpoke.conf ~/.cowpoke .cowpoke "$COWPOKE_CONF"; do [ -r "$f" ] && . "$f"; done


get_archdist_vars()
{
    _ARCHDIST_OPTIONS="RESULT_DIR BASE_PATH"
    _RESULT_DIR="result"
    _BASE_PATH="base.cow"

    for arch in $BUILDD_ARCH; do
	for dist in $BUILDD_DIST; do
	    for var in $_ARCHDIST_OPTIONS; do
		if [ "$1" = "display" ]; then
		    if [ -z "$(eval echo "\$${arch}_${dist}_${var}")" ]; then
			echo "   ${arch}_${dist}_${var} = $PBUILDER_BASE/$arch/$dist/$(eval echo "\$_$var")"
		    else
			echo "   ${arch}_${dist}_${var} = $(eval echo "\$${arch}_${dist}_${var}")"
		    fi
		else
		    if [ -z "$(eval echo "\$${arch}_${dist}_${var}")" ]; then
			echo "${arch}_${dist}_${var}=\"$PBUILDER_BASE/$arch/$dist/$(eval echo "\$_$var")\""
		    else
			echo "${arch}_${dist}_${var}=\"$(eval echo "\$${arch}_${dist}_${var}")\""
		    fi
		fi
	    done
	done
    done
}

PROGNAME="$(basename $0)"
version ()
{
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2007-9 by Ron <ron@debian.org>, all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the
GNU General Public License."
    exit 0
}

usage()
{
    cat 1>&2 <<EOF

cowpoke [options] package.dsc

  Uploads a Debian source package to a cowbuilder host and builds it,
  optionally also signing and uploading the result to an incoming queue.
  The following options are supported:

   --arch="arch"         Specify the Debian architecture(s) to build for.
   --dist="dist"         Specify the Debian distribution(s) to build for.
   --buildd="host"       Specify the remote host to build on.
   --buildd-user="name"  Specify the remote user to build as.
   --create              Create the remote cowbuilder root if necessary.

  The current default configuration is:

   BUILDD_HOST = $BUILDD_HOST
   BUILDD_USER = $BUILDD_USER
   BUILDD_ARCH = $BUILDD_ARCH
   BUILDD_DIST = $BUILDD_DIST

  The expected remote paths are:

   INCOMING_DIR  = $INCOMING_DIR
   PBUILDER_BASE = ${PBUILDER_BASE:-/}

$(get_archdist_vars display)

  The cowbuilder image must have already been created on the build host
  and the expected remote paths must already exist if the --create option
  is not passed.  You must have ssh access to the build host as BUILDD_USER
  if that is set, else as the user executing cowpoke or a user specified
  in your ssh config for '$BUILDD_HOST'.
  That user must be able to execute cowbuilder as root using '$BUILDD_ROOTCMD'.

EOF

    exit $1
}


for arg; do
    case "$arg" in
	--arch=*)
	    BUILDD_ARCH="${arg#*=}"
	    ;;

	--dist=*)
	    BUILDD_DIST="${arg#*=}"
	    ;;

	--buildd=*)
	    BUILDD_HOST="${arg#*=}"
	    ;;

	--buildd-user=*)
	    BUILDD_USER="${arg#*=}"
	    ;;

	--create)
	    CREATE_COW="yes"
	    ;;

	--dpkg-opts=*)
	    DEBBUILDOPTS="--debbuildopts \"${arg#*=}\""
	    ;;

	*.dsc)
	    DSC="$arg"
	    ;;

	--help)
	    usage 0
	    ;;

	--version)
	    version
	    ;;

	*)
	    echo "ERROR: unrecognised option '$arg'"
	    usage 1
	    ;;
    esac
done

if [ -z "$REMOTE_SCRIPT" ]; then
    echo "No remote script name set.  Aborted."
    exit 1
fi
if [ -z "$DSC" ]; then
    echo "ERROR: No package .dsc specified"
    usage 1
fi
if ! [ -r "$DSC" ]; then
    echo "ERROR: '$DSC' not found."
    exit 1
fi
if [ -z "$BUILDD_ARCH" ]; then
    echo "No BUILDD_ARCH set.  Aborted."
    exit 1
fi
if [ -z "$BUILDD_HOST" ]; then
    echo "No BUILDD_HOST set.  Aborted."
    exit 1
fi
if [ -z "$BUILDD_ROOTCMD" ]; then
    echo "No BUILDD_ROOTCMD set.  Aborted."
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

[ -z "$BUILDD_USER" ] || BUILDD_USER="$BUILDD_USER@"

PACKAGE="$(basename $DSC .dsc)"
DATE="$(date +%Y%m%d 2>/dev/null)"


cat > "$REMOTE_SCRIPT" <<-EOF
	#! /bin/bash
	# cowpoke generated remote worker script.
	# Normally this should have been deleted already, you can safely remove it now.

	$(get_archdist_vars)

	for arch in $BUILDD_ARCH; do
	  for dist in $BUILDD_DIST; do

	    echo " ------- Begin build for \$arch \$dist -------"

	    CHANGES="\$arch.changes"
	    LOGFILE="$INCOMING_DIR/build.${PACKAGE}_\$arch.\$dist.log"
	    UPDATELOG="$INCOMING_DIR/cowbuilder-\${arch}-\${dist}-update-log-$DATE"
	    RESULT_DIR="\$(eval echo "\\\$\${arch}_\${dist}_RESULT_DIR")"
	    BASE_PATH="\$(eval echo "\\\$\${arch}_\${dist}_BASE_PATH")"

	    # Sort the list of old changes files for this package to try and
	    # determine the most recent one preceding this version.  We will
	    # debdiff to this revision in the final sanity checks if one exists.
	    # This is adapted from the insertion sort trickery in git-debimport.

	    OLD_CHANGES="\$(find "\$RESULT_DIR/" -maxdepth 1 -type f \\
	                         -name "${PACKAGE%%_*}_*_\$CHANGES" 2>/dev/null \\
	                    | sort 2>/dev/null)"
	    P=( \$OLD_CHANGES )
	    count=\${#P[*]}
	    COMPARE="dpkg --compare-versions"

	    for(( i=1; i < count; ++i )) do
	        j=i
	        #echo "was \$i: \${P[i]}"
	        while ((\$j)) && \$COMPARE "\${P[j-1]%_*.changes}" gt "\${P[i]%_*.changes}"; do ((--j)); done
	        ((i==j)) || P=( \${P[@]:0:j} \${P[i]} \${P[j]} \${P[@]:j+1:i-(j+1)} \${P[@]:i+1} )
	    done
	    #for(( i=1; i < count; ++i )) do echo "now \$i: \${P[i]}"; done

	    OLD_CHANGES=
	    for(( i=count-1; i >= 0; --i )) do
	        if [ "\${P[i]}" != "\$RESULT_DIR/${PACKAGE}_\$CHANGES" ]; then
	            OLD_CHANGES="\${P[i]}"
	            break
	        fi
	    done


	    set -eo pipefail

	    if ! [ -e "\$BASE_PATH" ]; then
	        if [ "$CREATE_COW" = "yes" ]; then
	            mkdir -p "\$RESULT_DIR"
	            mkdir -p "\$(dirname \$BASE_PATH)"
	            mkdir -p "$PBUILDER_BASE/aptcache"
	            $BUILDD_ROOTCMD cowbuilder --create --distribution \$dist       \\
	                                       --basepath "\$BASE_PATH"             \\
	                                       --aptcache "$PBUILDER_BASE/aptcache" \\
	                                       --debootstrap "$DEBOOTSTRAP"         \\
	                                       --debootstrapopts --arch="\$arch"    \\
	            2>&1 | tee "\$UPDATELOG"
	        else
	            echo "SKIPPING \$dist/\$arch build, '\$BASE_PATH' does not exist" | tee "\$LOGFILE"
	            echo "         use the cowpoke --create option to bootstrap a new build root" | tee -a "\$LOGFILE"
	            continue
	        fi
	    elif ! [ -e "\$UPDATELOG" ]; then
	        $BUILDD_ROOTCMD cowbuilder --update --basepath "\$BASE_PATH"    \\
	                                   --aptcache "$PBUILDER_BASE/aptcache" \\
	                                   --autocleanaptcache                  \\
	        2>&1 | tee "\$UPDATELOG"
	    fi
	    $BUILDD_ROOTCMD cowbuilder --build --basepath "\$BASE_PATH"      \\
	                               --aptcache "$PBUILDER_BASE/aptcache"  \\
	                               --buildplace "$PBUILDER_BASE/build"   \\
	                               --buildresult "\$RESULT_DIR"          \\
	                               $DEBBUILDOPTS                         \\
	                               "$INCOMING_DIR/$(basename $DSC)" 2>&1 \\
	    | tee "\$LOGFILE"

	    set +eo pipefail


	    echo >> "\$LOGFILE"
	    echo "lintian \$RESULT_DIR/${PACKAGE}_\$CHANGES" >> "\$LOGFILE"
	    lintian "\$RESULT_DIR/${PACKAGE}_\$CHANGES" 2>&1 | tee -a "\$LOGFILE"

	    if [ -n "\$OLD_CHANGES" ]; then
	        echo >> "\$LOGFILE"
	        echo "debdiff \$OLD_CHANGES ${PACKAGE}_\$CHANGES" >> "\$LOGFILE"
	        debdiff "\$OLD_CHANGES" "\$RESULT_DIR/${PACKAGE}_\$CHANGES" 2>&1 \\
	        | tee -a "\$LOGFILE"
	    else
	        echo >> "\$LOGFILE"
	        echo "No previous packages for \$dist/\$arch to compare" >> "\$LOGFILE"
	    fi

	  done
	done

EOF
chmod 755 "$REMOTE_SCRIPT"


if ! dcmd rsync -vP $DSC "$REMOTE_SCRIPT" "$BUILDD_USER$BUILDD_HOST:$INCOMING_DIR";
then
    dcmd scp $DSC "$REMOTE_SCRIPT" "$BUILDD_USER$BUILDD_HOST:$INCOMING_DIR"
fi

ssh -t "$BUILDD_USER$BUILDD_HOST" "\"$INCOMING_DIR/$REMOTE_SCRIPT\" && rm -f \"$INCOMING_DIR/$REMOTE_SCRIPT\""

echo
echo "Build completed."

if [ -n "$SIGN_KEYID" ]; then
    for arch in $BUILDD_ARCH; do
      CHANGES="$arch.changes"
      for dist in $BUILDD_DIST; do

	RESULT_DIR="$(eval echo "\$${arch}_${dist}_RESULT_DIR")"
	[ -n "$RESULT_DIR" ] || RESULT_DIR="$PBUILDER_BASE/$arch/$dist/result"

	_desc="$dist/$arch"
	[ "$dist" != "default" ] || _desc="$arch"

	while true; do
	    echo -n "Sign $_desc $PACKAGE with key '$SIGN_KEYID' (yes/no)? "
	    read -e yesno
	    case "$yesno" in
		YES | yes)
		    debsign "-k$SIGN_KEYID" -r "$BUILDD_USER$BUILDD_HOST" "$RESULT_DIR/${PACKAGE}_$CHANGES"

		    if [ -n "$UPLOAD_QUEUE" ]; then
			while true; do
			    echo -n "Upload $_desc $PACKAGE to '$UPLOAD_QUEUE' (yes/no)? "
			    read -e upload
			    case "$upload" in
				YES | yes)
				    ssh "$BUILDD_USER$BUILDD_HOST" \
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

      done
    done
fi

rm -f "$REMOTE_SCRIPT"

# vi:sts=4:sw=4:noet:foldmethod=marker
