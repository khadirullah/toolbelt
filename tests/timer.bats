#!/usr/bin/env bats
# Tests for timer. Countdowns last one second at most. notify-send is a stub.

load helpers

setup() {
    tb_setup
    unset WAYLAND_DISPLAY
    export DISPLAY=:0
    tb_stub notify-send 'printf "%s|" "$@" >> "$BATS_TEST_TMPDIR/notices"'
}

notices() { cat "$BATS_TEST_TMPDIR/notices" 2>/dev/null; }

@test "help prints usage and exits 0" {
    run timer --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: timer "* ]]
}

@test "bad usage exits 2" {
    run timer 25x
    [ "$status" -eq 2 ]
    [[ $output == "timer: cannot read 25x. Use 90, 90s, 25m, 1h30m or --at 17:30"* ]]
    run timer 0
    [ "$status" -eq 2 ]
    run timer 1m-
    [ "$status" -eq 2 ]
    run timer --at 25:00
    [ "$status" -eq 2 ]
    run timer --at noon
    [ "$status" -eq 2 ]
    run timer --nope
    [ "$status" -eq 2 ]
}

@test "counts down, then says done and sends a notice" {
    run timer 1s "stand up"
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^timer:\ 0:01\ left,\ ends\ at\ [0-9]{2}:[0-9]{2},\ stand\ up$ ]]
    [[ $output =~ timer:\ done\ at\ [0-9]{2}:[0-9]{2},\ stand\ up ]]
    [[ $output == *$'\a'* ]]
    [ "$(notices)" = "-u|critical|--|Timer done|stand up|" ]
}

@test "without a message the notice names the duration" {
    run timer 1
    [ "$status" -eq 0 ]
    [ "$(notices)" = "-u|critical|--|Timer done|1 is up|" ]
}

@test "--bell sends no notice, and no notify-send is fine" {
    run timer --bell 1s
    [ "$status" -eq 0 ]
    [ -z "$(notices)" ]
    tb_without notify-send
    run timer 1s
    [ "$status" -eq 0 ]
}

@test "-q keeps only the done line" {
    run timer -q 1s tea
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ ${lines[0]} == $'\a'"timer: done at "*", tea" ]]
}

@test "--at counts to a clock time" {
    at=$(date -d "$(tb_ago -7200)" +%H:%M)
    run timeout 1 timer --at "$at" call
    [ "$status" -eq 124 ]
    [[ ${lines[0]} =~ ^timer:\ 1:5[89]:[0-9]{2}\ left,\ ends\ at\ $at,\ call$ ]]
    [[ $output == *"timer: stopped with 1:5"*" left"* ]]
}

@test "a time that has passed means tomorrow" {
    at=$(date -d "$(tb_ago 7200)" +%H:%M)
    run timeout 1 timer --at "$at"
    [[ ${lines[0]} =~ ^timer:\ 2[12]:[0-9]{2}:[0-9]{2}\ left ]]
}

@test "stopwatch records a lap per line and stops at the end of input" {
    run bash -c 'printf "\n\n" | timer'
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^00:00:00\.[0-9]\ \ lap\ 1$ ]]
    [[ ${lines[1]} =~ ^00:00:00\.[0-9]\ \ lap\ 2,\ \+00:00:00\.[0-9]$ ]]
    [[ ${lines[2]} =~ ^00:00:00\.[0-9]\ \ stopped$ ]]
}
