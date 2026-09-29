#!/usr/bin/env bats
# Tests for archmount. No FUSE tool runs here: the stubs write and remove
# lines in a mount table of the test's own, which TB_TEST_MOUNTS points at.

load helpers

setup() {
    tb_setup
    export TB_TEST_MOUNTS=$BATS_TEST_TMPDIR/mounts
    export ARCHMOUNT_POLL=0.1
    : > "$TB_TEST_MOUNTS"
    mkdir -p src
    echo hello > src/a.txt
    tar -cf - src | zstd -q -o backup.tar.zst
    (cd src && zip -q ../logs.zip a.txt)
    # The tools on this machine must not answer instead of the stubs.
    tb_without fuse-archive archivemount ratarmount fusermount3 fusermount lsof
    export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
    fake_umount
}

# A FUSE tool stub that logs its arguments and adds a mount line.
fake_mount() {
    tb_stub "$1" "printf '%s\n' \"\$*\" >> \"\$BATS_TEST_TMPDIR/calls\"
printf '%s %s fuse.$1 ro 0 0\n' \"\${@: -2:1}\" \"\${@: -1}\" >> \"\$TB_TEST_MOUNTS\""
}

# fusermount3 -u DIR: drop the line, or fail when the busy flag is set.
fake_umount() {
    tb_stub fusermount3 'dir=$2
if [[ -e $BATS_TEST_TMPDIR/busy ]]; then
    echo "fusermount3: failed to unmount $dir: Device or resource busy" >&2
    exit 1
fi
awk -v d="$dir" '"'"'$2 != d'"'"' "$TB_TEST_MOUNTS" > "$TB_TEST_MOUNTS.new"
mv "$TB_TEST_MOUNTS.new" "$TB_TEST_MOUNTS"'
}

# ---------------------------------------------------------------- help and usage

@test "help prints the layout and exits 0" {
    run archmount -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: archmount [options] archive [dir] [-- fuse options]" ]
    [[ $output == *"Open an archive as a folder without unpacking."* ]]
    [[ $output == *"Needs: "* ]]
    [[ $output == *"Exit: 0 ok"* ]]
}

@test "help fits in 80 columns" {
    run archmount -h
    while IFS= read -r line; do
        [ "${#line}" -le 80 ]
    done <<<"$output"
}

@test "bad usage exits 2" {
    run archmount
    [ "$status" -eq 2 ]
    [[ $output == *"name the archive to open"* ]]
    run archmount -b -w backup.tar.zst
    [ "$status" -eq 2 ]
    [[ $output == *"-b and -w contradict each other"* ]]
    run archmount a b c
    [ "$status" -eq 2 ]
    run archmount --list backup.tar.zst
    [ "$status" -eq 2 ]
    run archmount -u
    [ "$status" -eq 2 ]
    run archmount --nope backup.tar.zst
    [ "$status" -eq 2 ]
}

@test "no FUSE tool exits 3 and names all three" {
    run archmount -b backup.tar.zst
    [ "$status" -eq 3 ]
    [[ $output == *"needs fuse-archive, archivemount or ratarmount"* ]]
    [[ $output == *"archivemount"* ]]
}

@test "a missing archive exits 1" {
    fake_mount fuse-archive
    run archmount -b nope.tar.zst
    [ "$status" -eq 1 ]
    [[ $output == *"nope.tar.zst: no such file"* ]]
}

# ---------------------------------------------------------------- mounting

@test "-b mounts beside the archive and prints the unmount line" {
    fake_mount fuse-archive
    run archmount -b backup.tar.zst
    [ "$status" -eq 0 ]
    [[ $output == *"archmount: backup.tar.zst on backup/, read-only"* ]]
    [[ $output == *"Unmount with: archmount -u backup"* ]]
    [ -d backup ]
    grep -q " $PWD/backup fuse.fuse-archive " "$TB_TEST_MOUNTS"
    grep -qx "$PWD/backup.tar.zst $PWD/backup" "$BATS_TEST_TMPDIR/calls"
}

