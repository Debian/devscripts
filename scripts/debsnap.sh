#!/bin/bash

# Copyright © 2009, David Paleino <d.paleino@gmail.com>,
#                   Ron <ron@debian.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Thanks to Ron Lee and Patrick Schoenfeld for helping during
# the development process! :)

#set -x
set -e

##
# Rationale for variables naming:
# DEBSNAP_FOO : means it directly comes from the config file, which can be edited by the user
# foo         : means we assigned it, also combining data coming from the user
##

OPTS=$(getopt -ao d:fvh --long destdir:,force,verbose,version,help -n $0 -- "$@")
if [ $? -ne 0 ]; then
	echo "Terminating." >&2
	exit 1
fi
eval set -- "$OPTS"

PROGNAME="$(basename $0)"

version() {
	echo \
"This is $PROGNAME, from the Debian devscripts package, version ###VERSION###
This code is copyright 2009 by David Paleino <d.paleino@gmail.com> and
Ron <ron@debian.org> -- all rights reserved.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of the GNU
General Public License v3 or, at your option, any later version."
	exit 0
}

usage() {
	cat 1>&2 <<EOF
$PROGNAME [options] <package name> [package version]

  Automatically downloads packages from snapshot.debian.net

  The following options are supported:
  -h, --help                          Shows this help message
  --version                           Shows information about version
  -v, --verbose                       Be verbose
  -d <destination directory>,
  --destdir <destination directory>   Directory for retrieved packages
                                      Default is ./source-<package name>
  -f, --force                         Force overwriting an existing
                                      destdir

EOF
	exit 0
}

debug() {
	if [ "$DEBSNAP_VERBOSE" = "yes" ]; then
		echo "$@"
	fi
}

start_download() {
	quiet="$1"
	destdir="$2"
	package="$3"
	version="$4"
	directory="$5"
	suffix="$6"

	dsc="$DEBSNAP_BASE_URL/$directory/${package}_$version.dsc"
	diff="$DEBSNAP_BASE_URL/$directory/${package}_$version.diff.gz"
	orig="$DEBSNAP_BASE_URL/$directory/${package}_$upversion.$suffix"

	printf "Downloading %s... " $version
	[ -n "$quiet" ] || echo

	# I don't really like dget's output with missing files :)
#	( cd sources / ; \
#	dget -d --quiet $base_url/$directory/${package}_$version.dsc )

	# the "continue" annidated here mean "go to the next stanza of Sources.gz"
	if ! wget $quiet -P "$destdir" -nH -nc "$dsc"; then
		echo "missing .dsc."
		debug "Url: $dsc"
		return 1
	else
		if ! wget $quiet -P "$destdir" -nH -nc "$orig"; then
			echo "missing .$suffix."
			debug "Url: $orig"
			return 1
		else
			if [ "$suffix" = "orig.tar.gz" ]; then
				if ! wget $quiet -P "$destdir" -nH -nc "$diff"; then
					echo "missing .diff.gz."
					debug "Url: $diff"
					return 1
				else
					echo "done."
				fi
			else
				echo "done."
			fi
		fi
	fi
}

# these are our defaults
DEFAULT_DEBSNAP_VERBOSE=no
DEFAULT_DEBSNAP_DESTDIR=
DEFAULT_DEBSNAP_BASE_URL=http://snapshot.debian.net/archive
DEFAULT_DEBSNAP_CLEAN_REGEX="s@\([^/]*\)/[^/]*/\(.*\)@\1/\2@"
DEFAULT_DEBSNAP_SOURCES_GZ_PATH=source/Sources.gz
VARS="DEBSNAP_VERBOSE DEBSNAP_DESTDIR DEBSNAP_BASE_URL DEBSNAP_CLEAN_REGEX DEBSNAP_SOURCES_GZ_PATH"

# read configuration from devscripts
eval $(
	set +e
	for var in $VARS; do
		eval "$var=\$DEFAULT_$var"
	done
	[ -r "/etc/devscripts.conf" ] && . /etc/devscripts.conf
	[ -r "~/.devscripts" ] && . ~/.devscripts
	set | egrep "^(DEBSNAP|DEVSCRIPTS)_"
)

# sanitize variables
case "$DEBSNAP_VERBOSE" in
	yes|no) ;;
	*) DEBSNAP_VERBOSE=no ;;
esac

while true; do
	case "$1" in
		-v|--verbose)
			DEBSNAP_VERBOSE=yes
			shift
			;;
		-d|--destdir)
			DEBSNAP_DESTDIR="$2"
			shift 2
			;;
		-f|--force)
			force_overwrite=yes
			shift
			;;
		--version)
			version
			shift
			;;
		-h|--help)
			usage
			shift
			;;
		--)
			shift
			break
			;;
		*)
			echo "Internal error in option parsing." >&2
			;;
	esac
