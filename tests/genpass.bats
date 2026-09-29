#!/usr/bin/env bats
# Tests for genpass.

load helpers

setup() {
    tb_setup
    unset DISPLAY TMUX
    export WAYLAND_DISPLAY=wayland-0
    tb_stub wl-copy 'cat > "$BATS_TEST_TMPDIR/board"'
}

@test "help prints usage and exits 0" {
    run genpass --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: genpass "* ]]
}

@test "bad usage exits 2" {
    run genpass -l 4
    [ "$status" -eq 2 ]
    [[ $output == "genpass: length 4 is below the minimum of 8"* ]]
    run genpass -l x
    [ "$status" -eq 2 ]
    run genpass -n 0
    [ "$status" -eq 2 ]
    run genpass -w 2
    [ "$status" -eq 2 ]
    run genpass -w 5 -l 30
    [ "$status" -eq 2 ]
    run genpass -s _
    [ "$status" -eq 2 ]
    run genpass -c -n 3
    [ "$status" -eq 2 ]
    run genpass extra
    [ "$status" -eq 2 ]
    run genpass -p
    [ "$status" -eq 2 ]
}

@test "a password is 20 characters with every kind of character" {
    run genpass
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${#output}" -eq 20 ]
    [[ $output == *[a-z]* && $output == *[A-Z]* && $output == *[0-9]* ]]
    [[ $output == *[!A-Za-z0-9]* ]]
    [[ $output =~ ^[A-Za-z0-9\!#%*+=?@^_~-]+$ ]]
}

@test "-n and -l and --no-symbols" {
    run genpass -n 3 -l 32 --no-symbols
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    for l in "${lines[@]}"; do
        [ "${#l}" -eq 32 ]
        [[ $l =~ ^[A-Za-z0-9]+$ ]]
    done
    [ "${lines[0]}" != "${lines[1]}" ]
}

@test "-w makes a passphrase from the word list" {
    run genpass -w 5
    [ "$status" -eq 0 ]
    [[ $output =~ ^[a-z]+(-[a-z]+){4}$ ]]
    IFS=- read -ra ws <<<"$output"
    for w in "${ws[@]}"; do grep -qx "$w" "$TB_REPO/lib/words"; done
}

@test "-s sets the separator and -v tells the strength" {
    run genpass -v -w 4 -s .
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^[a-z]+(\.[a-z]+){3}$ ]]
    [ "${lines[1]}" = "genpass: 4 words from 7776, about 51 bits" ]
    run genpass -v
    [ "${lines[1]}" = "genpass: 20 characters from 74, about 124 bits" ]
    run genpass -v --no-symbols -l 8
    [ "${lines[1]}" = "genpass: 8 characters from 62, about 47 bits" ]
}

@test "the word list has 7776 different words" {
    [ "$(grep -vc '^#' "$TB_REPO/lib/words")" -eq 7776 ]
    [ "$(grep -v '^#' "$TB_REPO/lib/words" | sort -u | wc -l)" -eq 7776 ]
}

@test "-c copies with clip and prints no password" {
    run genpass -c
    [ "$status" -eq 0 ]
    [ "$output" = "clip: copied 20 bytes with wl-copy" ]
    [ "$(wc -c < "$BATS_TEST_TMPDIR/board")" -eq 20 ]
    run genpass -q -c -w 3
    [ -z "$output" ]
}

@test "a copy that fails prints no password" {
    unset WAYLAND_DISPLAY
    export DISPLAY=:0
    tb_without xclip xsel
    run genpass -c
    [ "$status" -eq 1 ]
    [[ $output == *"clip: needs xclip"* ]]
    [[ $output == *"genpass: could not copy, nothing was printed"* ]]
}
