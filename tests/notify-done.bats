#!/usr/bin/env bats
# Tests for notify-done. notify-send is a stub, so no real notice pops up.

load helpers
bats_require_minimum_version 1.5.0

setup() {
    tb_setup
    unset WAYLAND_DISPLAY
    export DISPLAY=:0
    tb_stub notify-send 'printf "%s|" "$@" >> "$BATS_TEST_TMPDIR/notices"; echo >> "$BATS_TEST_TMPDIR/notices"'
}

notices() { cat "$BATS_TEST_TMPDIR/notices" 2>/dev/null; }

@test "help prints usage and exits 0" {
    run notify-done --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: notify-done "* ]]
}

@test "bad usage exits 2" {
    run notify-done
    [ "$status" -eq 2 ]
    [[ $output == *"no command to run"* ]]
    run notify-done --min x true
    [ "$status" -eq 2 ]
    run notify-done --nope true
    [ "$status" -eq 2 ]
}

@test "a missing command exits 127" {
    run -127 notify-done no-such-command-here
    [[ $output == "notify-done: no-such-command-here: command not found" ]]
}

@test "a short command stays silent" {
    run notify-done echo hi
    [ "$status" -eq 0 ]
    [ "$output" = hi ]
    [ -z "$(notices)" ]
}

@test "sends a notice with the time and the exit code" {
    tb_stub make 'echo built'
    run notify-done --min 0 make build -j4
    [ "$status" -eq 0 ]
    [[ $output == *"built"* ]]
    [[ $output == *"notify-done: make build finished, exit 0, "* ]]
    [[ $(notices) == "-u|normal|--|make build|done in "*"s|" ]]
}

@test "a failure keeps the exit code and sends a critical notice" {
    run notify-done --min 0 -t "EKS apply" sh -c 'exit 3'
    [ "$status" -eq 3 ]
    [[ $output == *"notify-done: EKS apply failed, exit 3, "* ]]
    [[ $(notices) == "-u|critical|--|EKS apply|failed with exit 3 after "* ]]
}

@test "no desktop rings the bell instead" {
    unset DISPLAY
    run notify-done --min 0 true
    [ "$status" -eq 0 ]
    [[ $output == *$'\a'* ]]
    [[ $output == *"no desktop, rang the terminal bell instead"* ]]
    [ -z "$(notices)" ]
}

@test "--bell skips the desktop notice" {
    run notify-done --min 0 --bell true
    [[ $output == *$'\a'* ]]
    [ -z "$(notices)" ]
}

@test "without notify-send it rings the bell and says what to install" {
    tb_without notify-send
    run notify-done --min 0 true
    [ "$status" -eq 0 ]
    [[ $output == *"no notify-send, rang the terminal bell instead. Install it with"* ]]
}

@test "the command's own options are not read as notify-done's" {
    run notify-done printf '%s\n' -t
    [ "$status" -eq 0 ]
    [ "$output" = "-t" ]
}
