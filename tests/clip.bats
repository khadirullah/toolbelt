#!/usr/bin/env bats
# Tests for clip. Every clipboard tool is a stub that keeps the clipboard in
# a file, and OSC 52 goes to a file instead of the terminal.

load helpers

setup() {
    tb_setup
    unset WAYLAND_DISPLAY DISPLAY TMUX
    BOARD=$BATS_TEST_TMPDIR/board
    export BOARD
    tb_stub wl-copy 'echo "wl-copy $*" >> "$BOARD.log"; [[ " $* " == *" --clear "* ]] && { : > "$BOARD"; exit 0; }; cat > "$BOARD"'
    tb_stub wl-paste 'echo "wl-paste $*" >> "$BOARD.log"; cat "$BOARD"'
    tb_stub xclip 'echo "xclip $*" >> "$BOARD.log"; if [[ " $* " == *" -out "* ]]; then cat "$BOARD"; else cat > "$BOARD"; fi'
    tb_stub xsel 'echo "xsel $*" >> "$BOARD.log"; case " $* " in *" --output "*) cat "$BOARD" ;; *" --clear "*) : > "$BOARD" ;; *) cat > "$BOARD" ;; esac'
    tb_stub sleep ':'
}

log() { cat "$BOARD.log" 2>/dev/null; }

@test "help prints usage and exits 0" {
    run clip --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: command | clip "* ]]
}

@test "bad usage exits 2" {
    run clip a b
    [ "$status" -eq 2 ]
    run clip -o file
    [ "$status" -eq 2 ]
    run clip --clear-after x
    [ "$status" -eq 2 ]
    run clip -c --clear-after 5
    [ "$status" -eq 2 ]
    run clip -p
    [ "$status" -eq 2 ]
    run clip --nope
    [ "$status" -eq 2 ]
}

@test "X11 without xclip or xsel exits 3 with the install line" {
    export DISPLAY=:0
    tb_without xclip xsel
    run bash -c 'echo hello | clip'
    [ "$status" -eq 3 ]
    [[ $output == "clip: needs xclip. Install it with"* ]]
}

@test "Wayland copies with wl-copy and pastes with wl-paste" {
    export WAYLAND_DISPLAY=wayland-0
    run bash -c 'printf "ssh-ed25519 AAAA me\n" | clip'
    [ "$status" -eq 0 ]
    [ "$output" = "clip: copied 20 bytes with wl-copy" ]
    run clip -o
    [ "$output" = "ssh-ed25519 AAAA me" ]
    [[ $(log) == *"wl-paste --no-newline"* ]]
}

@test "a file argument copies the file" {
    export WAYLAND_DISPLAY=wayland-0
    printf 'key\n' > id.pub
    run clip id.pub
    [ "$status" -eq 0 ]
    [ "$(cat "$BOARD")" = key ]
    run clip nothere
    [ "$status" -eq 1 ]
    [[ $output == *"nothere: no such file"* ]]
    mkdir d
    run clip d
    [ "$status" -eq 1 ]
}

@test "X11 uses xclip, and xsel when xclip is missing" {
    export DISPLAY=:0
    run bash -c 'echo hi | clip -v'
    [[ $output == *"+ xclip -selection clipboard -in < "* ]]
    [[ $output == *"clip: copied 3 bytes with xclip"* ]]
    tb_without xclip
    run bash -c 'echo hi | clip --primary'
    [ "$status" -eq 0 ]
    [[ $output == *"with xsel"* ]]
    [[ $(log) == *"xsel --primary --input"* ]]
}

@test "--primary picks the primary selection" {
    export WAYLAND_DISPLAY=wayland-0
    run bash -c 'echo hi | clip --primary'
    [[ $(log) == *"wl-copy --primary"* ]]
}

@test "-c clears the clipboard" {
    export WAYLAND_DISPLAY=wayland-0
    echo secret > "$BOARD"
    run clip -c
    [ "$status" -eq 0 ]
    [ "$output" = "clip: cleared the clipboard" ]
    [ ! -s "$BOARD" ]
}

@test "--clear-after clears in the background when nothing else was copied" {
    export WAYLAND_DISPLAY=wayland-0
    run bash -c 'printf s3cret | clip --clear-after 30'
    [ "$status" -eq 0 ]
    [ "$output" = "clip: copied 6 bytes with wl-copy, clearing in 30s" ]
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BOARD" ] || break; command sleep 0.2; done
    [ ! -s "$BOARD" ]
}

@test "--clear-after leaves a newer copy alone" {
    export WAYLAND_DISPLAY=wayland-0
    tb_stub sleep 'printf newer > "$BOARD"'
    run bash -c 'printf s3cret | clip --clear-after 30'
    command sleep 1
    [ "$(cat "$BOARD")" = newer ]
    [[ $(log) != *"--clear"* ]]
}

@test "no display sends OSC 52 to the terminal" {
    export TB_TEST_OSC52=$BATS_TEST_TMPDIR/tty
    run bash -c 'printf hi | clip'
    [ "$status" -eq 0 ]
    [ "$output" = "clip: copied 2 bytes through the terminal with OSC 52" ]
    [ "$(cat "$TB_TEST_OSC52")" = $'\e]52;c;aGk=\a' ]
    run bash -c 'printf hi | TMUX=/tmp/t clip --primary'
    [ "$(cat "$TB_TEST_OSC52")" = $'\ePtmux;\e\e]52;p;aGk=\a\e\\' ]
}

@test "no display cannot paste" {
    run clip -o
    [ "$status" -eq 3 ]
    [[ $output == *"OSC 52 only copies"* ]]
}

@test "options after -- go to the tool" {
    export WAYLAND_DISPLAY=wayland-0
    head -c 1K /dev/urandom > report.png
    run clip report.png -- --type image/png
    [ "$status" -eq 0 ]
    [[ $(log) == "wl-copy --type image/png" ]]
    cmp report.png "$BOARD"
}
