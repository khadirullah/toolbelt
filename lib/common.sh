# shellcheck shell=bash
# Shared helpers for every toolbelt command.
#
# A command sources this file, defines usage(), and parses its options with
# tb_expand and tb_common_opt. See CONTRIBUTING.md for the full contract.

[[ -n ${TB_COMMON_LOADED:-} ]] && return 0
TB_COMMON_LOADED=1

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    echo "toolbelt needs bash 4.4 or newer, this is $BASH_VERSION" >&2
    exit 1
fi

TB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TB_VERSION=$(cat "$TB_ROOT/VERSION" 2>/dev/null || echo unknown)
TB_CMD=${TB_CMD:-$(basename "$0")}
TB_URL=https://github.com/khadirullah/toolbelt

# Exit codes, the same in every command.
readonly E_OK=0 E_FAIL=1 E_USAGE=2 E_TOOL=3 E_SAFE=4 E_NO=5

# Set by the common options.
TB_QUIET=0
TB_VERBOSE=0
TB_YES=0
TB_PASS=()      # everything after --
TB_EXPANDED=()  # the argument list after tb_expand

# ---------------------------------------------------------------- colour

TB_COLOR=0
if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
    TB_COLOR=1
fi
if (( TB_COLOR )); then
    C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YEL=$'\e[33m' C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_OFF=$'\e[0m'
else
    C_RED="" C_GRN="" C_YEL="" C_DIM="" C_BOLD="" C_OFF=""
fi

# Colour for text going to stdout, which may be a pipe when stderr is not.
tb_color_stdout() {
    if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YEL=$'\e[33m' C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_OFF=$'\e[0m'
    else
        C_RED="" C_GRN="" C_YEL="" C_DIM="" C_BOLD="" C_OFF=""
    fi
}

# ---------------------------------------------------------------- output

# An error line: "unpack: message".
tb_err() { printf '%s: %s\n' "$TB_CMD" "$*" >&2; }

# An error line, then exit with the code given first.
tb_die() {
    local code=$1
    shift
    tb_err "$@"
    exit "$code"
}

# A warning, shown even in quiet mode.
tb_warn() { printf '%s%s: %s%s\n' "$C_YEL" "$TB_CMD" "$*" "$C_OFF" >&2; }

# Progress and notes for a person. Hidden by -q.
tb_info() { (( TB_QUIET )) || printf '%s\n' "$*" >&2; }

# A step, shown only with -v.
tb_say() { (( TB_VERBOSE )) && printf '%s: %s\n' "$TB_CMD" "$*" >&2; return 0; }

# Print a command the way -v shows it: "+ tar -xf - -C out".
tb_show() {
    (( TB_VERBOSE )) || return 0
    local out="+" a
    for a in "$@"; do
        if [[ $a =~ ^[][A-Za-z0-9_./:=,@%+^-]+$ ]]; then
            out+=" $a"
        else
            out+=" '${a//\'/\'\\\'\'}'"
        fi
    done
    printf '%s%s%s\n' "$C_DIM" "$out" "$C_OFF" >&2
}

# Show a command with -v, then run it.
tb_run() {
    tb_show "$@"
    "$@"
}

