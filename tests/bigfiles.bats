#!/usr/bin/env bats
# Tests for bigfiles.

load helpers

setup() {
    tb_setup
    mkdir -p vms dl 'my docs'
    head -c 40K /dev/zero > vms/disk.img
    head -c 20K /dev/zero > dl/debian.iso
    head -c 8K /dev/zero > 'my docs/tax 2025.pdf'
    printf 'hi\n' > small.txt
    touch -d '10 days ago' dl/debian.iso
}

@test "help prints usage and exits 0" {
    run bigfiles --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: bigfiles "* ]]
}

@test "bad usage exits 2" {
    run bigfiles -n 0
    [ "$status" -eq 2 ]
    run bigfiles -n many
    [ "$status" -eq 2 ]
    run bigfiles -m huge
    [ "$status" -eq 2 ]
    run bigfiles -d -- -mtime 1
    [ "$status" -eq 2 ]
}

@test "a missing du exits 3 for -d" {
    tb_without du
    run bigfiles -d
    [ "$status" -eq 3 ]
    [[ $output == "bigfiles: needs du."* ]]
}

@test "lists files biggest first with size, age and path" {
    run bigfiles
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "   40KB     0s  ./vms/disk.img" ]
    [ "${lines[1]}" = "   20KB    10d  ./dl/debian.iso" ]
    [ "${lines[2]}" = "    8KB     0s  ./my docs/tax 2025.pdf" ]
    [ "${lines[4]}" = "4 files, 68KB together" ]
}

@test "-n and --min limit the list" {
    run bigfiles -n 1
    [ "${#lines[@]}" -eq 2 ]
    [[ ${lines[0]} == *disk.img ]]
    run bigfiles --min 10K
    [ "${lines[2]}" = "2 files, 60KB together" ]
    run bigfiles -m 1G .
    [ "$output" = "No files of 1GB or more." ]
}

@test "-d lists folders one level down" {
    run bigfiles -d
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == *"  ./vms" ]]
    [[ ${lines[2]} == *"  ./my docs" ]]
    [ "${lines[3]}" = "3 folders, 68KB together" ]
}

@test "-x leaves names out" {
    run bigfiles -x vms -x '*.pdf'
    [[ $output != *disk.img* ]]
    [[ $output != *tax* ]]
    [[ $output == *debian.iso* ]]
}

@test "tests after -- go to find, actions are refused" {
    run bigfiles -- -name '*.iso'
    [ "${#lines[@]}" -eq 2 ]
    [[ ${lines[0]} == *debian.iso ]]
    run bigfiles -- -delete
    [ "$status" -eq 4 ]
    [ -e vms/disk.img ]
}

@test "stays on one filesystem unless -a" {
    run bigfiles -v
    [[ ${lines[0]} == "+ find -P . -xdev '(' -path /proc -o -path /sys ')' -prune -o -type f"* ]]
    run bigfiles -v -a
    [[ ${lines[0]} != *-xdev* ]]
}

@test "suggests ncdu when it is installed" {
    tb_stub ncdu 'exit 0'
    tb_tty
    run bigfiles vms </dev/null
    [[ $output == *"To browse the tree, run: ncdu -x vms"* ]]
    run bigfiles -q vms </dev/null
    [[ $output != *ncdu* ]]
}

@test "a missing path exits 1" {
    run bigfiles nothere
    [ "$status" -eq 1 ]
}
