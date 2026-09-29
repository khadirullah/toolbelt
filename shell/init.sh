# toolbelt shell settings. Your ~/.bashrc or ~/.zshrc loads this file with one
# line, added by `toolbelt shell enable`. It turns on the settings listed in
# ~/.config/toolbelt/shell. Works in bash and zsh.

_tb_root=$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." 2>/dev/null && pwd)
_tb_conf=${XDG_CONFIG_HOME:-$HOME/.config}/toolbelt/shell

_tb_on() { [ -r "$_tb_conf" ] && grep -qx "$1" "$_tb_conf"; }

# mkcd and up
if _tb_on functions && [ -r "$_tb_root/shell/functions.sh" ]; then
    . "$_tb_root/shell/functions.sh"
fi

# 50000 lines with timestamps, written at once and shared between terminals
if _tb_on history; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        HISTSIZE=50000
        SAVEHIST=50000
        HISTFILE=${HISTFILE:-$HOME/.zsh_history}
        setopt EXTENDED_HISTORY SHARE_HISTORY HIST_IGNORE_SPACE HIST_IGNORE_DUPS
    elif [ -n "${BASH_VERSION:-}" ]; then
        HISTSIZE=50000
        HISTFILESIZE=50000
        HISTTIMEFORMAT='%F %T  '
        HISTCONTROL=ignoreboth
        shopt -s histappend
        case ${PROMPT_COMMAND:-} in
            *"history -a"*) ;;
            *) PROMPT_COMMAND="history -a; history -n${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
        esac
    fi
fi

# cp and mv ask before they overwrite
if _tb_on safe; then
    alias cp='cp -i'
    alias mv='mv -i'
fi

# zsh completion for every toolbelt command
if [ -n "${ZSH_VERSION:-}" ] && [ -d "$_tb_root/completions" ]; then
    fpath=("$_tb_root/completions" $fpath)
fi

unset -f _tb_on
unset _tb_root _tb_conf
