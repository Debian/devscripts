#!/bin/sh

# debrepro: a reproducibility tester for Debian packages
#
# © 2016 Antonio Terceiro <terceiro@debian.org>
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

set -eu

check_dependencies() {
    for optional in disorderfs diffoscope; do
        if ! command -v "$optional" > /dev/null; then
            echo "W: $optional not installed, there will be missing functionality" >&2
        fi
    done

    local failed=''
    for mandatory in faketime; do
        if ! command -v "$mandatory" > /dev/null; then
            echo "E: $mandatory not installed, cannot proceed." >&2
            failed=yes
        fi
    done
    if [ -n "$failed" ]; then
        exit 3
    fi
}

usage() {
    echo "usage: $0 [OPTIONS] [SOURCEDIR]"
    echo ""
    echo "Options:"
    echo ""
    echo " -b,--before-second-build COMMAND  Run COMMAND before second build"
    echo "                                   (e.g. apply a patch)"
    echo " -s,--skip VARIATION               Don't perform the named variation"
    echo " -h,--help                         Display this help message and exit"
}

first_banner=y
banner() {
    if [ "$first_banner" = n ]; then
        echo
    fi
    echo "$@" | sed -e 's/./=/g'
    echo "$@"
    echo "$@" | sed -e 's/./=/g'
    echo
    first_banner=n
}

variation() {
    echo
    echo "# Variation:" "$@"
}

vary() {
    local var="$1"

    for skipped in $skip_variations; do
        if [ "$skipped" = "$var" ]; then
            return
        fi
    done

    variation "$var"
    local first="$2"
    local second="$3"
    if [ "$which_build" = 'first' ]; then
        if [ -n "$first" ]; then
            echo "$first"
        fi
    else
        echo "$second"
    fi
}

create_build_script() {
    echo 'set -eu'

    echo
    echo "# this script must be run from inside an unpacked Debian source"
    echo "# package"
    echo

    vary path \
        '' \
        'export PATH="$PATH":/i/capture/the/path'

    vary user \
        'export USER=user1' \
        'export USER=user2'

    vary umask \
        'umask 0022' \
        'umask 0002'

    vary locale \
        'export LC_ALL=C.UTF-8 LANG=C.UTF-8' \
        'export LC_ALL=pt_BR.UTF-8 LANG=pt_BR.UTF-8'

    vary timezone \
        'export TZ=GMT+12' \
        'export TZ=GMT-14'

    if command -v disorderfs >/dev/null; then
        disorderfs_commands='cd .. &&
mv source orig &&
mkdir source &&
disorderfs --shuffle-dirents=yes orig source &&
trap "cd .. && fusermount -u source && rmdir source && mv orig source" INT TERM EXIT &&
cd source'
        vary filesystem-ordering \
            '' \
            "$disorderfs_commands"
    fi

    echo 'build_prefix=""'

    vary time \
        '' \
        'build_prefix="faketime +213days+7hours+13minutes"; export NO_FAKE_STAT=1'

    if [ -n "$timeout" ]; then
        echo "build_prefix=\"timeout $timeout \$build_prefix\""
    fi

    echo '${build_prefix:-} dpkg-buildpackage -b -us -uc'
}


build() {
    export which_build="$1"
    mkdir "$tmpdir/build"

    cp -r "$SOURCE" "$tmpdir/build/source"
    cd "$tmpdir/build/source"

    if [ "$which_build" = second ] && [ -n "$before_second_build_command" ]; then
        banner "I: running before second build: $before_second_build_command"
        sh -c "$before_second_build_command"
    fi

    create_build_script > ../build.sh
    sh ../build.sh
    cd -

    mv "$tmpdir/build" "$tmpdir/$which_build"
}

binmatch() {
    cmp --silent "$1" "$2"
}

compare() {
    rc=0
    for first_deb in "$tmpdir"/first/*.deb; do
        deb="$(basename "$first_deb")"
        second_deb="$tmpdir"/second/"$deb"
        if binmatch "$first_deb" "$second_deb"; then
            echo "✓ $deb: binaries match"
        else
            echo "✗ $deb: binaries don't match"
            rc=1
        fi
    done
    if [ "$rc" -ne 0 ]; then
        if command -v diffoscope >/dev/null; then
            diffoscope "$tmpdir"/first/*.changes "$tmpdir"/second/*.changes || true
        else
            echo "I: install diffoscope for a deep comparison between artifacts"
        fi
        echo "E: package is not reproducible."
    fi
    return "$rc"
}

TEMP=$(getopt -n "debrepro" -o 'hs:b:t:' \
    -l 'help,skip:,before-second-build:,timeout:' \
    -- "$@") || (rc=$?; usage >&2; exit $rc)
eval set -- "$TEMP"

skip_variations=""
before_second_build_command=''
timeout=''
while true; do
    case "$1" in
        -s|--skip)
            case "$2" in
                user|path|umask|locale|timezone|filesystem-ordering|time)
                    skip_variations="$skip_variations $2"
                    ;;
                *)
                    echo "E: invalid variation name $2"
                    exit 1
                    ;;
            esac
            shift
            ;;
        -b|--before-second-build)
            before_second_build_command="$2"
            shift
            ;;
        -t|--timeout)
            timeout="$2"
            shift
            ;;
        -h|--help)
            usage
            exit
            ;;
        --)
            shift
            break
            ;;
    esac
    shift
done

SOURCE="${1:-}"
if [ -z "$SOURCE" ]; then
    SOURCE="$(pwd)"
fi
if [ ! -f "$SOURCE/debian/changelog" ]; then
    echo "E: $SOURCE does not look like a Debian source package"
    exit 2
fi

tmpdir=$(mktemp --directory --tmpdir debrepro.XXXXXXXXXX)
trap "if [ \$? -eq 0 ]; then rm -rf $tmpdir; else echo; echo 'I: artifacts left in $tmpdir'; fi" INT TERM EXIT

check_dependencies

banner "First build"
build first

banner "Second build"
build second

banner "Comparing binaries"
compare first second

# vim:ts=4 sw=4 et
