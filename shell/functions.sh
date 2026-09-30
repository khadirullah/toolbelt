# shellcheck shell=bash
# toolbelt shell functions: mkcd and up. They change the folder of the shell
# you type in, which a script in its own process cannot do, so they are
# functions. shell/init.sh loads this file when the "functions" setting is on.
# Works in bash and zsh.

# Make a folder, with its parents, and move into it.
mkcd() {
    case ${1:-} in
        -h|--help)
            cat <<'EOF'
usage: mkcd [--] folder

Make a folder with its parents, and move into it.

Examples:
  mkcd ~/lab/kind/manifests
  mkcd -- -odd-name

Exit: 0 ok, 1 cannot make or enter it, 2 bad usage. See man mkcd.
EOF
            return 0 ;;
        --) shift ;;
        -?*)
            printf 'mkcd: unknown option %s\n' "$1" >&2
            printf "Try 'mkcd --help' for the options.\n" >&2
            return 2 ;;
    esac
    if [ $# -ne 1 ] || [ -z "$1" ]; then
        printf 'mkcd: give one folder name\n' >&2
        printf "Try 'mkcd --help' for the options.\n" >&2
        return 2
    fi
    local _mkcd_dir=$1
    # A relative name gets ./ in front, so cd never follows CDPATH somewhere else.
    case $_mkcd_dir in
        /*|./*|../*|.|..) ;;
        *) _mkcd_dir=./$_mkcd_dir ;;
    esac
    if [ -e "$_mkcd_dir" ] && [ ! -d "$_mkcd_dir" ]; then
        printf 'mkcd: %s exists and is not a folder\n' "$1" >&2
        return 1
    fi
    command mkdir -p -- "$_mkcd_dir" || { printf 'mkcd: cannot make %s\n' "$1" >&2; return 1; }
    builtin cd -- "$_mkcd_dir" || { printf 'mkcd: cannot enter %s\n' "$1" >&2; return 1; }
}

# Go up a number of folders, or to the nearest parent with a name.
up() {
    local _up_dir _up_n _up_i
    case ${1:-} in
        -h|--help)
            cat <<'EOF'
usage: up [n | name]

Go up n folders, or to the nearest parent with a name.

Examples:
  up
  up 3
  up lab

Exit: 0 ok, 1 no such parent, 2 bad usage. See man up.
EOF
            return 0 ;;
        --) shift ;;
        -?*)
            printf 'up: unknown option %s\n' "$1" >&2
            printf "Try 'up --help' for the options.\n" >&2
            return 2 ;;
    esac
    if [ $# -gt 1 ]; then
        printf 'up: give one number or one folder name\n' >&2
        printf "Try 'up --help' for the options.\n" >&2
        return 2
    fi
    _up_dir=$PWD
    case ${1:-1} in
        *[!0-9]*)
            # A name: walk up until a folder has it.
            while [ "$_up_dir" != / ] && [ -n "$_up_dir" ]; do
                _up_dir=${_up_dir%/*}
                [ -z "$_up_dir" ] && _up_dir=/
                if [ "${_up_dir##*/}" = "$1" ]; then
                    builtin cd -- "$_up_dir" || return 1
                    return 0
                fi
            done
            printf 'up: no parent folder named %s\n' "$1" >&2
            return 1 ;;
        *)
            # Leading zeros off, so 08 is not read as a bad octal number, and
            # anything past 4096 levels is the root anyway.
            _up_n=${1:-1}
            while [ "${#_up_n}" -gt 1 ] && [ "${_up_n#0}" != "$_up_n" ]; do _up_n=${_up_n#0}; done
            [ "${#_up_n}" -gt 4 ] && _up_n=4096
            if [ "$_up_n" -lt 1 ]; then
                printf 'up: give a number of 1 or more\n' >&2
                return 2
            fi
            _up_i=0
            while [ "$_up_i" -lt "$_up_n" ] && [ "$_up_dir" != / ]; do
                _up_dir=${_up_dir%/*}
                [ -z "$_up_dir" ] && _up_dir=/
                _up_i=$(( _up_i + 1 ))
            done
            builtin cd -- "$_up_dir" || return 1 ;;
    esac
}
