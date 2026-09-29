#!/usr/bin/env bats
# Tests for logs. journalctl is a stub that prints a few JSON lines, and the
# syslog tests use tiny files in a fake tree through TB_ROOTFS.

load helpers

# One journal entry: priority, unit, identifier, message, and optionally
# the transport and a user unit.
jline() {
    local t=${T:-$(( $(date +%s) - 60 ))}000000
    printf '{"__REALTIME_TIMESTAMP":"%s","PRIORITY":"%s","_SYSTEMD_UNIT":"%s","SYSLOG_IDENTIFIER":"%s","_TRANSPORT":"%s","_SYSTEMD_USER_UNIT":"%s","MESSAGE":"%s"}\n' \
        "$t" "$1" "$2" "$3" "${5:-journal}" "${6:-}" "$4"
}

setup() {
    tb_setup
    export TZ=UTC
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    mkdir -p "$TB_ROOTFS/proc" "$TB_ROOTFS/var/log/journal/abc"
    echo "3600.12 100.00" > "$TB_ROOTFS/proc/uptime"
    : > "$TB_ROOTFS/var/log/journal/abc/system.journal"
    J=$BATS_TEST_TMPDIR/journal.json
    {
        jline 3 dnf-makecache.service dnf "Curl error (6): Couldn't resolve host name"
        jline 3 dnf-makecache.service dnf "Curl error (6): Couldn't resolve host name"
        jline 3 dnf-makecache.service dnf "Failed to download metadata"
        jline 3 "" kernel "iwlwifi 0000:03:00.0: Microcode SW error detected. Restarting." kernel
        jline 4 NetworkManager.service NetworkManager "dhcp4 (wlp3s0): request timed out"
        jline 4 user@1000.service pipewire "spa.alsa: hw:0: Broken pipe" journal pipewire.service
        jline 4 user@1000.service pipewire "spa.alsa: hw:0: Broken pipe" journal pipewire.service
        jline 4 NetworkManager.service NetworkManager "a line with \\\"quotes\\\" in it"
    } > "$J"
    tb_stub journalctl "
echo \"\$*\" >> \"$BATS_TEST_TMPDIR/args\"
case \"\$*\" in
    *--list-boots*)
        echo ' -1 3ab440c4a424 Sun 2026-09-27 10:59:48 UTC Mon 2026-09-28 21:42:08 UTC'
        echo '  0 ec65a11bcba5 Tue 2026-09-29 00:17:33 UTC Tue 2026-09-29 17:10:25 UTC' ;;
    *'-o cat'*) cat \"$BATS_TEST_TMPDIR/tail\" 2>/dev/null ;;
    *) cat \"$J\" ;;
esac"
}

@test "help prints usage and exits 0" {
    run logs --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: logs "* ]]
    [[ $output != *"-p, --priority"* ]]
}

@test "bad usage exits 2" {
    run logs --priority info
    [ "$status" -eq 2 ]
    run logs -n 0
    [ "$status" -eq 2 ]
    run logs -b last
    [ "$status" -eq 2 ]
    run logs -p err
    [ "$status" -eq 2 ]
    [[ $output == *"unknown option -p"* ]]
}

@test "a time it cannot read exits 2 with examples" {
    run logs --since yesterdy
    [ "$status" -eq 2 ]
    [[ $output == "logs: cannot read the time yesterdy. Try 2h, today, yesterday or 2026-09-28 18:00." ]]
}

@test "no journalctl and no syslog file exits 3" {
    tb_without journalctl
    run logs
    [ "$status" -eq 3 ]
    [[ $output == "logs: needs journalctl."* ]]
}

@test "groups errors and warnings by unit, most first" {
    run logs
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "this boot, since "*". 2 units with errors, 2 with warnings." ]]
    [ "${lines[1]}" = "ERRORS" ]
    [[ ${lines[2]} == "dnf-makecache            3x  last "* ]]
    [ "${lines[3]}" = "  Failed to download metadata" ]
    [[ ${lines[4]} == "kernel                   1x  last "* ]]
    [ "${lines[6]}" = "WARNINGS" ]
    [ "${lines[7]}" = 'NetworkManager           2x  a line with "quotes" in it' ]
    [ "${lines[8]}" = "pipewire (user)          2x  spa.alsa: hw:0: Broken pipe" ]
}

@test "reads this boot at warning level by default" {
    run logs -v
    [[ $output == *"+ journalctl --no-pager -q -o json --output-fields="*" -p 4 -b 0"* ]]
}

@test "--priority err shows errors only and asks journalctl for them" {
    run logs --priority err
    [ "$status" -eq 0 ]
    [[ $output == *"2 units with errors."* ]]
    [[ $output != *WARNINGS* ]]
    grep -q -- '-p 3 -b 0' "$BATS_TEST_TMPDIR/args"
}

@test "-n keeps more sample lines per unit" {
    run logs -n 2 --priority err
    [ "${lines[3]}" = "  Failed to download metadata" ]
    [ "${lines[4]}" = "  Curl error (6): Couldn't resolve host name" ]
}

@test "-g keeps only matching lines, ignoring case in lower case patterns" {
    run logs -g 'broken pipe'
    [[ $output == *"pipewire (user)"* ]]
    [[ $output != *dnf-makecache* ]]
    [[ ${lines[0]} == *"0 units with errors, 1 with warnings." ]]
}

