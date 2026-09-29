#!/usr/bin/env bats
# Tests for boottime. systemd-analyze and journalctl are stubs, and a fake
# tree through TB_ROOTFS says systemd is PID 1.

load helpers

setup() {
    tb_setup
    export TZ=UTC
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    mkdir -p "$TB_ROOTFS/run/systemd/system" "$TB_ROOTFS/proc"
    echo "600.50 100.00" > "$TB_ROOTFS/proc/uptime"
    local f=$BATS_TEST_TMPDIR
    cat > "$f/time" <<'EOF'
Startup finished in 8.101s (firmware) + 2.302s (loader) + 1.804s (kernel) + 3.050s (initrd) + 7.612s (userspace) = 22.871s
graphical.target reached after 7.590s in userspace.
EOF
    cat > "$f/blame" <<'EOF'
3.402s NetworkManager-wait-online.service
 812ms plymouth-quit-wait.service
 640ms dev-nvme0n1p3.device
 402ms systemd-udev-settle.service
 210ms firewalld.service
 190ms upower.service
EOF
    tb_stub systemd-analyze "
echo \"\$*\" >> '$f/args'
case \"\$*\" in
    *time*) cat '$f/time' ;;
    *blame*) cat '$f/blame' ;;
esac"
    tb_stub journalctl "
case \"\$*\" in
    *--list-boots*)
        echo ' -2 aaaa1111 Fri 2026-09-25 09:10:02 UTC Fri 2026-09-25 23:01:40 UTC'
        echo ' -1 bbbb2222 Sat 2026-09-26 08:30:11 UTC Sun 2026-09-27 01:12:09 UTC'
        echo '  0 cccc3333 Tue 2026-09-29 09:05:40 UTC Tue 2026-09-29 12:00:00 UTC' ;;
    *MESSAGE_ID*)
        echo '{\"_BOOT_ID\":\"aaaa1111\",\"MESSAGE\":\"Startup finished in 1.8s (kernel) + 3.1s (initrd) + 7.4s (userspace) = 12.3s.\"}'
        echo '{\"_BOOT_ID\":\"bbbb2222\",\"MESSAGE\":\"Startup finished in 1.9s (kernel) + 3.0s (initrd) + 41.2s (userspace) = 46.1s.\"}'
        echo '{\"_BOOT_ID\":\"cccc3333\",\"MESSAGE\":\"Startup finished in 1.8s (kernel) + 3.0s (initrd) + 7.6s (userspace) = 12.4s.\"}' ;;
esac"
}

@test "help prints usage and exits 0" {
    run boottime --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: boottime "* ]]
}

@test "bad usage exits 2" {
    run boottime -n 0
    [ "$status" -eq 2 ]
    run boottime -n many
    [ "$status" -eq 2 ]
    run boottime firefox
    [ "$status" -eq 2 ]
    run boottime --fast
    [ "$status" -eq 2 ]
}

@test "a missing systemd-analyze exits 3" {
    tb_without systemd-analyze
    run boottime
    [ "$status" -eq 3 ]
    [[ $output == "boottime: needs systemd-analyze."* ]]
}

@test "refuses when systemd is not PID 1" {
    rmdir "$TB_ROOTFS/run/systemd/system"
    run boottime
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "boottime: systemd is not PID 1 here, so there is no boot to time." ]
    [ "${lines[1]}" = "          Inside a container? Run it on the host." ]
}

@test "shows each phase, the slowest units and a hint" {
    run boottime
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "last boot  "*", 22.9s to the desktop" ]]
    [ "${lines[1]}" = "  firmware     8.1s" ]
    [ "${lines[2]}" = "  loader       2.3s" ]
    [ "${lines[3]}" = "  kernel       1.8s" ]
    [ "${lines[4]}" = "  initrd       3.1s" ]
    [ "${lines[5]}" = "  userspace    7.6s  until graphical.target" ]
    [ "${lines[6]}" = "slowest units" ]
    [ "${lines[7]}" = "    3.4s  NetworkManager-wait-online.service" ]
    [ "${lines[11]}" = "    0.2s  firewalld.service" ]
    [ "${lines[12]}" = "hint  3.4s went to waiting for the network. See what needs it:" ]
    [ "${lines[13]}" = "      systemd-analyze critical-chain network-online.target" ]
    [ "${#lines[@]}" -eq 14 ]
}

@test "-n sets how many units, and no hint for a small top unit" {
    printf ' 900ms upower.service\n 100ms a.service\n' > "$BATS_TEST_TMPDIR/blame"
    run boottime -n 1
    [ "${lines[-1]}" = "    0.9s  upower.service" ]
}

@test "the login prompt is the goal on a server" {
    sed -i 's/^graphical/multi-user/' "$BATS_TEST_TMPDIR/time"
    run boottime
    [[ ${lines[0]} == *", 22.9s to the login prompt" ]]
}

@test "-q prints only the systemd-analyze time lines" {
    run boottime -q
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "Startup finished in 8.101s (firmware) + 2.302s (loader) + 1.804s (kernel) + 3.050s (initrd) + 7.612s (userspace) = 22.871s" ]
}

@test "options after -- go to systemd-analyze" {
    run boottime -v -- --user
    [[ $output == *"+ systemd-analyze --user time"* ]]
    grep -q -- '--user blame --no-pager' "$BATS_TEST_TMPDIR/args"
}

@test "a boot still running exits 1" {
    echo "Bootup is not yet finished (org.freedesktop.systemd1.Manager.FinishTimestampMonotonic=0)." > "$BATS_TEST_TMPDIR/time"
    run boottime
    [ "$status" -eq 1 ]
    [[ $output == *"the boot has not finished yet"* ]]
}

@test "--history lists each boot and marks a slow one" {
    run boottime --history
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "BOOT  STARTED        TOTAL  USERSPACE" ]
    [ "${lines[1]}" = "   0  Sep 29 09:05   12.4s    7.6s" ]
    [ "${lines[2]}" = "  -1  Sep 26 08:30   46.1s   41.2s  slow, see: logs -b -1" ]
    [ "${lines[3]}" = "  -2  Sep 25 09:10   12.3s    7.4s" ]
}

@test "--history with no readable boot times exits 1" {
    tb_stub journalctl 'exit 0'
    run boottime --history
    [ "$status" -eq 1 ]
    if [ "$EUID" -eq 0 ]; then
        [ "$output" = "boottime: the journal holds no boot times" ]
    else
        [[ $output == *"no boot times in the journal you can read"* ]]
    fi
}

@test "--history without journalctl exits 3" {
    tb_without journalctl
    run boottime --history
    [ "$status" -eq 3 ]
    [[ $output == "boottime: needs journalctl."* ]]
}

@test "no start time for another machine" {
    run boottime -- -M web1
    [ "${lines[0]}" = "last boot 22.9s to the desktop" ]
}