done

package="$1"
_version="${2//*:/}"    # remove the Epoch

if [ -z "$package" ]; then
	usage
fi

if [ "$DEBSNAP_VERBOSE" = "yes" ]; then
	echo "Using these values:"
	for var in $VARS; do
		eval "echo $var=\$$var"
	done
	echo "Requested package: $package"
	if [ -z "$_version" ]; then
		echo "Requested version: all"
	else
		echo "Requested version: $_version"
	fi
else
	quiet="--quiet"
fi

source_pkg=$(apt-cache showsrc $package | grep -m1 ^Package | cut -f2 -d\ )
cache_dir=$(apt-cache showsrc $package | grep -m1 ^Directory | cut -f2 -d\ )

# make it pool/f/foo from pool/<section>/f/foo
clean_dir=$(echo "$cache_dir" | sed -e "$DEBSNAP_CLEAN_REGEX")

[ -n "$DEBSNAP_DESTDIR" ] || DEBSNAP_DESTDIR="source-$source_pkg"
if [ "$DEBSNAP_DESTDIR" != "." ]; then
	if [ -d "$DEBSNAP_DESTDIR" ]; then
		if [ -z "$force_overwrite" ]; then
			echo "Destination dir $DEBSNAP_DESTDIR already exists."
			echo "Please (re)move it first, or use --force to overwrite."
			exit 1
		fi
		echo "Removing exiting destination dir $DEBSNAP_DESTDIR as requested."
		rm -rf "$DEBSNAP_DESTDIR"
	fi
	mkdir -p "$DEBSNAP_DESTDIR"
fi


# download the Sources.gz
tmpdir=$(mktemp -d /tmp/$PROGNAME.XXXX)
trap "rm -rf \"$tmpdir\"; exit 1" 0 SIGHUP SIGINT SIGTERM
sources_url="$DEBSNAP_BASE_URL/$clean_dir/$DEBSNAP_SOURCES_GZ_PATH"
sources_path="$tmpdir/Sources.gz"

echo -n "Downloading Sources.gz... "
[ -n "$quiet" ] || echo

if ! wget $quiet "$sources_url" -O "$sources_path"; then
	echo "failed."
	debug "Url: $sources_url"
	exit 1
else
	echo "done."
fi

while read field value
do
	case $field in
		Package:)
			if [ "$value" != "$source_pkg" ]; then
				echo "Source package names not matching! Exiting."
				exit 1
			fi
			have_package=yes
			;;
		Version:)
			if [ -n "$version" ]; then
				echo "Version already set. Exiting."
				exit 1
			else
				# remove the Epoch
				version=${value//*:/}
				# remove everything after a -
				upversion=${version%-*}
				if [ "$upversion" = "$version" ]; then
					# this is a native package, so the original tarball has 
					# just "tar.gz" as suffix.
					suffix="tar.gz"
				else
					# this is not a native package, use "orig.tar.gz"
					suffix="orig.tar.gz"
				fi
			fi
			;;
		Directory:)
			if [ -n "$directory" ]; then
				echo "Directory already set. Exiting."
				exit 1
			else
				directory=$value
			fi
			;;
		"")
			# the blank line always comes last (unless it comes first)
			# bail out with errors if directory and version are not set,
			# (but only if we have seen a Package line already).
			if [ -z "$have_package" ]; then
				echo "No Package name before empty Sources.gz line. Skipping stanza."
			elif [ -z "$version" ] || [ -z "$directory" ]; then
				echo "Couldn't parse version/directory. Skipping stanza."
				debug "Version: $version"
				debug "Directory: $directory"
#				exit 1
			else
				# if the user requested a specific version,
				# skip the download step until we find it,
				# then break from the loop and let the outer
				# call deal with this case for us.
				if [ -z "$_version" ]; then
					if ! start_download "$quiet" "$DEBSNAP_DESTDIR" \
					                    "$package" "$version"      \
					                    "$directory" "$suffix"; then
						# Keep trying if some files were missing,
						# but report that to the caller at exit.
						missing_package=yes
					fi
				elif [ "$_version" = "$version" ]; then
					break
				fi
			fi
			have_package=
			version=
			directory=
			;;
	esac
done < <(zcat "$sources_path")

# We need this if there isn't an empty line following the last (or only) stanza
# and we also perform the download here if just a single version was requested.
if [ -n "$version" ] && [ -n "$directory" ]; then
	if ! start_download "$quiet" "$DEBSNAP_DESTDIR" "$package" \
	                    "$version" "$directory" "$suffix"; then
		missing_package=yes
	fi
fi

# Disable the trap on exit so we can take back control of the exit code
trap - 0
rm -rf "$tmpdir"

[ -z "$missing_package" ] || exit 2
