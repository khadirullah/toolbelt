#!/usr/bin/env bats
# Tests for svc. systemctl, journalctl and sudo are stubs that log their
# arguments, so no real unit is touched.

load helpers

setup() {
    tb_setup
    export TB_ROOTFS=$BATS_TEST_TMPDIR/root
    mkdir -p "$TB_ROOTFS/run/systemd/system"
    export CALLS=$BATS_TEST_TMPDIR/calls
    : > "$CALLS"
    unset SSH_CONNECTION SSH_CLIENT
    cat > "$BATS_TEST_TMPDIR/stubs/systemctl" <<'SH'
#!/usr/bin/env bash
echo "systemctl $*" >> "$CALLS"
args=" $* "
user=0
[[ $args == *" --user "* ]] && user=1
last=${!#}
case $args in
    *" list-units --state=failed "*)
        if (( user )); then printf '%b' "${FAILED_USER:-}"; else printf '%b' "${FAILED:-}"; fi ;;
    *" list-unit-files "*)
        printf 'sshd.service enabled disabled\nbluetooth.service enabled enabled\ncron.service enabled enabled\n' ;;
    *" list-units --all "*)
        printf 'sshd.service loaded active running OpenSSH server daemon\n' ;;
    *" show -p LoadState --value "*)
        case $last in
            sshd.service|bluetooth.service|cron.service|syncthing.service|dnf-makecache.service) echo loaded ;;
            *) echo not-found ;;
        esac ;;
    *" show -p ActiveState --value "*) echo "${STATE:-active}" ;;
    *" show -p SubState --value "*) echo "${SUB:-running}" ;;
    *" show -p MainPID --value "*) echo 51203 ;;
    *" show -p Result "*)
        printf 'Result=exit-code\nExecMainStatus=1\nStateChangeTimestamp=Sat 2026-09-26 15:40:02 IST\n' ;;
    *" show -p Id "*)
        printf '%s\n' "Id=sshd.service" "Description=OpenSSH server daemon" "ActiveState=active" \
            "SubState=running" "ActiveEnterTimestamp=Sat 2026-09-26 09:11:04 IST" "InactiveEnterTimestamp=" \
            "UnitFileState=enabled" "UnitFilePreset=disabled" "MainPID=1" "MemoryCurrent=4404019" \
            "NRestarts=0" "FragmentPath=/usr/lib/systemd/system/sshd.service" \
            "DropInPaths=/etc/systemd/system/sshd.service.d/override.conf" "Result=success" "ExecMainStatus=0" ;;
    *" is-enabled "*) echo "${ENABLED:-enabled}" ;;
    *" start "*|*" stop "*|*" restart "*|*" enable "*|*" disable "*) exit "${ACTION_RC:-0}" ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/systemctl"
    tb_stub journalctl 'echo "journalctl $*" >> "$CALLS"
[[ $* == *"-p 3"* ]] && { echo "Curl error (6): Could not resolve host name"; exit 0; }
[[ $* == *"-o cat"* ]] && exit 0
printf "Sep 29 10:02:11 box sshd[48210]: Accepted publickey for khadir\nSep 29 10:02:11 box sshd[48210]: session opened\n"'
    tb_stub sudo 'echo "sudo $*" >> "$CALLS"; exec "$@"'
}

@test "help prints usage and exits 0" {
    run svc --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: svc [--user]" ]
}

@test "bad usage exits 2" {
    run svc restart
    [ "$status" -eq 2 ]
    [[ $output == *"restart needs a unit name"* ]]
    run svc sshd cron
    [ "$status" -eq 2 ]
    run svc sshd --since 1h
    [ "$status" -eq 2 ]
    run svc sshd -- -x
    [ "$status" -eq 2 ]
    run svc -n 0 sshd
    [ "$status" -eq 2 ]
    run svc --nope
    [ "$status" -eq 2 ]
}

@test "no systemd exits 3" {
    tb_without systemctl
    run svc
    [ "$status" -eq 3 ]
    [[ $output == "svc: needs systemctl."* ]]
}

@test "a system that did not boot with systemd exits 3" {
    rm -r "$TB_ROOTFS/run/systemd"
    run svc sshd
    [ "$status" -eq 3 ]
    [ "$output" = "svc: this system does not run systemd, so there are no units to show" ]
}

@test "no failed units exits 0" {
    run svc
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "failed, system" ]
    [ "${lines[1]}" = "  none" ]
    [ "${lines[2]}" = "failed, user" ]
    [ "${lines[-1]}" = "svc: no failed units" ]
}