# Show a pipeline or other shell text with -v. The caller runs it.
tb_show_text() { (( TB_VERBOSE )) && printf '%s+ %s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; return 0; }

# ---------------------------------------------------------------- options

# Rewrite the argument list into TB_EXPANDED so a plain case loop can read it.
#   -qv        becomes  -q -v
#   -l9        becomes  -l 9   when l is in the list of letters that take a value
#   --out=dir  becomes  --out dir
# Everything from -- on is copied as it is.
# Usage: tb_expand "letters with a value" "$@"; set -- "${TB_EXPANDED[@]}"
tb_expand() {
    local valued=$1 a i c
    shift
    TB_EXPANDED=()
    while (( $# )); do
        a=$1
        shift
        if [[ $a == -- ]]; then
            TB_EXPANDED+=(-- "$@")
            return 0
        elif [[ $a =~ ^--[A-Za-z0-9][A-Za-z0-9-]*=(.*)$ ]]; then
            TB_EXPANDED+=("${a%%=*}" "${BASH_REMATCH[1]}")
        elif [[ $a =~ ^-[A-Za-z0-9]{2,} ]]; then
            for ((i = 1; i < ${#a}; i++)); do
                c=${a:i:1}
                TB_EXPANDED+=("-$c")
                if [[ $valued == *"$c"* ]]; then
                    (( i + 1 < ${#a} )) && TB_EXPANDED+=("${a:i+1}")
                    break
                fi
            done
        else
            TB_EXPANDED+=("$a")
        fi
    done
}

# Handle an option every command shares. Returns 1 when it is not one.
tb_common_opt() {
    case $1 in
        -h|--help)    usage; exit 0 ;;
        -q|--quiet)   TB_QUIET=1 ;;
        -v|--verbose) TB_VERBOSE=1 ;;
        -y|--yes)     TB_YES=1 ;;
        --version)    echo "$TB_CMD, toolbelt $TB_VERSION"; exit 0 ;;
        *) return 1 ;;
    esac
}

# Bad usage: say what is wrong, point at --help, exit 2.
tb_usage_error() {
    tb_err "$*"
    echo "Try '$TB_CMD --help' for the options." >&2
    exit "$E_USAGE"
}

# Check that an option got its value. Usage: tb_optarg "$@" inside the case.
tb_optarg() {
    [[ $# -ge 2 && -n $2 ]] || tb_usage_error "$1 needs a value"
}

# An unknown option or a normal argument. Usage in the case loop:
#   -*) tb_common_opt "$1" || tb_unknown "$1" ;;
tb_unknown() { tb_usage_error "unknown option $1"; }

# ---------------------------------------------------------------- tools

tb_has() { command -v "$1" >/dev/null 2>&1; }

# True while a pid runs. A zombie counts as gone, since in a container whose
# PID 1 never reaps, a process that ended stays a zombie for good.
tb_alive() {
    kill -0 "$1" 2>/dev/null || return 1
    ! grep -qs '^State:[[:space:]]*Z' "/proc/$1/status"
}

# The package manager of this machine: apt, dnf, pacman, zypper or apk.
tb_pm() {
    if [[ -z ${TB_PM:-} ]]; then
        local p
        for p in apt-get dnf yum pacman zypper apk; do
            if tb_has "$p"; then
                TB_PM=$p
                break
            fi
        done
        case ${TB_PM:-} in
            apt-get) TB_PM=apt ;;
            yum) TB_PM=dnf ;;
            "") TB_PM=unknown ;;
        esac
    fi
    echo "$TB_PM"
}

# The package that provides a command on this machine, from lib/pkgmap.
# Prints nothing when the map has no entry.
tb_pkg_for() {
    local cmd=$1 pm col line
    pm=$(tb_pm)
    case $pm in
        apt) col=2 ;; dnf) col=3 ;; pacman) col=4 ;; zypper) col=5 ;; apk) col=6 ;; *) return 1 ;;
    esac
    line=$(awk -v c="$cmd" '$1 == c { print; exit }' "$TB_ROOT/lib/pkgmap" 2>/dev/null)
    [[ -n $line ]] || return 1
    line=$(awk -v n="$col" '{ print $n }' <<<"$line")
    [[ -n $line && $line != - ]] || return 1
    echo "$line"
}

# The full install line for a command, such as "sudo apt install 7zip".
# Returns 1 when lib/pkgmap has no package for it on this machine.
tb_install_line() {
    local cmd=$1 pkg pm sudo="sudo " alt=""
    pm=$(tb_pm)
    (( EUID == 0 )) && sudo=""
    pkg=$(tb_pkg_for "$cmd") || return 1
    # "7zip|p7zip-full" means the first name, or the second on older releases.
    if [[ $pkg == *"|"* ]]; then
        alt=" (${pkg#*|} on older releases)"
        pkg=${pkg%%|*}
    fi
    case $pm in
        apt)    echo "${sudo}apt install $pkg$alt" ;;
        dnf)    echo "${sudo}dnf install $pkg$alt" ;;
        pacman) echo "${sudo}pacman -S $pkg$alt" ;;
        zypper) echo "${sudo}zypper install $pkg$alt" ;;
        apk)    echo "${sudo}apk add $pkg$alt" ;;
    esac
}

# The "needs x" line for a missing command.
tb_missing_msg() {
    local line
    if line=$(tb_install_line "$1"); then
        echo "needs $1. Install it with: $line"
    else
        echo "needs $1. Install the package that provides it"
    fi
}

