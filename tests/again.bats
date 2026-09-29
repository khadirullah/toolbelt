#!/usr/bin/env bats
# Tests for again.

load helpers
bats_require_minimum_version 1.5.0

setup() {
    tb_setup
    # Waits are logged, not slept, so the tests take no time.
    tb_stub sleep 'echo "$1" >> "$BATS_TEST_TMPDIR/slept"'
    # flaky fails until its third run, with exit 7.
    tb_stub flaky 'n=$(( $(cat "$BATS_TEST_TMPDIR/runs" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$BATS_TEST_TMPDIR/runs"
(( n >= 3 )) && { echo ok; exit 0; }
echo "run $n failed" >&2; exit 7'
}

@test "help prints usage and exits 0" {
    run again --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: again "* ]]
}

@test "bad usage exits 2" {
    run again
    [ "$status" -eq 2 ]
    [[ $output == *"no command to run"* ]]
    run again -n 0 -- true
    [ "$status" -eq 2 ]
    run again -d x -- true
    [ "$status" -eq 2 ]
    run again --on 300 -- true
    [ "$status" -eq 2 ]
    run again --nope -- true
    [ "$status" -eq 2 ]
}

@test "a missing command exits 127" {
    run -127 again -- no-such-command-here
    [ "$status" -eq 127 ]
    [ "$output" = "again: no-such-command-here: command not found" ]
}

@test "retries until it works, with doubling waits" {
    run again -- flaky
    [ "$status" -eq 0 ]
    [[ $output == *"again: try 1 of 5 failed, exit 7, next in 1s"* ]]
    [[ $output == *"again: try 2 of 5 failed, exit 7, next in 2s"* ]]
    [[ $output == *"ok"* ]]
    [[ $output == *"again: try 3 of 5 worked"*"in total" ]]
    [ "$(cat "$BATS_TEST_TMPDIR/slept" | tr '\n' ' ')" = "1 2 " ]
}

@test "a first try that works prints nothing of its own" {
    run again -- echo hello
    [ "$status" -eq 0 ]
    [ "$output" = hello ]
}

@test "gives up with the command's last exit code" {
    run again -n 3 -- sh -c 'exit 4'
    [ "$status" -eq 4 ]
    [[ $output == *"again: gave up after 3 tries, last exit 4" ]]
    [ "$(wc -l < "$BATS_TEST_TMPDIR/slept")" -eq 2 ]
}

@test "--fixed keeps the wait and --max-delay caps it" {
    run again -n 4 -d 5 --fixed -- false
    [ "$(cat "$BATS_TEST_TMPDIR/slept" | tr '\n' ' ')" = "5 5 5 " ]
    rm "$BATS_TEST_TMPDIR/slept"
    run again -n 5 -d 3 --max-delay 7 -- false
    [ "$(cat "$BATS_TEST_TMPDIR/slept" | tr '\n' ' ')" = "3 6 7 7 " ]
}

@test "--on stops at an exit code it was not given" {
    run again --on 1 -- sh -c 'exit 3'
    [ "$status" -eq 3 ]
    [[ $output == *"exit 3, which is not in --on"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/slept" ]
    run again --on 7 --on 1 -- flaky
    [ "$status" -eq 0 ]
}

@test "the command's own options are not read as again's" {
    run again -n 2 printf '%s-%s\n' -n -d
    [ "$status" -eq 0 ]
    [ "$output" = "-n--d" ]
    run again -qn2 -- false
    [ "$status" -eq 1 ]
    [ "$output" = "again: gave up after 2 tries, last exit 1" ]
}

@test "-v shows the command before each try" {
    run again -v -- echo hi
    [ "${lines[0]}" = "+ echo hi" ]
}
