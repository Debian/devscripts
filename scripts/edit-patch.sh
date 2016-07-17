#!/bin/sh
#
# Copyright (C) 2009 Canonical
#
# Authors:
#  Michael Vogt
#  Daniel Holbach
#  David Futcher
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

set -e


PATCHSYSTEM="unknown"
PATCHNAME="no-patch-name"
PREFIX="debian/patches"

PATCH_DESC=$(cat<<EOF
## Description: add some description\
\n## Origin/Author: add some origin or author\
\n## Bug: bug URL
EOF
)

fatal_error() {
    echo "$@" >&2
    exit 1
}

# check if the given binary is installed and give an error if not
# arg1: binary
# arg2: error message
require_installed() {
    if ! which "$1" >/dev/null; then
        fatal_error "$2"
    fi
}

ensure_debian_dir() {
    if [ ! -e debian/control ] || [ ! -e debian/rules ]; then
        fatal_error "Can not find debian/rules or debian/control. Not in a debian dir?"
    fi

}

detect_patchsystem() {
    CDBS_PATCHSYS="^[^#]*simple-patchsys.mk"

    if grep -q "$CDBS_PATCHSYS" debian/rules; then
        PATCHSYSTEM="cdbs"
        require_installed cdbs-edit-patch "no cdbs-edit-patch found, is 'cdbs' installed?"
    elif [ -e debian/patches/00list ]; then
        PATCHSYSTEM="dpatch"
        require_installed dpatch-edit-patch "no dpatch-edit-patch found, is 'dpatch' installed?"
    elif [ -e debian/patches/series -o \
           "$(cat debian/source/format 2> /dev/null)" = "3.0 (quilt)" ]; then
        PATCHSYSTEM="quilt"
        require_installed quilt "no quilt found, is 'quilt' installed?"
    else
        PATCHSYSTEM="none"
        PREFIX="debian/applied-patches"
    fi
}