# Exit 3 with the install line unless every command given exists.
tb_need() {
    local c
    for c in "$@"; do
        tb_has "$c" && continue
        tb_err "$(tb_missing_msg "$c")"
        exit "$E_TOOL"
    done
}

# Exit 3 unless at least one of the commands exists, and store the first
# that exists in a variable. The install line names the first command.
# Usage: tb_need_any var 7z 7zz 7za
tb_need_any() {
    local _var=$1 _c
    shift
    for _c in "$@"; do
        if tb_has "$_c"; then
            printf -v "$_var" '%s' "$_c"
            return 0
        fi
    done
    tb_err "$(tb_missing_msg "$1")"
    exit "$E_TOOL"
}

# Print a one-time hint about an optional tool. Never exits.
tb_hint() {
    local cmd=$1 why=$2
    tb_has "$cmd" && return 0
    (( TB_QUIET )) && return 0
    local line
    line=$(tb_install_line "$cmd") || line="the package that provides $cmd"
    tb_info "$TB_CMD: $why. Install it with: $line"
}

# ---------------------------------------------------------------- questions

# True when a person can answer a question. Tests set TB_TEST_TTY=1 to
# answer questions through stdin.
tb_is_tty() { [[ ${TB_TEST_TTY:-} == 1 ]] || [[ -t 0 && -t 2 ]]; }

# Ask a yes or no question. The answer defaults to no.
# Returns 0 for yes, 1 for no, 2 when there is no terminal to ask in.
# With -y it returns 0 without asking.
tb_ask() {
    local reply
    (( TB_YES )) && return 0
    tb_is_tty || return 2
    printf '%s [y/N] ' "$*" >&2
    IFS= read -r reply || reply=""
    [[ ${reply,,} == y || ${reply,,} == yes ]]
}

# Ask before a change the user asked for. A no exits 5 and a missing
# terminal exits 4, so nothing changes without a clear yes or --yes.
tb_confirm() {
    tb_ask "$@"
    case $? in
        0) return 0 ;;
        1) tb_info "Nothing changed."; exit "$E_NO" ;;
        *) tb_die "$E_SAFE" "not asking without a terminal, pass --yes to go ahead" ;;
    esac
}

# ---------------------------------------------------------------- trash

# Move files to the trash in ~/.local/share/Trash, following the
# freedesktop.org spec, so a file manager can restore them.
# Sets TB_TRASHED to the names used inside Trash/files.
tb_trash() {
    local trash=${XDG_DATA_HOME:-$HOME/.local/share}/Trash p abs base name n info
    TB_TRASHED=()
    mkdir -p "$trash/files" "$trash/info" || return 1
    for p in "$@"; do
        [[ -e $p || -L $p ]] || { tb_err "$p: no such file"; return 1; }
        abs=$(cd "$(dirname "$p")" && pwd)/$(basename "$p")
        base=$(basename "$p")
        name=$base
        n=2
        while [[ -e $trash/files/$name || -e $trash/info/$name.trashinfo ]]; do
            name="$base.$n"
            ((n++))
        done
        info=$trash/info/$name.trashinfo
        printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' "$(tb_urlencode "$abs")" \
            "$(date +%Y-%m-%dT%H:%M:%S)" > "$info" || return 1
        if ! mv -- "$p" "$trash/files/$name"; then
            rm -f "$info"
            return 1
        fi
        TB_TRASHED+=("$name")
    done
}

# Put a file back from the trash. Arguments: the name inside Trash/files,
# and the path to restore it to. Refuses to overwrite.
tb_untrash() {
    local trash=${XDG_DATA_HOME:-$HOME/.local/share}/Trash name=$1 dest=$2
    [[ -e $trash/files/$name ]] || { tb_err "$name is no longer in the trash"; return 1; }
    [[ -e $dest ]] && { tb_err "$dest already exists"; return 1; }
    mv -- "$trash/files/$name" "$dest" && rm -f "$trash/info/$name.trashinfo"
}

# Percent-encode a path for a .trashinfo file.
tb_urlencode() {
    local LC_ALL=C s=$1 out="" c i
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:i:1}
        case $c in
            [A-Za-z0-9/._~-]) out+=$c ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$out"
}

