#!/usr/bin/env bats
# Tests for autounpack. systemctl, inotifywait and unpack are stubs, so no
# real service is ever enabled and no real watch runs.

load helpers

setup() {
    tb_setup
    export AUTOUNPACK_SETTLE=0
    mkdir -p "$HOME/Downloads"
    CALLS=$BATS_TEST_TMPDIR/calls
    UNIT=$XDG_CONFIG_HOME/systemd/user/autounpack.service
    LOG=$XDG_STATE_HOME/toolbelt/autounpack.log
    # systemctl logs its arguments. is-active answers from a flag file.
    tb_stub systemctl 'echo "systemctl $*" >> "$BATS_TEST_TMPDIR/calls"
case "$*" in
    "--user show-environment") [[ -e $BATS_TEST_TMPDIR/no-session ]] && exit 1; echo PATH=/usr/bin ;;
    "--user is-active autounpack.service") cat "$BATS_TEST_TMPDIR/state" 2>/dev/null || echo inactive ;;
esac
exit 0'
    # inotifywait prints the events listed in a file, then ends the watch.
    tb_stub inotifywait 'cat "$BATS_TEST_TMPDIR/events" 2>/dev/null'
    # unpack logs its folder and arguments. Names with "refuse" or "broken"
    # fail the way the real one does.
    tb_stub unpack 'echo "$PWD: $*" >> "$BATS_TEST_TMPDIR/unpacks"
name=${!#}; name=${name#./}
case $name in
    *refuse*) echo "unpack: ${name%%.*}/ already exists. Pass -y to write ${name%%.*}-1/" >&2; exit 4 ;;
    *unsafe*) echo "unpack: $name: ../evil.txt escapes the target folder" >&2
              echo "unpack: refused, 1 unsafe path. Nothing was written." >&2; exit 4 ;;
    *full*) echo "unpack: $name needs 2.0 GB and the disk has 1.1 GB free" >&2
            echo "unpack: refused. Use -o to unpack onto a disk with more room." >&2; exit 4 ;;
    *broken*) echo "unpack: $name is damaged, 7z says: Data Error" >&2; exit 1 ;;
esac
echo "$name -> ${name%%.*}/ (3 files, 12KB, 0.1s)"'
}

# Queue inotify events for files in a folder.
events() {
    local dir=$1 f
    shift
    for f in "$@"; do printf '%s/%s\n' "$dir" "$f"; done >> "$BATS_TEST_TMPDIR/events"
}

# ---------------------------------------------------------------- help and usage

@test "help prints the layout and exits 0" {
    run autounpack -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: autounpack [status]" ]
    [[ $output == *"Unpack archives as they land in ~/Downloads."* ]]
    [[ $output == *"Needs: "* ]]
    [[ $output == *"Exit: 0 ok"* ]]
}

@test "help fits in 80 columns" {
    run autounpack -h
    while IFS= read -r line; do
        [ "${#line}" -le 80 ]
    done <<<"$output"
}

@test "bad usage exits 2" {
    run autounpack start
    [ "$status" -eq 2 ]
    [[ $output == *"unknown command start"* ]]
    run autounpack enable a b
    [ "$status" -eq 2 ]
    run autounpack run
    [ "$status" -eq 2 ]
    run autounpack status x
    [ "$status" -eq 2 ]
    run autounpack -n many log
    [ "$status" -eq 2 ]
    run autounpack --nope
    [ "$status" -eq 2 ]
    [ ! -e "$CALLS" ]
}

@test "enable refuses --rm for unpack with exit 2" {
    run autounpack enable -- --rm
    [ "$status" -eq 2 ]
    [[ $output == *"autounpack never deletes archives"* ]]
    [ ! -e "$UNIT" ]
    not grep -q " enable" "$CALLS"
}