@test "-b with a folder mounts there" {
    fake_mount fuse-archive
    mkdir mnt
    run archmount -b logs.zip mnt/logs
    [ "$status" -eq 0 ]
    [[ $output == *"Unmount with: archmount -u mnt/logs"* ]]
    grep -q " $PWD/mnt/logs " "$TB_TEST_MOUNTS"
}

@test "-q keeps only the unmount line" {
    fake_mount fuse-archive
    run archmount -q -b backup.tar.zst
    [ "$status" -eq 0 ]
    [ "$output" = "Unmount with: archmount -u backup" ]
}

@test "a taken default folder gets the next free name" {
    fake_mount fuse-archive
    mkdir backup
    echo keep > backup/k
    run archmount -b backup.tar.zst
    [ "$status" -eq 0 ]
    [[ $output == *"on backup-1/"* ]]
    [ -f backup/k ]
}

@test "a folder that is not empty exits 4" {
    fake_mount fuse-archive
    mkdir full
    echo x > full/x
    run archmount -b backup.tar.zst full
    [ "$status" -eq 4 ]
    [[ $output == *"full is not empty"* ]]
    [ ! -s "$TB_TEST_MOUNTS" ]
}

@test "a folder that is already a mount point exits 4" {
    fake_mount fuse-archive
    mkdir m
    echo "x $PWD/m fuse.other ro 0 0" > "$TB_TEST_MOUNTS"
    run archmount -b backup.tar.zst m
    [ "$status" -eq 4 ]
    [[ $output == *"already a mount point"* ]]
}

@test "archivemount is used read-only when fuse-archive is missing" {
    fake_mount archivemount
    run archmount -v -b backup.tar.zst
    [ "$status" -eq 0 ]
    [[ $output == *"+ archivemount -o readonly $PWD/backup.tar.zst $PWD/backup"* ]]
}

@test "ratarmount is the last choice" {
    fake_mount ratarmount
    run archmount -b backup.tar.zst
    [ "$status" -eq 0 ]
    grep -q "fuse.ratarmount" "$TB_TEST_MOUNTS"
}

@test "options after -- go to the tool before the archive" {
    fake_mount fuse-archive
    run archmount -v -b backup.tar.zst -- -o allow_other
    [ "$status" -eq 0 ]
    [[ $output == *"+ fuse-archive -o allow_other $PWD/backup.tar.zst $PWD/backup"* ]]
}

@test "a failed mount exits 1 and removes the folder it made" {
    tb_stub fuse-archive 'echo "fuse-archive: invalid archive" >&2; exit 1'
    run archmount -b backup.tar.zst
    [ "$status" -eq 1 ]
    [[ $output == *"fuse-archive could not mount backup.tar.zst"* ]]
    [ ! -e backup ]
}

@test "a tool that exits 0 without mounting counts as a failure" {
    tb_stub fuse-archive 'exit 0'
    run archmount -b backup.tar.zst
    [ "$status" -eq 1 ]
    [ ! -e backup ]
}

# ---------------------------------------------------------------- list and unmount

@test "--list shows the mounts and prunes stale records" {
    fake_mount fuse-archive
    archmount -q -b backup.tar.zst >/dev/null
    archmount -q -b logs.zip >/dev/null
    run archmount --list
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "FOLDER"*"TOOL"*"ARCHIVE" ]]
    [[ $output == *"$PWD/backup "*"fuse-archive"*"$PWD/backup.tar.zst"* ]]
    [[ $output == *"$PWD/logs "*"$PWD/logs.zip"* ]]
    # Unmounted behind archmount's back: the record goes.
    fusermount3 -u "$PWD/logs"
    run archmount --list
    [[ $output != *"logs.zip"* ]]
    ! grep -q logs.zip "$XDG_STATE_HOME/toolbelt/archmount.mounts"
}