@test "an earlier boot shows its span and whether it shut down cleanly" {
    printf 'Reached target shutdown.target - Shutdown.\nJournal stopped\n' > "$BATS_TEST_TMPDIR/tail"
    run logs -b -1 --priority err
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "boot -1, Sep 27 10:59 to Sep 28 21:42, 1 day. 2 units with errors." ]]
    [ "${lines[1]}" = "it shut down cleanly." ]
    printf 'kernel: i915 FIFO underrun\n' > "$BATS_TEST_TMPDIR/tail"
    run logs --boot=-1 --priority err
    [ "${lines[1]}" = "it did not shut down cleanly, the last entry is Sep 28 21:42:08" ]
    grep -q -- '-b -1' "$BATS_TEST_TMPDIR/args"
}

@test "units, --user, -k and options after -- reach journalctl" {
    run logs --user -k --since 2h NetworkManager -- --facility=auth
    [ "$status" -eq 0 ]
    grep -q -- '--user --no-pager' "$BATS_TEST_TMPDIR/args"
    grep -q -- '--since -2h -k --user-unit NetworkManager --facility=auth' "$BATS_TEST_TMPDIR/args"
}

@test "nothing found says so" {
    : > "$J"
    run logs --since 10m
    [ "$status" -eq 0 ]
    [[ $output == "nothing at warning or above, since "*"." ]]
}

@test "says when it can read only your own entries" {
    [ "$EUID" -ne 0 ] || skip "root can read every entry"
    rm "$TB_ROOTFS/var/log/journal/abc/system.journal"
    run logs --priority err
    [[ $output == *"you can read only your own entries"* ]]
    [[ $output == *"usermod -aG systemd-journal"* ]]
}

@test "a journalctl error exits 1 with its message" {
    tb_stub journalctl 'echo "Data from the specified boot (-9) is not available" >&2; exit 1'
    run logs -b -9
    [ "$status" -eq 1 ]
    [[ $output == *"journalctl failed, Data from the specified boot (-9) is not available"* ]]
}

@test "long samples wrap to COLUMNS" {
    jline 4 foo.service foo "one two three four five six seven eight nine ten eleven" > "$J"
    COLUMNS=50 run logs -q
    [ "${lines[1]}" = "foo                      1x  one two three four" ]
    [ "${lines[2]}" = "                             five six seven eight" ]
    [ "${lines[3]}" = "                             nine ten eleven" ]
}

@test "-f reads a syslog file, from boot or --since" {
    local today old
    today=$(date +%Y-%m-%dT%H:%M:%S)
    old=$(date -d "$(tb_ago 259200)" +%Y-%m-%dT%H:%M:%S)
    {
        echo "$old+00:00 host nginx[12]: old error, before boot"
        echo "$today+00:00 host nginx[12]: connect() failed (111: Connection refused)"
        echo "$today+00:00 host kernel: usb 1-2: warning, device not accepting address"
        echo "$today+00:00 host cron[9]: (root) CMD (true)"
    } > "$BATS_TEST_TMPDIR/app.log"
    run logs -f "$BATS_TEST_TMPDIR/app.log"
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "app.log, this boot, since "*"1 unit with errors, 1 with warnings." ]]
    [[ ${lines[2]} == "nginx                    1x  last "* ]]
    [[ $output != *"old error"* ]]
    [[ ${lines[2]} == *" 1x  "* ]]
    run logs -f "$BATS_TEST_TMPDIR/app.log" --since 5d
    [[ ${lines[2]} == "nginx                    2x  last "* ]]
    run logs -f "$BATS_TEST_TMPDIR/app.log" -b -1
    [ "$status" -eq 2 ]
}

@test "falls back to /var/log/syslog without journalctl" {
    printf '%s host sshd[5]: error: kex_exchange_identification\n' "$(date '+%b %e %H:%M:%S')" \
        > "$TB_ROOTFS/var/log/syslog"
    tb_without journalctl
    run logs --priority err
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "syslog, this boot"* ]]
    [[ ${lines[2]} == "sshd "* ]]
}

@test "-f reads nginx and Apache error logs by their level" {
    local d=$BATS_TEST_TMPDIR t
    mkdir -p "$d/nginx" "$d/apache2"
    t=$(date +%Y/%m/%d)
    {
        echo "$t 09:12:01 [error] 812#812: *5 connect() failed (111: Connection refused)"
        echo "$t 09:14:30 [warn] 812#812: *9 an upstream response is buffered"
        echo "$t 09:15:00 [notice] 812#812: signal process started"
    } > "$d/nginx/error.log"
    run logs -f "$d/nginx/error.log" --since today
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "error.log, since "*"1 unit with errors, 1 with warnings." ]]
    [ "${lines[3]}" = "  connect() failed (111: Connection refused)" ]
    [ "${lines[5]}" = "nginx                    1x  an upstream response is buffered" ]
    printf '[%s 09:12:01.123456 %s] [proxy:error] [pid 812:tid 140] AH00957: connect to 127.0.0.1:8080 failed\n' \
        "$(date '+%a %b %d')" "$(date +%Y)" > "$d/apache2/error.log"
    run logs -f "$d/apache2/error.log" --since today
    [[ ${lines[2]} == "apache2                  1x  last 09:12" ]]
    [ "${lines[3]}" = "  AH00957: connect to 127.0.0.1:8080 failed" ]
}