@test "run refuses --rm too" {
    run autounpack run "$HOME/Downloads" -- --rm
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------- missing pieces

@test "no systemctl exits 3" {
    tb_without systemctl
    run autounpack enable
    [ "$status" -eq 3 ]
    [[ $output == *"needs a systemd user session, this machine runs"* ]]
    [ ! -e "$UNIT" ]
}

@test "no user session exits 3 with the linger hint" {
    touch "$BATS_TEST_TMPDIR/no-session"
    run autounpack enable
    [ "$status" -eq 3 ]
    [[ $output == *"systemctl --user cannot reach one"* ]]
    [[ $output == *"loginctl enable-linger $(id -un)"* ]]
    # Containers, cron and system services often run without USER set.
    run env -u USER autounpack enable
    [ "$status" -eq 3 ]
    [[ $output == *"loginctl enable-linger $(id -un)"* ]]
    [ ! -e "$UNIT" ]
}

@test "no inotifywait exits 3 with an install line" {
    tb_without inotifywait
    run autounpack enable
    [ "$status" -eq 3 ]
    [[ $output == *"inotifywait"* ]]
    [[ $output == *"inotify-tools"* ]]
}

@test "a folder that does not exist exits 1" {
    run autounpack enable "$HOME/Inbox"
    [ "$status" -eq 1 ]
    [[ $output == *"~/Inbox does not exist"* ]]
    [ ! -e "$UNIT" ]
}

# ---------------------------------------------------------------- enable, status, disable

@test "enable writes the unit and starts it" {
    run autounpack enable
    [ "$status" -eq 0 ]
    [[ $output == *"enabled autounpack.service for your user"* ]]
    [[ $output == *"watching ~/Downloads. Archives stay after unpacking."* ]]
    [ -f "$UNIT" ]
    grep -qx "# autounpack-dir: $HOME/Downloads" "$UNIT"
    grep -qx "ExecStart=\"$TB_REPO/bin/autounpack\" run \"$HOME/Downloads\"" "$UNIT"
    grep -qx "WantedBy=default.target" "$UNIT"
    grep -qx "systemctl --user daemon-reload" "$CALLS"
    grep -qx "systemctl --user enable autounpack.service" "$CALLS"
    grep -qx "systemctl --user restart autounpack.service" "$CALLS"
}

@test "enable with a folder and unpack options" {
    mkdir -p "$HOME/My Inbox"
    run autounpack enable "$HOME/My Inbox" -- -d '100%'
    [ "$status" -eq 0 ]
    grep -qx "# autounpack-options: -d 100%" "$UNIT"
    grep -qx "ExecStart=\"$TB_REPO/bin/autounpack\" run \"$HOME/My Inbox\" -- \"-d\" \"100%%\"" "$UNIT"
}

@test "enable follows XDG_DOWNLOAD_DIR from user-dirs.dirs" {
    mkdir -p "$HOME/Stuff" "$XDG_CONFIG_HOME"
    echo 'XDG_DOWNLOAD_DIR="$HOME/Stuff"' > "$XDG_CONFIG_HOME/user-dirs.dirs"
    run autounpack enable
    [ "$status" -eq 0 ]
    [[ $output == *"watching ~/Stuff"* ]]
}

@test "-v shows each systemctl call" {
    run autounpack -v enable
    [ "$status" -eq 0 ]
    [[ $output == *"+ systemctl --user enable autounpack.service"* ]]
}

@test "status says off when there is no unit" {
    run autounpack
    [ "$status" -eq 0 ]
    [ "$output" = "autounpack: off" ]
}

@test "status shows the folder, the options and the last run" {
    autounpack -q enable -- -d
    echo active > "$BATS_TEST_TMPDIR/state"
    mkdir -p "$(dirname "$LOG")"
    echo "2026-09-12 14:03  chart-1.5.tgz  -> chart-1.5/ (14 files)" > "$LOG"
    run autounpack status
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "autounpack: on, watching ~/Downloads" ]
    [ "${lines[1]}" = "autounpack: unpack options: -d" ]
    [ "${lines[2]}" = "autounpack: last run 2026-09-12 14:03, chart-1.5.tgz" ]
}

@test "status reports a unit whose service is not running" {
    autounpack -q enable
    echo failed > "$BATS_TEST_TMPDIR/state"
    run autounpack status
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "autounpack: enabled for ~/Downloads, but the service is failed."* ]]
}

@test "disable stops the service and removes the unit" {
    autounpack -q enable
    run autounpack disable
    [ "$status" -eq 0 ]
    [ "$output" = "autounpack: off. Archives already unpacked stay where they are." ]
    [ ! -e "$UNIT" ]
    grep -qx "systemctl --user disable --now autounpack.service" "$CALLS"
}

