#!/bin/bash
# Simple shell script for driving a remote cowbuilder via ssh
#
# Copyright(C) 2007, 2008, 2009, 2011, 2012, 2014, Ron <ron@debian.org>
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
    _ARCHDIST_OPTIONS="RESULT_DIR BASE_PATH BASE_DIST CREATE_OPTS UPDATE_OPTS BUILD_OPTS SIGN_KEYID UPLOAD_QUEUE"
    _RESULT_DIR="result"
    _BASE_PATH="base.cow"

    for arch in $BUILDD_ARCH; do
	for dist in $BUILDD_DIST; do
	    for var in $_ARCHDIST_OPTIONS; do
		eval "val=( \"\${${arch}_${dist}_${var}[@]}\" )"

		if [ "$1" = "display" ]; then
		    case $var in
			RESULT_DIR | BASE_PATH )
			    [ ${#val[@]} -gt 0 ] || eval "val=\"$PBUILDER_BASE/$arch/$dist/\$_$var\""
			    echo "   ${arch}_${dist}_${var} = $val"
			    ;;

			*_OPTS )
			    # Don't display these if they are overridden on the command line.
			    eval "override=( \"\${OVERRIDE_${var}[@]}\" )"
			    [ ${#override[@]} -gt 0 ] || [ ${#val[@]} -eq 0 ] ||
				echo "   ${arch}_${dist}_${var} =$(printf " '%s'" "${val[@]}")"
			    ;;

			* )
			    [ ${#val[@]} -eq 0 ] || echo "   ${arch}_${dist}_${var} = $val"
			    ;;
		    esac
		else
		    case $var in
			RESULT_DIR | BASE_PATH )
			    # These are always a single value, and must always be set,
			    # either by the user or to their default value.
			    [ ${#val[@]} -gt 0 ] || eval "val=\"$PBUILDER_BASE/$arch/$dist/\$_$var\""
			    echo "${arch}_${dist}_${var}='$val'"
			    ;;

			*_OPTS )
			    # These may have zero, one, or many values which we must not word-split.
			    # They can safely remain unset if there are no values.
			    #
			    # We don't need to worry about the command line overrides here,
			    # they will be taken care of in the remote script.
			    [ ${#val[@]} -eq 0 ] ||
				echo "${arch}_${dist}_${var}=($(printf " %q" "${val[@]}") )"
			    ;;

			SIGN_KEYID | UPLOAD_QUEUE )
			    # We don't need these in the remote script
			    ;;

			* )
			    # These may have zero or one value.
			    # They can safely remain unset if there are no values.
			    [ ${#val[@]} -eq 0 ] || echo "${arch}_${dist}_${var}='$val'"
			    ;;
		    esac
		fi
	    done
	done
    done
}

display_override_vars()
{
    _OVERRIDE_OPTIONS="CREATE_OPTS UPDATE_OPTS BUILD_OPTS"

    for var in $_OVERRIDE_OPTIONS; do
	eval "override=( \"\${OVERRIDE_${var}[@]}\" )"
	[ ${#override[@]} -eq 0 ] || echo "   $var =$(printf " '%s'" "${override[@]}")"
    done
}


PROGNAME="$(basename $0)"
version ()
{
    echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is Copyright 2007-2014, Ron <ron@debian.org>.
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
   --return[="path"]     Copy results of the build to 'path'.  If path is
                         not specified, return them to the current directory.
   --no-return           Do not copy results of the build to RETURN_DIR
                         (overriding a path set for it in the config files).

  The current default configuration is:

   BUILDD_HOST   = $BUILDD_HOST
   BUILDD_USER   = $BUILDD_USER
   BUILDD_ARCH   = $BUILDD_ARCH
   BUILDD_DIST   = $BUILDD_DIST
   RETURN_DIR    = $RETURN_DIR
   SIGN_KEYID    = $SIGN_KEYID
   UPLOAD_QUEUE  = $UPLOAD_QUEUE

  The expected remote paths are:

   INCOMING_DIR  = $INCOMING_DIR
   PBUILDER_BASE = ${PBUILDER_BASE:-/}

$(get_archdist_vars display)
$(display_override_vars)

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

	--return=*)
	    RETURN_DIR="${arg#*=}"
	    ;;

	--return)
	    RETURN_DIR=.
	    ;;

	--no-return)
	    RETURN_DIR=
	    ;;

	--dpkg-opts=*)
	    # This one is a bit tricky, given the combination of the calling convention here,
	    # the calling convention for cowbuilder, and the behaviour of things that might
	    # pass this option to us.  Some things, like when we are called from the gitpkg
	    # hook using options from git-config, will preserve any quoting that was used in
	    # the .gitconfig file, which is natural for anyone to want to use in a construct
	    # like: options = --dpkg-opts='-uc -us -j6'.  People are going to cringe if we
	    # tell them they must not use quotes there no matter how much it may 'make sense'
	    # if you know too much about the internals.  And it will only get worse when we
	    # then tell them they must quote it like that if they type it directly in their
	    # shell ...
	    #
	    # So we do the only thing that seems sensible, and try to Deal With It here.
	    # If the outermost characters are paired quotes, we manually strip them off.
	    # We don't want to let the shell do quote removal, since that might change a
	    # part of this which we don't want modified.
	    # We collect however many sets of those we are passed in an array, which we'll
	    # then combine back into a single argument at the final point of use.
	    #
	    # Which _should_ DTRT for anyone who isn't trying to blow this up deliberately
	    # any maybe will still do it for them too in spite of their efforts. But unless
	    # someone finds a sensible case this fails on, I'm not going to cry over people
	    # who want to stuff up their own system with input they created themselves.
	    val=${arg#*=}
	    [[ $val == \'*\' || $val == \"*\" ]] && val=${val:1:-1}
	    DEBBUILDOPTS[${#DEBBUILDOPTS[@]}]=$val
	    ;;

	--create-opts=*)
	    OVERRIDE_CREATE_OPTS[${#OVERRIDE_CREATE_OPTS[@]}]="${arg#*=}"
	    ;;

	--update-opts=*)
	    OVERRIDE_UPDATE_OPTS[${#OVERRIDE_UPDATE_OPTS[@]}]="${arg#*=}"
	    ;;

	--build-opts=*)
	    OVERRIDE_BUILD_OPTS[${#OVERRIDE_BUILD_OPTS[@]}]="${arg#*=}"
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
	#!/bin/bash
	# cowpoke generated remote worker script.
	# Normally this should have been deleted already, you can safely remove it now.

	compare_changes()
	{
	    p1="\${1%_*.changes}"
	    p2="\${2%_*.changes}"
	    p1="\${p1##*_}"
	    p2="\${p2##*_}"

	    dpkg --compare-versions "\$p1" gt "\$p2"
	}

	$(get_archdist_vars)

	for arch in $BUILDD_ARCH; do
	  for dist in $BUILDD_DIST; do

	    echo " ------- Begin build for \$arch \$dist -------"

	    CHANGES="\$arch.changes"
	    LOGFILE="$INCOMING_DIR/build.${PACKAGE}_\$arch.\$dist.log"
	    UPDATELOG="$INCOMING_DIR/cowbuilder-\${arch}-\${dist}-update-log-$DATE"
	    eval "RESULT_DIR=\"\\\$\${arch}_\${dist}_RESULT_DIR\""
	    eval "BASE_PATH=\"\\\$\${arch}_\${dist}_BASE_PATH\""
	    eval "BASE_DIST=\"\\\$\${arch}_\${dist}_BASE_DIST\""
	    eval "CREATE_OPTS=( \"\\\${\${arch}_\${dist}_CREATE_OPTS[@]}\" )"
	    eval "UPDATE_OPTS=( \"\\\${\${arch}_\${dist}_UPDATE_OPTS[@]}\" )"
	    eval "BUILD_OPTS=( \"\\\${\${arch}_\${dist}_BUILD_OPTS[@]}\" )"

	    [ -n "\$BASE_DIST" ]                  || BASE_DIST=\$dist
	    [ ${#OVERRIDE_CREATE_OPTS[@]} -eq 0 ] || CREATE_OPTS=("${OVERRIDE_CREATE_OPTS[@]}")
	    [ ${#OVERRIDE_UPDATE_OPTS[@]} -eq 0 ] || UPDATE_OPTS=("${OVERRIDE_UPDATE_OPTS[@]}")
	    [ ${#OVERRIDE_BUILD_OPTS[@]}  -eq 0 ] || BUILD_OPTS=("${OVERRIDE_BUILD_OPTS[@]}")
	    [ ${#DEBBUILDOPTS[*]} -eq 0 ]         || DEBBUILDOPTS=("--debbuildopts" "${DEBBUILDOPTS[*]}")


	    # Sort the list of old changes files for this package to try and
	    # determine the most recent one preceding this version.  We will
	    # debdiff to this revision in the final sanity checks if one exists.
	    # This is adapted from the insertion sort trickery in git-debimport.

	    OLD_CHANGES="\$(find "\$RESULT_DIR/" -maxdepth 1 -type f \\
	                         -name "${PACKAGE%%_*}_*_\$CHANGES" 2>/dev/null \\
	                    | sort 2>/dev/null)"
	    P=( \$OLD_CHANGES )
	    count=\${#P[*]}

	    for(( i=1; i < count; ++i )) do
	        j=i
	        #echo "was \$i: \${P[i]}"
	        while ((\$j)) && compare_changes "\${P[j-1]}" "\${P[i]}"; do ((--j)); done
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
	            $BUILDD_ROOTCMD cowbuilder --create --distribution \$BASE_DIST  \\
	                                       --basepath "\$BASE_PATH"             \\
	                                       --aptcache "$PBUILDER_BASE/aptcache" \\
	                                       --debootstrap "$DEBOOTSTRAP"         \\
	                                       --debootstrapopts --arch="\$arch"    \\
	                                       "\${CREATE_OPTS[@]}"                 \\
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
	                                   "\${UPDATE_OPTS[@]}"                 \\
	        2>&1 | tee "\$UPDATELOG"
	    fi
	    $BUILDD_ROOTCMD cowbuilder --build --basepath "\$BASE_PATH"      \\
	                               --aptcache "$PBUILDER_BASE/aptcache"  \\
	                               --buildplace "$PBUILDER_BASE/build"   \\
	                               --buildresult "\$RESULT_DIR"          \\
	                               "\${DEBBUILDOPTS[@]}"                 \\
	                               "\${BUILD_OPTS[@]}"                   \\
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

for arch in $BUILDD_ARCH; do
    CHANGES="$arch.changes"
    for dist in $BUILDD_DIST; do

	eval "sign_keyid=\"\$${arch}_${dist}_SIGN_KEYID\""
	[ -n "$sign_keyid" ] || sign_keyid="$SIGN_KEYID"
	[ -n "$sign_keyid" ] || continue

	eval "RESULT_DIR=\"\$${arch}_${dist}_RESULT_DIR\""
	[ -n "$RESULT_DIR" ] || RESULT_DIR="$PBUILDER_BASE/$arch/$dist/result"

	_desc="$dist/$arch"
	[ "$dist" != "default" ] || _desc="$arch"

	while true; do
	    echo -n "Sign $_desc $PACKAGE with key '$sign_keyid' (yes/no)? "
	    read -e yesno
	    case "$yesno" in
		YES | yes)
		    debsign "-k$sign_keyid" -r "$BUILDD_USER$BUILDD_HOST" "$RESULT_DIR/${PACKAGE}_$CHANGES"

		    eval "upload_queue=\"\$${arch}_${dist}_UPLOAD_QUEUE\""
		    [ -n "$upload_queue" ] || upload_queue="$UPLOAD_QUEUE"

		    if [ -n "$upload_queue" ]; then
			while true; do
			    echo -n "Upload $_desc $PACKAGE to '$upload_queue' (yes/no)? "
			    read -e upload
			    case "$upload" in
				YES | yes)
				    ssh "$BUILDD_USER$BUILDD_HOST" \
					"cd \"$RESULT_DIR/\" && dput \"$upload_queue\" \"${PACKAGE}_$CHANGES\""
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

if [ -n "$RETURN_DIR" ]; then
    for arch in $BUILDD_ARCH; do
      CHANGES="$arch.changes"
      for dist in $BUILDD_DIST; do

	eval "RESULT_DIR=\"\$${arch}_${dist}_RESULT_DIR\""
	[ -n "$RESULT_DIR" ] || RESULT_DIR="$PBUILDER_BASE/$arch/$dist/result"


	cache_dir="./cowpoke-return-cache"
	mkdir -p $cache_dir

	scp "$BUILDD_USER$BUILDD_HOST:$RESULT_DIR/${PACKAGE}_$CHANGES" $cache_dir

	for f in $(cd $cache_dir && dcmd ${PACKAGE}_$CHANGES); do
	    RESULTS="$RESULTS $RESULT_DIR/$f"
	done

	rm -f $cache_dir/${PACKAGE}_$CHANGES
	rmdir $cache_dir


	if ! rsync -vP "$BUILDD_USER$BUILDD_HOST:$RESULTS" "$RETURN_DIR" ;
	then
	    scp "$BUILDD_USER$BUILDD_HOST:$RESULTS" "$RETURN_DIR"
	fi

      done
    done
fi

rm -f "$REMOTE_SCRIPT"

# vi:sts=4:sw=4:noet:foldmethod=marker