# The question after a job that leaves its input behind, for unpack and squash.
# Usage: tb_offer_delete "Delete x.zip (2.4MB)? It goes to the trash." "x.zip is in the trash." path...
# TB_RM=1 deletes without asking, TB_KEEP=1 never asks. Without a terminal
# it keeps the files. Answering no keeps them and is not an error.
tb_offer_delete() {
    local question=$1 done_msg=$2
    shift 2
    (( ${TB_KEEP:-0} )) && return 0
    if (( ! ${TB_RM:-0} )); then
        tb_is_tty || return 0
        local saved=$TB_YES
        TB_YES=0
        tb_ask "$question"
        local rc=$?
        TB_YES=$saved
        (( rc == 0 )) || return 0
    fi
    if tb_trash "$@"; then
        tb_info "$done_msg"
    else
        tb_warn "could not move to the trash, nothing was deleted"
        return 1
    fi
}

# ---------------------------------------------------------------- numbers

# Bytes as 512B, 2.4KB, 31MB, 1.2GB. A second argument goes between the
# number and the unit, so tb_human 32505856 " " gives "31 MB".
tb_human() {
    local b=${1:-0} sep=${2:-} u=0 div=1 units=(B KB MB GB TB PB) t
    if (( b < 1024 )); then
        echo "$b$sep${units[0]}"
        return
    fi
    while (( b / div >= 1024 && u < 5 )); do
        div=$(( div * 1024 ))
        ((u++))
    done
    # Round to the nearest tenth below 10, to the nearest whole above it.
    t=$(( (b * 10 + div / 2) / div ))
    if (( t >= 10240 && u < 5 )); then
        div=$(( div * 1024 ))
        ((u++))
        t=$(( (b * 10 + div / 2) / div ))
    fi
    if (( t < 100 && t % 10 )); then
        echo "$(( t / 10 )).$(( t % 10 ))$sep${units[u]}"
    else
        echo "$(( (t + 5) / 10 ))$sep${units[u]}"
    fi
}

# Total size in bytes of files and folders, counting the files only. du -sb
# before coreutils 9 adds 4KB per folder.
tb_bytes() {
    local total=0 p s
    for p in "$@"; do
        [[ $p == -* ]] && p=./$p
        if [[ -f $p ]]; then
            s=$(stat -c %s -- "$p" 2>/dev/null || wc -c <"$p")
        elif find "$p" -maxdepth 0 -printf '' 2>/dev/null; then
            s=$(find "$p" -type f -printf '%s\n' 2>/dev/null | awk '{ s += $1 } END { printf "%.0f", s }')
        elif [[ -d $p ]]; then
            # BusyBox find has no -printf.
            s=$(find "$p" -type f -exec stat -c %s -- {} + 2>/dev/null | awk '{ s += $1 } END { printf "%.0f", s }')
        else
            s=$(du -sk -- "$p" 2>/dev/null)
            s=$(( ${s%%[[:space:]]*} * 1024 ))
        fi
        total=$(( total + ${s:-0} ))
    done
    echo "$total"
}

# Milliseconds since the epoch. Whole seconds on systems without %N.
tb_now_ms() {
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        local t=${EPOCHREALTIME/,/.}
        echo $(( ${t%.*} * 1000 + 10#${t#*.} / 1000 ))
        return
    fi
    local n
    n=$(date +%s%N)
    if [[ $n == *N ]]; then echo $(( ${n%N} * 1000 )); else echo $(( n / 1000000 )); fi
}

# Milliseconds as 0.4s, 18s or 3m05s.
tb_elapsed() {
    local ms=$1
    if (( ms < 10000 )); then printf '%d.%ds' $((ms / 1000)) $((ms % 1000 / 100))
    elif (( ms < 60000 )); then printf '%ds' $((ms / 1000))
    elif (( ms < 3600000 )); then printf '%dm%02ds' $((ms / 60000)) $((ms % 60000 / 1000))
    else printf '%dh%02dm' $((ms / 3600000)) $((ms % 3600000 / 60000)); fi
}

# Seconds as an age: 5s, 3m, 2h, 40d, 1y.
tb_age() {
    local s=${1:-0}
    (( s < 0 )) && s=0
    if (( s < 60 )); then echo "${s}s"
    elif (( s < 3600 )); then echo "$(( s / 60 ))m"
    elif (( s < 86400 )); then echo "$(( s / 3600 ))h"
    elif (( s < 31536000 )); then echo "$(( s / 86400 ))d"
    else echo "$(( s / 31536000 ))y"; fi
}

# A size such as 100K, 1.5G, 25MB or 4KiB in bytes. Returns 1 when it is not a size.
tb_parse_size() {
    local s=${1^^} mult=1
    s=${s%B}
    s=${s%I}
    [[ $s =~ ^([0-9]+(\.[0-9]+)?)([KMGT]?)$ ]] || return 1
    case ${BASH_REMATCH[3]} in
        K) mult=1024 ;; M) mult=1048576 ;; G) mult=1073741824 ;; T) mult=1099511627776 ;;
    esac
    awk -v n="${BASH_REMATCH[1]}" -v m="$mult" 'BEGIN { printf "%.0f\n", n * m }'
}