# remove full path if given
normalize_patch_path() {
    PATCHNAME=${PATCHNAME##*/}
    echo "Normalizing patch path to $PATCHNAME"
}

# ensure (for new patches) that:
# - dpatch ends with .dpatch
# - cdbs/quilt with .patch
normalize_patch_extension() {
    # check if we have a patch already
    if [ -e $PREFIX/$PATCHNAME ]; then
        echo "Patch $PATCHNAME exists, not normalizing"
        return
    fi

    # normalize name for new patches
    PATCHNAME=${PATCHNAME%.*}
    if [ "$PATCHSYSTEM" = "quilt" ]; then
        PATCHNAME="${PATCHNAME}.patch"
    elif [ "$PATCHSYSTEM" = "cdbs" ]; then
        PATCHNAME="${PATCHNAME}.patch"
    elif [ "$PATCHSYSTEM" = "dpatch" ]; then
        PATCHNAME="${PATCHNAME}.dpatch"
    elif [ "$PATCHSYSTEM" = "none" ]; then
        PATCHNAME="${PATCHNAME}.patch"
    fi

    echo "Normalizing patch name to $PATCHNAME"
}

edit_patch_cdbs() {
    cdbs-edit-patch $PATCHNAME
    vcs_add debian/patches/$1
}

edit_patch_dpatch() {
    dpatch-edit-patch $PATCHNAME
    # add if needed
    if ! grep -q $1 $PREFIX/00list; then
        echo "$1" >> $PREFIX/00list
    fi
    vcs_add $PREFIX/00list $PREFIX/$1
}

edit_patch_quilt() {
    export QUILT_PATCHES=debian/patches
    top_patch=$(quilt top)
    echo "Top patch: $top_patch"
    if [ -e $PREFIX/$1 ]; then
        # if it's an existing patch and we are at the end of the stack,
        # go back at the beginning
        if ! quilt unapplied; then
            quilt pop -a
        fi
        quilt push $1
    else
        # if it's a new patch, make sure we are at the end of the stack
        if quilt unapplied >/dev/null; then
            quilt push -a
        fi
        quilt new $1
    fi
    # use a sub-shell
    quilt shell
    quilt refresh
    echo "Reverting quilt back to $top_patch"
    quilt pop $top_patch
    vcs_add $PREFIX/$1 $PREFIX/series
}

edit_patch_none() {
    # Dummy edit-patch function, just display a warning message
    echo "No patchsystem could be found so the patch was applied inline and a copy \
stored in debian/patches-applied. Please remember to mention this in your changelog."
}

add_patch_quilt() {
    # $1 is the original patchfile, $2 the normalized name
    # FIXME: use quilt import instead?
    cp $1 $PREFIX/$2
    if ! grep -q $2 $PREFIX/series; then
        echo "$2" >> $PREFIX/series
    fi
    vcs_add $PREFIX/$2 $PREFIX/series
}

add_patch_cdbs() {
    # $1 is the original patchfile, $2 the normalized name
    cp $1 $PREFIX/$2
    vcs_add $PREFIX/$2
}

add_patch_dpatch() {
    # $1 is the original patchfile, $2 the normalized name
    cp $1 $PREFIX
    if ! grep -q $2 $PREFIX/00list; then
        echo "$2" >> $PREFIX/00list
    fi
    vcs_add $PREFIX/$2 $PREFIX/00list
}

add_patch_none() {
    # $1 is the original patchfile, $2 the normalized name
    cp $1 $PREFIX/$2
    vcs_add $PREFIX/$2
}

vcs_add() {
    if [ -d .bzr ]; then
        bzr add $@
    elif [ -d .git ];then
        git add $@
    else
        echo "Remember to add $@ to a VCS if you use one"
    fi
}

vcs_commit() {
    # check if debcommit is happy
    if ! debcommit --noact 2>/dev/null; then
        return
    fi
    # commit (if the user confirms)
    debcommit --confirm
}

add_changelog() {
    S="$PREFIX/$1: [DESCRIBE CHANGES HERE]"
    if head -n1 debian/changelog|grep UNRELEASED; then
        dch --append "$S"
    else
        dch --increment "$S"
    fi
    # let the user edit it
    dch --edit
}

add_patch_tagging() {
    # check if we have a description already
    if grep "## Description:" $PREFIX/$1; then
        return
    fi
    # if not, add one
    RANGE=1,1
    # make sure we keep the first line (for dpatch)
    if head -n1 $PREFIX/$1|grep -q '^#'; then
        RANGE=2,2
    fi
    sed -i ${RANGE}i"$PATCH_DESC" $PREFIX/$1
}

detect_patch_location() {
    # Checks whether the specified patch exists in debian/patches or on the filesystem
    FILENAME=${PATCHNAME##*/}

    if [ -f "$PREFIX/$FILENAME" ]; then
        PATCHTYPE="debian"
    elif [ -f "$PATCHNAME" ]; then
        PATCHTYPE="file"
        PATCHORIG="$PATCHNAME"
    else
        if [ "$PATCHSYSTEM" = "none" ]; then
            fatal_error "No patchsystem detected, cannot create new patch (no dpatch/quilt/cdbs?)"
        else
            PATCHTYPE="new"
        fi
    fi
}

handle_file_patch() {
    if [ "$PATCHTYPE" = "file" ]; then
        [ -f "$PATCHORIG" ] || fatal_error "No patch detected"

        if [ "$PATCHSYSTEM" = "none" ]; then
            # If we're supplied a file and there is no patchsys we apply it directly
            # and store it in debian/applied patches
            [ -d $PREFIX ] || mkdir $PREFIX

            patch -p0 < "$PATCHORIG"
            cp "$PATCHORIG" "$PREFIX/$PATCHNAME"
        else
            # Patch type is file but there is a patchsys present, so we add it
            # correctly
            cp "$PATCHORIG" "$PREFIX/$PATCHNAME"

            if [ "$PATCHSYSTEM" = "quilt" ]; then
                echo "$PATCHNAME" >> $PREFIX/series
            elif [ "$PATCHSYSTEM" = "dpatch" ]; then
                echo "$PATCHNAME" >> $PREFIX/00list

                # Add the dpatch header to files that don't already have it
                if ! grep -q "@DPATCH@" "$PREFIX/$PATCHNAME"; then
                    sed -i '1i#! /bin/sh /usr/share/dpatch/dpatch-run\n@DPATCH@' $PREFIX/$PATCHNAME
                fi
            fi

            echo "Copying and applying new patch. You can now edit the patch or exit the subshell to save."
        fi
    fi
}

# TODO:
# - edit-patch --remove implementieren
# - dbs patch system

main() {
    # parse args
    if [ $# -ne 1 ]; then
        fatal_error "Need exactly one patch name"
    fi
    PATCHNAME="$1"
    # do the work
    ensure_debian_dir
    detect_patchsystem
    detect_patch_location
    normalize_patch_path
    normalize_patch_extension
    handle_file_patch
    if [ "$(basename $0 .sh)" = "edit-patch" ]; then
        edit_patch_$PATCHSYSTEM $PATCHNAME
    elif [ "$(basename $0 .sh)" = "add-patch" ]; then
        add_patch_$PATCHSYSTEM $1 $PATCHNAME
    else
        fatal_error "Unknown script name: $0"
    fi
    add_patch_tagging $PATCHNAME
    add_changelog $PATCHNAME
    vcs_commit
}

main $@
