# shellcheck shell=bash
# Loaded by every test file with `load helpers`. Call tb_setup from setup().

TB_REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd)

# A clean home, state and trash for each test, with the repo's bin first on PATH.
tb_setup() {
    export HOME=$BATS_TEST_TMPDIR/home
    export XDG_DATA_HOME=$HOME/.local/share XDG_STATE_HOME=$HOME/.local/state
    export XDG_CACHE_HOME=$HOME/.cache XDG_CONFIG_HOME=$HOME/.config
    export NO_COLOR=1
    unset TB_TEST_TTY
    mkdir -p "$HOME" "$BATS_TEST_TMPDIR/stubs" "$BATS_TEST_TMPDIR/work"
    export PATH="$BATS_TEST_TMPDIR/stubs:$TB_REPO/bin:$PATH"
    cd "$BATS_TEST_TMPDIR/work" || return 1
}

# Replace a command with a small script for this test.
# Usage: tb_stub kubectl 'echo "pod/web-1"'
tb_stub() {
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BATS_TEST_TMPDIR/stubs/$1"
    chmod +x "$BATS_TEST_TMPDIR/stubs/$1"
}

# Run with a PATH where the named commands do not exist, to test the
# "needs x" message. Builds a folder of links to everything else.
# Usage: tb_without 7z 7zz 7za; run unpack x.7z
tb_without() {
    local d=$BATS_TEST_TMPDIR/nopath dir f name skip
    mkdir -p "$d"
    local IFS=:
    for dir in $PATH; do
        [[ -d $dir ]] || continue
        for f in "$dir"/*; do
            name=${f##*/}
            [[ -x $f && ! -e $d/$name ]] || continue
            for skip in "$@"; do [[ $name == "$skip" ]] && continue 2; done
            ln -s "$f" "$d/$name"
        done
    done
    export PATH=$d
}

# Print a time N seconds ago as @EPOCH, for touch -d and date -d. BusyBox
# reads @EPOCH but not words like "3 days ago". A negative N is in the future.
tb_ago() {
    echo "@$(( $(date +%s) - $1 ))"
}

# Skip the test unless every named tool is installed. CI installs only the
# common ones, so tests that run a real 7z, gpg or kubectl use this.
tb_needs() {
    local t
    for t; do command -v "$t" >/dev/null || skip "$t is not installed"; done
}

# Answer questions through stdin, as if a person typed at a terminal.
# Usage: tb_tty; run bash -c 'echo y | unpack x.zip'
tb_tty() { export TB_TEST_TTY=1; }

# Files in the trash, one name per line.
tb_trash_list() { ls -1 "$XDG_DATA_HOME/Trash/files" 2>/dev/null; }
