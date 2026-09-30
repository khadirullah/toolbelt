#!/usr/bin/env bats
# Tests for epoch. The zone is fixed to India, UTC+5:30, so the output is known.

load helpers

setup() {
    tb_setup
    # A POSIX rule, so the tests need no tzdata. Minimal images such as
    # ubuntu:22.04 have none, and a zone name there falls back to UTC.
    export TZ=IST-5:30
}

@test "help prints usage and exits 0" {
    run epoch --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: epoch "* ]]
}

@test "bad usage exits 2" {
    run epoch next-ish
    [ "$status" -eq 2 ]
    [[ $output == "epoch: cannot read next-ish as a timestamp or a date"* ]]
    run epoch --nope
    [ "$status" -eq 2 ]
}

@test "a timestamp prints local, UTC and how long ago" {
    run epoch 1790000000
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "local  Mon 2026-09-21 19:43:20 IST" ]
    [ "${lines[1]}" = "utc    Mon 2026-09-21 14:13:20 UTC" ]
    [[ ${lines[2]} =~ ^(ago|in)\ \ \ \ [0-9]+\ [a-z]+ ]]
}

@test "milliseconds, microseconds and nanoseconds by length" {
    run epoch 1790000000123
    [ "${lines[0]}" = "epoch: read as milliseconds" ]
    [ "${lines[1]}" = "local  Mon 2026-09-21 19:43:20.123 IST" ]
    run epoch 1790000000123456
    [ "${lines[0]}" = "epoch: read as microseconds" ]
    [ "${lines[2]}" = "utc    Mon 2026-09-21 14:13:20.123 UTC" ]
    run epoch 1790000000123456789
    [ "${lines[0]}" = "epoch: read as nanoseconds" ]
    run epoch -q 1790000000123
    [ "${lines[0]}" = "local  Mon 2026-09-21 19:43:20.123 IST" ]
}

@test "a fraction, an @ and a negative number" {
    run epoch 1790000000.5
    [ "${lines[0]}" = "local  Mon 2026-09-21 19:43:20.5 IST" ]
    run epoch @0
    [ "${lines[1]}" = "utc    Thu 1970-01-01 00:00:00 UTC" ]
    run epoch -86400
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "utc    Wed 1969-12-31 00:00:00 UTC" ]
}

@test "ago and in count the two largest units" {
    now=$(date +%s)
    run epoch $(( now - 3 * 86400 - 5 * 3600 - 60 ))
    [ "${lines[2]}" = "ago    3 days, 5 hours" ]
    run epoch $(( now + 3600 + 150 ))
    [[ ${lines[2]} =~ ^in\ \ \ \ \ 1\ hour,\ 2\ minutes$ ]]
}

@test "a date prints its timestamp" {
    run epoch "2026-09-29 14:30"
    [ "$status" -eq 0 ]
    [ "$output" = 1790672400 ]
    run epoch 2026-09-29 14:30
    [ "$output" = 1790672400 ]
    run epoch -u 2026-09-29 09:00
    [ "$output" = 1790672400 ]
    run epoch 2026-09-29T09:00:00Z
    [ "$output" = 1790672400 ]
    run epoch --ms "2026-09-29 14:30:00.250"
    [ "$output" = 1790672400250 ]
}

@test "ISO dates read the same through BusyBox date" {
    if [[ $(readlink -f "$(type -P date)") != */busybox ]]; then
        command -v busybox >/dev/null || skip "no busybox"
        tb_stub date 'exec busybox date "$@"'
    fi
    run epoch 2026-09-29T09:00:00Z
    [ "$output" = 1790672400 ]
    run epoch 2026-09-29T14:30
    [ "$output" = 1790672400 ]
    run epoch -u 2026-09-29T09:00
    [ "$output" = 1790672400 ]
    run epoch 2026-09-29T11:00:00+02:00
    [ "$output" = 1790672400 ]
    run epoch 2026-09-29T04:30:00-0430
    [ "$output" = 1790672400 ]
    run epoch --ms 2026-09-29T09:00:00.25Z
    [ "$output" = 1790672400250 ]
    run epoch --ms "2026-09-29 14:30:00.250"
    [ "$output" = 1790672400250 ]
    run epoch -v 2026-09-29T09:00:00Z
    [ "${lines[1]}" = "+ date -u -d '2026-09-29 09:00:00' +%s" ]
    [ "${lines[2]}" = "epoch: Tue 2026-09-29 14:30:00 IST" ]
    run epoch 2026-09-29T25:00
    [ "$status" -eq 2 ]
}

@test "nothing to read prints now" {
    run epoch
    [ "$status" -eq 0 ]
    [[ $output =~ ^[0-9]{10}$ ]]
    run epoch --ms
    [[ $output =~ ^[0-9]{13}$ ]]
}

@test "-v shows the date command" {
    run epoch -v "2026-09-29 14:30"
    [ "${lines[0]}" = "+ date -d '2026-09-29 14:30' +%s" ]
    [ "${lines[1]}" = "epoch: Tue 2026-09-29 14:30:00 IST" ]
}

@test "a missing date exits 3" {
    tb_without date
    run epoch 1790000000
    [ "$status" -eq 3 ]
    [[ $output == "epoch: needs date."* ]]
}
