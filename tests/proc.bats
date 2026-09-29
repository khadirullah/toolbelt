#!/usr/bin/env bats
# Tests for proc. Each test starts its own sleeper and kills it by pid.

load helpers

setup() {
    tb_setup
    cp "$(type -P sleep)" tbproc-sleeper
    tb_stub systemctl 'echo active'
    PIDS=()
}

teardown() {
    local p
    for p in "${PIDS[@]}"; do
        kill "$p" 2>/dev/null || true
    done
}

# The command line checks need sleep to be a real program. With
# coreutils-single, as on Rocky, it is a script that runs coreutils.
needs_real_sleep() {
    head -c 4 tbproc-sleeper | grep -q ELF || skip "sleep is a script here"
}

# BusyBox, as on Alpine, picks the applet by name, so a renamed copy of its
# sleep does not sleep.
needs_sleeper() {
    ./tbproc-sleeper 0 2>/dev/null || skip "sleep is a BusyBox applet here"
}

# Start a sleeper and store its pid in $pid.
start() {
    needs_sleeper
    ./tbproc-sleeper 60 "$@" >/dev/null 2>&1 3>&- &
    pid=$!
    PIDS+=("$pid")
}

@test "help prints usage and exits 0" {
    run proc --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: proc [-f] [-e] PID | NAME" ]
}

@test "bad usage exits 2" {
    run proc
    [ "$status" -eq 2 ]
    run proc 1 2
    [ "$status" -eq 2 ]
    run proc --nope 1
    [ "$status" -eq 2 ]
    run proc 1 -- -x
    [ "$status" -eq 2 ]
}

@test "no such process exits 1" {
    run proc 999999999
    [ "$status" -eq 1 ]
    [ "$output" = "proc: no process with pid 999999999" ]
    run proc no-such-process-name-here
    [ "$status" -eq 1 ]
    [ "$output" = "proc: no process matches no-such-process-name-here" ]
}

@test "shows everything about one pid" {
    needs_real_sleep
    start
    tb_stub ss "echo 'tcp LISTEN 0 5 127.0.0.1:8384 0.0.0.0:* users:((\"tbproc-sleeper\",pid=$pid,fd=3))'"
    run proc "$pid"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "pid      $pid  ./tbproc-sleeper 60" ]
    [[ ${lines[1]} == "user     $(id -un), started "*" ago" ]]
    [[ ${lines[2]} == "tree     "*" > tbproc-sleeper($pid)" ]]
    [[ $output == *"memory   RSS "*", swap "*", oom score "* ]]
    [[ $output == *"cpu      "*"% now, "*" in total, 1 thread"* ]]
    [[ $output == *"ports    tcp 127.0.0.1:8384"* ]]
    [[ $output == *"files    "*" open"* ]]
}

@test "finds a process by name" {
    start
    run proc tbproc-sleeper
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "pid      $pid  "* ]]
}

@test "a name that matches several lists them and exits 2" {
    needs_real_sleep
    start
    local first=$pid
    start
    run proc tbproc-sleeper
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "proc: 2 processes match tbproc-sleeper. Give a pid." ]
    [[ $output == *"$first  ./tbproc-sleeper 60"* ]]
    [[ $output == *"$pid  ./tbproc-sleeper 60"* ]]
}

@test "-q prints the pid and command line" {
    needs_real_sleep
    start
    run proc -q "$pid"
    [ "$status" -eq 0 ]
    [ "$output" = "$pid  ./tbproc-sleeper 60" ]
}

@test "-f lists open files and counts deleted ones" {
    needs_real_sleep
    needs_sleeper
    printf 'notes\n' > notes.txt
    ./tbproc-sleeper 60 >/dev/null 2>&1 3<notes.txt &
    pid=$!
    PIDS+=("$pid")
    tb_stub ss 'exit 0'
    run proc -f "$pid"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "pid $pid  ./tbproc-sleeper 60" ]
    [ "${lines[1]}" = "FD    TYPE  NAME" ]
    [[ $output == *"3     file  $PWD/notes.txt"* ]]
    [[ $output == *"1     dev   /dev/null"* ]]
    rm notes.txt
    run proc "$pid"
    [[ $output == *"1 deleted but still open"* ]]
}

@test "-e masks secret values" {
    FOO_TOKEN=abc123 DB_URL='postgres://app:hunter2@db/x' PLAIN=hello start
    run proc -e "$pid"
    [ "$status" -eq 0 ]
    [[ $output == *"FOO_TOKEN=***"* ]]
    [[ $output == *"DB_URL=postgres://app:***@db/x"* ]]
    [[ $output == *"PLAIN=hello"* ]]
    [[ $output != *abc123* ]]
    [[ $output != *hunter2* ]]
}

@test "works without ss and systemctl" {
    start
    tb_without ss systemctl
    run proc "$pid"
    [ "$status" -eq 0 ]
    [[ $output != *"ports "* ]]
    [[ $output == *"files    "* ]]
}