@test "failed units are listed with their last error and exit 1" {
    export FAILED='dnf-makecache.service loaded failed failed dnf makecache\n'
    run svc
    [ "$status" -eq 1 ]
    [ "${lines[1]}" = "  dnf-makecache.service   Sep 26 15:40, exit code 1" ]
    [ "${lines[2]}" = "    Curl error (6): Could not resolve host name" ]
    [ "${lines[-1]}" = "svc: 1 failed unit. Look closer with: svc dnf-makecache" ]
    run svc -q
    [ "$status" -eq 1 ]
    [ "$output" = "svc: 1 failed unit. Look closer with: svc dnf-makecache" ]
}

@test "--user lists only user units" {
    export FAILED='dnf-makecache.service loaded failed failed x\n' FAILED_USER='syncthing.service loaded failed failed y\n'
    run svc --user
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "failed, user" ]
    [[ $output != *dnf-makecache* ]]
    [ "${lines[-1]}" = "svc: 1 failed unit. Look closer with: svc --user syncthing" ]
}

@test "a name shows state, unit file, drop-ins and logs" {
    run svc sshd
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "sshd.service, OpenSSH server daemon" ]
    [[ ${lines[1]} == "state     active (running) since Sep 26 09:11, "* ]]
    [ "${lines[2]}" = "enabled   yes, vendor preset disabled" ]
    [[ ${lines[3]} == "main pid  1  "* ]]
    [ "${lines[4]}" = "memory    4.2MB, restarted 0 times" ]
    [ "${lines[5]}" = "unit      /usr/lib/systemd/system/sshd.service" ]
    [ "${lines[6]}" = "drop-in   /etc/systemd/system/sshd.service.d/override.conf" ]
    [ "${lines[7]}" = "last 4 log lines" ]
    [ "${lines[8]}" = "Sep 29 10:02:11 sshd[48210]: Accepted publickey for khadir" ]
    grep -q "journalctl -u sshd.service -n 4" "$CALLS"
}

@test "an unknown name suggests the closest unit" {
    run svc bluetoth
    [ "$status" -eq 1 ]
    [ "$output" = "svc: no unit named bluetoth. Did you mean bluetooth.service?" ]
    run svc zzzzzzzz
    [ "$status" -eq 1 ]
    [[ $output == *"List them with: systemctl list-unit-files"* ]]
}

@test "restart uses sudo for a system unit and reports the new state" {
    run svc -v restart sshd
    [ "$status" -eq 0 ]
    if [ "$EUID" -ne 0 ]; then
        [[ $output == *"+ sudo systemctl restart sshd.service"* ]]
        grep -qx "sudo systemctl restart sshd.service" "$CALLS"
    fi
    grep -qx "systemctl restart sshd.service" "$CALLS"
    [ "${lines[-1]}" = "sshd.service restarted, active (running), pid 51203" ]
}

@test "--user actions run without sudo and pass options to systemctl" {
    run svc enable syncthing --user -- --now
    [ "$status" -eq 0 ]
    grep -qx "systemctl --user enable --now syncthing.service" "$CALLS"
    not grep -q "^sudo" "$CALLS"
    [ "$output" = "syncthing.service enabled, it starts at boot" ]
}

@test "logs passes --since and options after -- to journalctl" {
    run svc logs sshd --since 1h -- -o short-precise
    [ "$status" -eq 0 ]
    grep -qx "journalctl -u sshd.service --since=-1h -o short-precise" "$CALLS"
    run svc logs --user syncthing
    grep -qx "journalctl --user-unit syncthing.service -n 50" "$CALLS"
}

@test "stopping sshd over ssh asks first" {
    export SSH_CONNECTION="192.168.1.31 51522 192.168.1.24 22"
    run svc stop sshd </dev/null
    [ "$status" -eq 4 ]
    not grep -q " stop " "$CALLS"
    tb_tty
    run bash -c 'echo n | svc stop sshd'
    [ "$status" -eq 5 ]
    not grep -q " stop " "$CALLS"
    run svc -y stop sshd
    [ "$status" -eq 0 ]
    grep -qx "systemctl stop sshd.service" "$CALLS"
}

@test "a failing action exits 1" {
    export ACTION_RC=1
    run svc start sshd
    [ "$status" -eq 1 ]
    [[ $output == *"systemctl start sshd.service failed with exit 1. See why with: svc sshd"* ]]
}

@test "a unit that fails right after start exits 1" {
    export STATE=failed SUB=failed
    run svc start sshd
    [ "$status" -eq 1 ]
    [[ $output == *"sshd.service started, failed (failed)"* ]]
    [[ $output == *"failed right after it started"* ]]
}
