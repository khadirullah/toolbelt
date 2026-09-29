#!/usr/bin/env bats
# Tests for temps. A tiny fake sysfs through TB_ROOTFS holds the sensors,
# and sensors itself is a stub.

load helpers

# One hwmon folder: hwN name, then file=value pairs.
hwmon() {
    local d=$TB_ROOTFS/sys/class/hwmon/$1 kv
    mkdir -p "$d"
    echo "$2" > "$d/name"
    shift 2
    for kv in "$@"; do echo "${kv#*=}" > "$d/${kv%%=*}"; done
}

setup() {
    tb_setup
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    hwmon hwmon0 acpitz temp1_input=45000 temp1_crit=120000
    hwmon hwmon1 nvme temp1_input=38850 temp1_label=Composite temp1_max=81850 \
        temp2_input=38850 temp2_label="Sensor 1"
    mkdir -p "$TB_ROOTFS/sys/class/hwmon/hwmon1/device/nvme0n1"
    hwmon hwmon2 coretemp temp1_input=71000 temp1_label="Package id 0" temp1_max=100000 \
        temp2_input=69000 temp2_label="Core 0" temp2_max=100000 \
        temp3_input=68000 temp3_label="Core 1" temp3_max=100000
    hwmon hwmon3 thinkpad fan1_input=3810
    tb_stub sensors 'echo "sensors $*"'
}

@test "help prints usage and exits 0" {
    run temps --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: temps "* ]]
}

@test "bad usage exits 2" {
    run temps cpu
    [ "$status" -eq 2 ]
    run temps -w 0
    [ "$status" -eq 2 ]
    run temps --hot
    [ "$status" -eq 2 ]
}

@test "options after -- need sensors, exit 3 without it" {
    tb_without sensors
    run temps -- -f
    [ "$status" -eq 3 ]
    [[ $output == "temps: needs sensors."* ]]
}

@test "options after -- run sensors with them" {
    run temps -- -f
    [ "$status" -eq 0 ]
    [ "$output" = "sensors -f" ]
}

@test "one row per part, cores on one row, the drive by name" {
    run temps
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "board    acpitz       45 C  high 120 C" ]
    [ "${lines[1]}" = "nvme     nvme0n1      39 C  high 82 C" ]
    [ "${lines[2]}" = "cpu      package      71 C  high 100 C" ]
    [ "${lines[3]}" = "cpu      cores        69 C  68 C  high 100 C" ]
    [ "${lines[4]}" = "fan      fan1         3,810 rpm" ]
    [ "${#lines[@]}" -eq 5 ]
}

@test "a reading near its high mark says hot" {
    echo 97000 > "$TB_ROOTFS/sys/class/hwmon/hwmon2/temp1_input"
    run temps
    [ "${lines[2]}" = "cpu      package      97 C  high 100 C  hot" ]
}

@test "-q prints the hottest CPU reading" {
    run temps -q
    [ "$status" -eq 0 ]
    [ "$output" = "cpu 71 C" ]
}

@test "-a lists every raw sensor with its driver and label" {
    run temps -a
    [ "${lines[0]}" = "SENSOR                 DRIVER       LABEL                VALUE  HIGH" ]
    [[ $output == *"hwmon1/temp2_input     nvme         Sensor 1              39 C"* ]]
    [[ $output == *"hwmon2/temp1_input     coretemp     Package id 0          71 C  100 C"* ]]
    [[ $output == *"hwmon3/fan1_input      thinkpad     -                3,810 rpm"* ]]
}

@test "thermal zones are the fallback with no hwmon" {
    rm -rf "$TB_ROOTFS/sys/class/hwmon"
    local z=$TB_ROOTFS/sys/class/thermal/thermal_zone0
    mkdir -p "$z"
    echo cpu-thermal > "$z/type"
    echo 52300 > "$z/temp"
    echo critical > "$z/trip_point_0_type"
    echo 90000 > "$z/trip_point_0_temp"
    run temps
    [ "$status" -eq 0 ]
    [ "$output" = "cpu      cpu-thermal  52 C  high 90 C" ]
}

@test "no sensors at all exits 1 and says why" {
    rm -rf "$TB_ROOTFS/sys"
    run temps
    [ "$status" -eq 1 ]
    [ "$output" = "temps: no sensors found. Virtual machines usually have none." ]
}

@test "-w refreshes a NOW MIN MAX table and sums up when stopped" {
    local out=$BATS_TEST_TMPDIR/watch pid st=0
    temps -w 0.2 >"$out" 2>&1 &
    pid=$!
    sleep 1
    kill -TERM "$pid"
    wait "$pid" || st=$?
    [ "$st" -eq 143 ]
    run cat "$out"
    [ "${lines[0]}" = "Ctrl+C stops it." ]
    [[ $output == *"                       NOW       MIN       MAX"* ]]
    [[ $output == *"cpu package           71 C      71 C      71 C"* ]]
    [[ $output == *"fan fan1         3,810 rpm 3,810 rpm 3,810 rpm"* ]]
    [ "${lines[-1]}" = "Nothing got hot. The most was 71 C, cpu package." ]
}