@test "disable when off says so and calls nothing" {
    run autounpack disable
    [ "$status" -eq 0 ]
    [ "$output" = "autounpack: already off" ]
    [ ! -e "$CALLS" ]
}

# ---------------------------------------------------------------- the watcher

@test "run unpacks each archive with -k in its folder and logs it" {
    d=$HOME/Downloads
    echo x > "$d/chart.tgz"
    events "$d" chart.tgz
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    grep -qx "$d: -k ./chart.tgz" "$BATS_TEST_TMPDIR/unpacks"
    grep -q "  chart.tgz  -> chart/ (3 files, 12KB, 0.1s)$" "$LOG"
    [ -f "$d/chart.tgz" ]
}

@test "run passes the options after --" {
    d=$HOME/Downloads
    echo x > "$d/a.zip"
    events "$d" a.zip
    run autounpack run "$d" -- -d
    [ "$status" -eq 0 ]
    grep -qx "$d: -k -d ./a.zip" "$BATS_TEST_TMPDIR/unpacks"
}

@test "run skips partial downloads, later parts and other files" {
    d=$HOME/Downloads
    for f in a.zip.part b.tgz.crdownload .hidden.zip notes.txt set.part2.rar set.002 set.r00; do
        echo x > "$d/$f"
    done
    events "$d" a.zip.part b.tgz.crdownload .hidden.zip notes.txt set.part2.rar set.002 set.r00
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/unpacks" ]
}

@test "run takes the first part of a set" {
    d=$HOME/Downloads
    echo x > "$d/set.part1.rar"
    echo x > "$d/big.7z.001"
    events "$d" set.part1.rar big.7z.001
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    [ "$(grep -c . "$BATS_TEST_TMPDIR/unpacks")" -eq 2 ]
}

@test "run unpacks a file once when two events arrive" {
    d=$HOME/Downloads
    echo x > "$d/a.zip"
    events "$d" a.zip a.zip
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    [ "$(grep -c . "$BATS_TEST_TMPDIR/unpacks")" -eq 1 ]
}

@test "run ignores a file that is gone" {
    d=$HOME/Downloads
    events "$d" gone.zip
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/unpacks" ]
    [ ! -s "$LOG" ]
}

@test "run logs refused and failed archives and keeps going" {
    d=$HOME/Downloads
    echo x > "$d/refuse.zip"
    echo x > "$d/broken.7z"
    echo x > "$d/good.tgz"
    events "$d" refuse.zip broken.7z good.tgz
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    grep -q "  refuse.zip  refused, refuse/ already exists. Pass -y to write refuse-1/$" "$LOG"
    grep -q "  broken.7z  failed, broken.7z is damaged, 7z says: Data Error$" "$LOG"
    grep -q "  good.tgz  -> good/" "$LOG"
}

@test "run on a folder that does not exist exits 1" {
    run autounpack run "$HOME/nope"
    [ "$status" -eq 1 ]
}

@test "log shows the last lines, -n picks how many" {
    run autounpack log
    [ "$status" -eq 0 ]
    [ "$output" = "autounpack: nothing unpacked yet" ]
    mkdir -p "$(dirname "$LOG")"
    for i in $(seq 1 30); do echo "2026-09-12 14:03  f$i.zip  -> f$i/" >> "$LOG"; done
    run autounpack log
    [ "${#lines[@]}" -eq 20 ]
    [[ ${lines[19]} == *"f30.zip"* ]]
    run autounpack -n 3 log
    [ "${#lines[@]}" -eq 3 ]
    [[ ${lines[0]} == *"f28.zip"* ]]
}

@test "run logs one refused, not two" {
    d=$HOME/Downloads
    echo x > "$d/unsafe.tar"
    echo x > "$d/full.zip"
    events "$d" unsafe.tar full.zip
    run autounpack run "$d"
    [ "$status" -eq 0 ]
    grep -q "  unsafe.tar  refused, 1 unsafe path. Nothing was written.$" "$LOG"
    grep -q "  full.zip  refused, full.zip needs 2.0 GB and the disk has 1.1 GB free. Use -o to unpack onto a disk with more room.$" "$LOG"
}
