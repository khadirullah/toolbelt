#!/usr/bin/env bash
# Install toolbelt for one user, with no sudo.
#
#   ./install.sh                     install to ~/.local
#   ./install.sh --prefix DIR        install somewhere else
#   ./install.sh --uninstall         remove everything this script put in place
#
# Piped from curl it downloads the latest main branch first:
#   curl -fsSL https://raw.githubusercontent.com/khadirullah/toolbelt/main/install.sh | bash
#
# The files go to PREFIX/share/toolbelt. Each command is a link in PREFIX/bin,
# man pages are links in PREFIX/share/man/man1, and bash completion is a link
# per command in PREFIX/share/bash-completion/completions. The file
# PREFIX/share/toolbelt/.installed lists every link, so uninstall removes
# exactly those and nothing else.

set -uo pipefail

TARBALL=https://github.com/khadirullah/toolbelt/archive/refs/heads/main.tar.gz
prefix=$HOME/.local
uninstall=0
quiet=0

say() { (( quiet )) || echo "$*"; }
die() { echo "install: $*" >&2; exit 1; }

while (( $# )); do
    case $1 in
        --prefix)      [[ -n ${2:-} ]] || die "--prefix needs a folder"; prefix=$2; shift ;;
        --prefix=*)    prefix=${1#*=} ;;
        --uninstall)   uninstall=1 ;;
        -q|--quiet)    quiet=1 ;;
        -h|--help)     sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *)             die "unknown option $1, see ./install.sh --help" ;;
    esac
    shift
done

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    die "toolbelt needs bash 4.4 or newer, this is $BASH_VERSION"
fi

mkdir -p "$prefix" || die "cannot create $prefix"
prefix=$(cd "$prefix" && pwd)
root=$prefix/share/toolbelt
record=$root/.installed
rc_mark='# toolbelt'

remove_rc_lines() {
    local f
    for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f $f ]] && grep -q "$rc_mark\$" "$f" || continue
        local tmp
        tmp=$(mktemp) || return 1
        grep -v "$rc_mark\$" "$f" > "$tmp" && cat "$tmp" > "$f"
        rm -f "$tmp"
        say "removed the toolbelt line from ${f/#$HOME/\~}"
    done
}

if (( uninstall )); then
    [[ -r $record ]] || die "no toolbelt install found in $prefix"
    n=0
    while read -r kind path; do
        case $kind in
            bin|man|comp)
                # Only remove links that still point into toolbelt.
                if [[ -L $path && $(readlink "$path") == "$root"/* ]]; then
                    rm -f "$path" && ((n++))
                fi ;;
        esac
    done < "$record"
    remove_rc_lines
    rm -rf "${root:?}"
    say "toolbelt removed, $n links. Open a new terminal to drop mkcd and up."
    exit 0
fi

# Run from a clone, or download the source first when piped from curl.
src=""
here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [[ -n $here && -f $here/lib/common.sh && -f $here/lib/commands ]]; then
    src=$here
else
    command -v curl >/dev/null || die "needs curl to download toolbelt"
    command -v tar >/dev/null || die "needs tar to unpack the download"
    dl=$(mktemp -d) || die "cannot make a temp folder"
    trap 'rm -rf "$dl"' EXIT
    say "downloading toolbelt"
    curl -fsSL "$TARBALL" | tar -xz -C "$dl" || die "download failed, nothing was installed"
    src=$(find "$dl" -mindepth 1 -maxdepth 1 -type d | head -1)
fi

[[ $src == "$root" ]] && die "run install.sh from a clone, not from the installed copy"

# Copy the files that run. Tests, docs and tools stay in the clone.
old_record=""
[[ -r $record ]] && old_record=$(cat "$record")
rm -rf "${root:?}.new"
mkdir -p "$root.new" || die "cannot write to $prefix/share"
cp -R "$src/bin" "$src/lib" "$src/shell" "$src/completions" "$src/VERSION" "$src/install.sh" "$root.new/" ||
    die "copy failed"
[[ -d $src/man ]] && cp -R "$src/man" "$root.new/"
rm -rf "$root" && mv "$root.new" "$root" || die "could not move the new files into place"

mkdir -p "$prefix/bin" "$prefix/share/man/man1" "$prefix/share/bash-completion/completions"
{
    echo "prefix=$prefix"
    echo "version=$(cat "$root/VERSION")"
} > "$record"

# Link each command. Never replace a file that is not a toolbelt link.
linked=0
skipped=()
for f in "$root"/bin/*; do
    name=$(basename "$f")
    dest=$prefix/bin/$name
    if [[ -e $dest || -L $dest ]] && ! [[ -L $dest && $(readlink "$dest") == "$root"/* ]]; then
        skipped+=("$name")
        continue
    fi
    ln -sfn "$f" "$dest"
    echo "bin $dest" >> "$record"
    ((linked++))
    if [[ -f $root/man/man1/$name.1 ]]; then
        ln -sfn "$root/man/man1/$name.1" "$prefix/share/man/man1/$name.1"
        echo "man $prefix/share/man/man1/$name.1" >> "$record"
    fi
    comp=$prefix/share/bash-completion/completions/$name
    if [[ ! -e $comp || -L $comp ]]; then
        ln -sfn "$root/completions/toolbelt.bash" "$comp"
        echo "comp $comp" >> "$record"
    fi
done
for page in "$root"/man/man1/mkcd.1 "$root"/man/man1/up.1; do
    [[ -f $page ]] || continue
    ln -sfn "$page" "$prefix/share/man/man1/$(basename "$page")"
    echo "man $prefix/share/man/man1/$(basename "$page")" >> "$record"
done

# Links from an older install that this version no longer has.
if [[ -n $old_record ]]; then
    while read -r kind path; do
        [[ $kind == bin || $kind == man || $kind == comp ]] || continue
        grep -qxF "$kind $path" "$record" && continue
        [[ -L $path && ! -e $path ]] && rm -f "$path"
    done <<<"$old_record"
fi

say "installed toolbelt $(cat "$root/VERSION"), $linked commands in ${prefix/#$HOME/\~}/bin"
if (( ${#skipped[@]} )); then
    echo "install: skipped ${skipped[*]}, a file with that name already exists in ${prefix/#$HOME/\~}/bin" >&2
fi
if [[ :$PATH: != *":$prefix/bin:"* ]]; then
    say "${prefix/#$HOME/\~}/bin is not on your PATH. Add this line to ~/.bashrc or ~/.zshrc:"
    say "  export PATH=\"$prefix/bin:\$PATH\""
fi
if [[ -f /etc/alpine-release ]] && ! [[ -x /bin/bash || -x /usr/bin/bash ]]; then
    say "Alpine does not ship bash. Run: apk add bash"
fi
say "next: toolbelt doctor, then toolbelt shell enable functions for mkcd and up"