@test "--list includes archive mounts made by hand" {
    echo "/data/old.tar.gz /mnt/old fuse.archivemount ro 0 0" > "$TB_TEST_MOUNTS"
    run archmount --list
    [ "$status" -eq 0 ]
    [[ $output == *"/mnt/old"*"archivemount"*"/data/old.tar.gz"* ]]
}

@test "--list with nothing mounted says so" {
    run archmount --list
    [ "$status" -eq 0 ]
    [ "$output" = "archmount: no archives are mounted" ]
}

@test "-u unmounts and removes the folder archmount made" {
    fake_mount fuse-archive
    archmount -q -b backup.tar.zst >/dev/null
    run archmount -u backup
    [ "$status" -eq 0 ]
    [ "$output" = "archmount: unmounted backup" ]
    [ ! -e backup ]
    [ ! -s "$TB_TEST_MOUNTS" ]
}

@test "-u keeps a folder the user made" {
    fake_mount fuse-archive
    mkdir mine
    archmount -q -b backup.tar.zst mine >/dev/null
    run archmount -u mine
    [ "$status" -eq 0 ]
    [ -d mine ]
}

@test "-u on a busy folder exits 1 and names the program" {
    fake_mount fuse-archive
    archmount -q -b backup.tar.zst >/dev/null
    touch "$BATS_TEST_TMPDIR/busy"
    tb_stub lsof 'printf "p48213\nfless\n" | sed "s/^f/c/"'
    run archmount -u backup
    [ "$status" -eq 1 ]
    [[ $output == *"backup is busy, used by less (pid 48213)"* ]]
    [[ $output == *"close it and run archmount -u backup again"* ]]
    [ -d backup ]
}

@test "-u on a busy folder without lsof shows the tool's error" {
    fake_mount fuse-archive
    archmount -q -b backup.tar.zst >/dev/null
    touch "$BATS_TEST_TMPDIR/busy"
    run archmount -u backup
    [ "$status" -eq 1 ]
    [[ $output == *"could not be unmounted: fusermount3: failed to unmount"* ]]
}

@test "-u on a folder that is not mounted exits 1" {
    mkdir plain
    run archmount -u plain
    [ "$status" -eq 1 ]
    [[ $output == *"plain is not mounted"* ]]
}

# ---------------------------------------------------------------- foreground

@test "-w stays until the mount goes, then cleans up" {
    fake_mount fuse-archive
    ( sleep 0.5; fusermount3 -u "$PWD/backup" ) &
    run archmount -w backup.tar.zst
    wait
    [ "$status" -eq 0 ]
    [[ $output == *"press Ctrl+C to unmount"* ]]
    [ ! -e backup ]
}

@test "-w unmounts on Ctrl+C" {
    fake_mount fuse-archive
    run timeout -s INT 1 archmount -w backup.tar.zst
    [ ! -s "$TB_TEST_MOUNTS" ]
    [ ! -e backup ]
    [[ $output == *"unmounted backup"* ]]
}

@test "in a terminal it opens a shell in the folder and unmounts after" {
    fake_mount fuse-archive
    tb_tty
    tb_stub fakeshell 'pwd > "$BATS_TEST_TMPDIR/shell-pwd"; grep -c . "$TB_TEST_MOUNTS" > "$BATS_TEST_TMPDIR/shell-mounts"'
    export SHELL=$BATS_TEST_TMPDIR/stubs/fakeshell
    run archmount backup.tar.zst
    [ "$status" -eq 0 ]
    [[ $output == *"new shell in backup/. Type exit to unmount."* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/shell-pwd")" = "$PWD/backup" ]
    [ "$(cat "$BATS_TEST_TMPDIR/shell-mounts")" = 1 ]
    [ ! -s "$TB_TEST_MOUNTS" ]
    [ ! -e backup ]
}