# "1 file", "3 files". A third argument is the plural when it is not word+s.
tb_plural() {
    local n=$1 one=$2 many=${3:-${2}s}
    if (( n == 1 )); then echo "$n $one"; else echo "$n $many"; fi
}

# 1234567 as 1,234,567.
tb_commas() {
    local n=$1 out=""
    while (( ${#n} > 3 )); do
        out=",${n: -3}$out"
        n=${n:0:${#n}-3}
    done
    echo "$n$out"
}

# ---------------------------------------------------------------- files and state

# Folders toolbelt writes to, created on first use.
tb_state_dir()  { local d=${XDG_STATE_HOME:-$HOME/.local/state}/toolbelt; mkdir -p "$d" && echo "$d"; }
tb_cache_dir()  { local d=${XDG_CACHE_HOME:-$HOME/.cache}/toolbelt; mkdir -p "$d" && echo "$d"; }
tb_config_dir() { local d=${XDG_CONFIG_HOME:-$HOME/.config}/toolbelt; mkdir -p "$d" && echo "$d"; }

# A path that does not exist yet: name, name-1, name-2. For a file the
# number goes before the extension, so notes.txt becomes notes-1.txt.
tb_free_name() {
    local p=$1 base=$1 ext="" n=1
    if [[ ${2:-dir} == file && $(basename "$1") == ?*.* ]]; then
        base=${1%.*}
        ext=.${1##*.}
    fi
    while [[ -e $p || -L $p ]]; do
        p="$base-$n$ext"
        ((n++))
    done
    echo "$p"
}

# Temp files and folders removed when the command exits, even on Ctrl+C.
TB_CLEANUP=()
tb_cleanup_add() { TB_CLEANUP+=("$@"); }
tb_cleanup() {
    local p
    for p in "${TB_CLEANUP[@]}"; do
        [[ -n $p && -e $p ]] && rm -rf -- "$p"
    done
    TB_CLEANUP=()
}
trap tb_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Make a temp folder, removed on exit, and store its path in a variable.
# It must not run in $( ), or the cleanup list never learns the path.
# Usage: tb_tmpdir var [parent folder, default /tmp]
tb_tmpdir() {
    local _d
    _d=$(mktemp -d "${2:-${TMPDIR:-/tmp}}/.$TB_CMD-XXXXXX") || return 1
    tb_cleanup_add "$_d"
    printf -v "$1" '%s' "$_d"
}

# Free kilobytes on the filesystem that holds a path.
tb_free_kb() { df -Pk -- "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'; }

# Available memory in kilobytes, from /proc/meminfo.
tb_mem_avail_kb() { awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo 2>/dev/null; }

# True when a local TCP port has a listener. Reads /proc, so it needs no ss.
tb_port_used() {
    local hex
    hex=$(printf '%04X' "$1")
    awk -v h=":$hex" 'NR > 1 && $4 == "0A" && substr($2, length($2) - 4) == h { f = 1 } END { exit !f }' \
        /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

# The first free TCP port at or above a start, default 8000.
tb_free_port() {
    local p=${1:-8000}
    while (( p < 65535 )); do
        tb_port_used "$p" || { echo "$p"; return 0; }
        ((p++))
    done
    return 1
}

# True when progress bars and live updates should be drawn.
tb_progress() { [[ -t 2 ]] && (( ! TB_QUIET && ! TB_VERBOSE )); }

# A status line that overwrites itself, only when tb_progress is true.
# End it with tb_line_end before printing anything else.
tb_line() { tb_progress || return 0; printf '\r%s\e[K' "$*" >&2; }
tb_line_end() { tb_progress || return 0; printf '\r\e[K' >&2; }
