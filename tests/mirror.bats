#!/usr/bin/env bats
# Tests for mirror, with the real rsync on folders of a few KB.

load helpers

setup() {
    tb_setup
    mkdir -p photos/2026 usb/photos/old empty
    head -c 4K /dev/urandom > photos/2026/a.jpg
    head -c 2K /dev/urandom > photos/2026/b.jpg
    printf 'album one\n' > photos/albums.txt
    printf 'album\n' > usb/photos/albums.txt
    touch -d '1 day ago' usb/photos/albums.txt
    head -c 3K /dev/urandom > usb/photos/old/export.zip
    printf 'stale\n' > usb/photos/stale.txt
}

@test "help prints usage and exits 0" {
    run mirror --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: mirror "* ]]
}

@test "bad usage exits 2" {
    run mirror photos/
    [ "$status" -eq 2 ]
    [[ $output == *"name a source and a dest"* ]]
    run mirror a b c
    [ "$status" -eq 2 ]
    run mirror --nope photos/ usb/photos
    [ "$status" -eq 2 ]
}

@test "a missing rsync exits 3" {
    tb_without rsync
    run mirror photos/ usb/photos
    [ "$status" -eq 3 ]
    [[ $output == *"mirror: needs rsync."* ]]
}

@test "-n shows new, changed and deleted with sizes, and changes nothing" {
    run mirror -n photos/ usb/photos
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "mirror: the contents of photos/ into usb/photos/" ]
    [ "${lines[1]}" = "2 new (6KB), 1 changed (10B), 2 deleted (3KB)" ]
    [[ $output == *"  new          4KB  2026/a.jpg"* ]]
    [[ $output == *"  changed      10B  albums.txt"* ]]
    [[ $output == *"  delete       3KB  old/export.zip"* ]]
    [[ $output == *"  delete        6B  stale.txt"* ]]
    [ -e usb/photos/stale.txt ]
    [ ! -e usb/photos/2026 ]
}

@test "with a yes it copies, and old files go to the trash" {
    run mirror -y photos/ usb/photos
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} == "done in "*", 3 old files kept in $XDG_DATA_HOME/Trash/files/mirror-"* ]]
    diff -r photos usb/photos
    local kept=("$XDG_DATA_HOME"/Trash/files/mirror-*)
    [ -f "${kept[0]}/stale.txt" ]
    [ -f "${kept[0]}/old/export.zip" ]
    [ "$(cat "${kept[0]}/albums.txt")" = "album" ]
    local info=("$XDG_DATA_HOME"/Trash/info/mirror-*.trashinfo)
    grep -q '^Path=/.*/usb/photos/mirror-' "${info[0]}"
}

@test "it asks first, and a no changes nothing" {
    tb_tty
    run bash -c 'echo n | mirror photos/ usb/photos'
    [ "$status" -eq 5 ]
    [[ $output == *"Go ahead? Deleted and replaced files go to the trash in "* ]]
    [ -e usb/photos/stale.txt ]
    run bash -c 'echo y | mirror photos/ usb/photos'
    [ "$status" -eq 0 ]
    [ ! -e usb/photos/stale.txt ]
}

@test "without a terminal or --yes it refuses" {
    run mirror photos/ usb/photos </dev/null
    [ "$status" -eq 4 ]
    [ -e usb/photos/stale.txt ]
}

@test "--no-delete never deletes" {
    run mirror -y --no-delete photos/ usb/photos
    [ "$status" -eq 0 ]
    [[ $output == *", 0 deleted (0B)"* ]]
    [ -e usb/photos/stale.txt ]
    [ -e usb/photos/2026/a.jpg ]
}

@test "an empty source is refused when the dest has files" {
    run mirror -y empty/ usb/photos
    [ "$status" -eq 4 ]
    [[ $output == *"refused, empty/ is empty, so this would delete all 3 files in usb/photos"* ]]
    [ -e usb/photos/stale.txt ]
    run mirror -y --no-delete empty/ usb/photos
    [ "$status" -eq 0 ]
}

@test "a source inside the dest, or the other way round, is refused" {
    run mirror -y photos/ photos/backup
    [ "$status" -eq 4 ]
    [[ $output == *"is inside photos/"* ]]
    run mirror -y usb/photos/ usb
    [ "$status" -eq 4 ]
    run mirror -y photos/ photos
    [ "$status" -eq 4 ]
    run mirror -y photos usb
    [ "$status" -eq 0 ]
    [ ! -e photos/backup ]
}

@test "no trailing slash copies the folder itself, with a warning when names match" {
    mkdir fresh
    run mirror -y photos fresh
    [ "$status" -eq 0 ]
    [[ $output == *"the folder photos itself into fresh/, as fresh/photos/"* ]]
    [ -f fresh/photos/2026/a.jpg ]
    run mirror -n photos usb/photos
    [[ $output == *"usb/photos already ends in photos, so this makes usb/photos/photos/. Write photos/ to copy what is inside it instead"* ]]
}

@test "-x leaves paths out, and --backup-in-dest keeps old files in the dest" {
    run mirror -y -x '*.txt' --backup-in-dest photos/ usb/photos
    [ "$status" -eq 0 ]
    [ -e usb/photos/stale.txt ]
    [ "$(cat usb/photos/albums.txt)" = "album" ]
    local kept=(usb/photos/.mirror-backup/*)
    [ -f "${kept[0]}/old/export.zip" ]
    # A later run keeps the backup folder.
    run mirror -y photos/ usb/photos
    [ -d usb/photos/.mirror-backup ]
}

@test "options after -- reach rsync, and -v shows both runs" {
    run mirror -y -v photos/ usb/photos -- --checksum
    [ "$status" -eq 0 ]
    [[ $output == *"+ rsync -a --dry-run '--out-format=%i %l %n' --delete '--filter=P /.mirror-backup/' --checksum -- photos/ usb/photos"* ]]
    [[ $output == *"+ rsync -a --backup --backup-dir=$XDG_DATA_HOME/Trash/files/mirror-"*" --delete '--filter=P /.mirror-backup/' --checksum -- photos/ usb/photos"* ]]
}

@test "a second run finds nothing to change" {
    mirror -y photos/ usb/photos
    run mirror photos/ usb/photos
    [ "$status" -eq 0 ]
    [[ $output == *"Nothing to change, usb/photos already matches photos/."* ]]
}

@test "long lists stop at 20 paths per kind" {
    for i in $(seq 1 25); do printf '%s\n' "$i" > "photos/n$i.txt"; done
    run mirror -n photos/ usb/photos
    [[ $output == *"27 new"* ]]
    [[ $output == *"  ...               7 more new"* ]]
}

@test "a remote dest goes through rsync, with the backup in the dest" {
    tb_stub rsync 'echo "$*" >> "$BATS_TEST_TMPDIR/rsync.log"
[[ " $* " == *" --dry-run "* ]] && echo ">f+++++++++ 5 a.txt"
exit 0'
    run mirror -y photos/ nas:/srv/photos
    [ "$status" -eq 0 ]
    [[ $output == *"done in "*", replaced and deleted files are in nas:/srv/photos/.mirror-backup/"* ]]
    grep -q -- '--backup-dir=.mirror-backup/' "$BATS_TEST_TMPDIR/rsync.log"
    grep -q -- '-- photos/ nas:/srv/photos' "$BATS_TEST_TMPDIR/rsync.log"
}
