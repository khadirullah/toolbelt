# shellcheck shell=bash
# Bash completion for every toolbelt command. The installer links each command
# name to this file, so bash-completion loads it on first Tab.
# Options come from each command's own --help, so they never go stale.

_toolbelt_complete() {
    local cur=${COMP_WORDS[COMP_CWORD]} cmd=${COMP_WORDS[0]##*/} opts
    if [[ $cmd == toolbelt ]] && (( COMP_CWORD == 1 )); then
        mapfile -t COMPREPLY < <(compgen -W "help doctor setup shell update version uninstall new" -- "$cur")
        return
    fi
    if [[ $cmd == toolbelt && ${COMP_WORDS[1]} == help ]] && (( COMP_CWORD == 2 )); then
        mapfile -t COMPREPLY < <(compgen -W "$(_toolbelt_names) archives files system network everyday kubernetes devops shell" -- "$cur")
        return
    fi
    if [[ $cmd == toolbelt && ${COMP_WORDS[1]} == shell ]]; then
        if (( COMP_CWORD == 2 )); then
            mapfile -t COMPREPLY < <(compgen -W "enable disable" -- "$cur")
        else
            mapfile -t COMPREPLY < <(compgen -W "functions history safe" -- "$cur")
        fi
        return
    fi
    if [[ $cur == -* ]]; then
        # Option lines in help start with two spaces and a dash.
        opts=$("$cmd" --help 2>/dev/null | grep -E '^  +-' | sed -E 's/  .*//; s/^ +//' |
            grep -oE -- '--?[A-Za-z0-9][A-Za-z0-9-]*' | sort -u)
        mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
        return
    fi
    # Anything else completes as a file name, through -o default.
    COMPREPLY=()
}

_toolbelt_names() {
    local lib
    lib=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/commands
    awk '!/^#/ && NF { for (i = 2; i <= NF; i++) print $i }' "$lib" 2>/dev/null
}

complete -o default -o bashdefault -F _toolbelt_complete $(_toolbelt_names | grep -v -e '^mkcd$' -e '^up$')
complete -o dirnames mkcd up 2>/dev/null
