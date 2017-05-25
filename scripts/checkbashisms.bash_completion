# /usr/share/bash-completion/completions/checkbashisms
# Bash command completion for ‘checkbashisms(1)’.
# Documentation: ‘bash(1)’, section “Programmable Completion”.

# Copyright © 2015, Nicholas Bamber <nicholas@periapt.co.uk>

_checkbashisms()
{
    local cur prev words cword special
    _init_completion || return

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $( compgen -W '--newline --posix --force --extra' -- "$cur" ) )
    else
        COMPREPLY=( $( compgen -o filenames -f -- "$cur" ) )
    fi

    return 0
} &&
complete -F _checkbashisms checkbashisms


# Local variables:
# coding: utf-8
# mode: shell-script
# indent-tabs-mode: nil
# End:
# vim: fileencoding=utf-8 filetype=sh expandtab shiftwidth=4 :
