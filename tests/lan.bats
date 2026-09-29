#!/usr/bin/env bats
# Tests for lan. Nothing is scanned: ip, sudo, arp-scan, nmap, getent and
# avahi-resolve are all stubs.

load helpers

setup() {
    tb_setup
    tb_stub sudo 'echo "$*" >> "$BATS_TEST_TMPDIR/sudo.args"; exec "$@"'
    tb_stub hostname 'echo km-laptop'
    tb_stub ip '
case "$*" in
    "route show default") echo "default via 192.168.1.1 dev wlp3s0 proto dhcp metric 600" ;;
    "link show wlp3s0") echo "3: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500" ;;
    "-o link show wlp3s0") echo "3: wlp3s0: <BROADCAST,UP> mtu 1500 link/ether 8c:16:45:21:9b:e0 brd ff:ff:ff:ff:ff:ff" ;;
    "-o -4 addr show dev wlp3s0") echo "3: wlp3s0    inet ${LAN_ADDR:-192.168.1.24/24} brd 192.168.1.255 scope global wlp3s0" ;;
    "link show tun0") echo "9: tun0: <POINTOPOINT,UP> mtu 1500" ;;
    "-o link show tun0") echo "9: tun0: <POINTOPOINT,UP> mtu 1500 link/none" ;;
    *) exit 1 ;;
esac'
    tb_stub arp-scan '
echo "$*" > "$BATS_TEST_TMPDIR/arp-scan.args"
printf "192.168.1.1\ta4:91:b1:3e:07:c2\tTechnicolor CH USA Inc.\n"
printf "192.168.1.52\t00:11:32:a8:4c:19\tSynology Incorporated\n"
printf "192.168.1.31\tf2:3a:9c:44:10:7d\t(Unknown: locally administered)\n"
[[ -f "$BATS_TEST_TMPDIR/newdev" ]] && printf "192.168.1.140\t24:0a:c4:7b:31:d2\tEspressif Inc.\n"
printf "192.168.1.52\t00:11:32:a8:4c:19\tSynology Incorporated (DUP: 2)\n"'
    tb_stub getent '
case "$2" in
    192.168.1.1) echo "192.168.1.1     router.lan" ;;
    192.168.1.52) echo "192.168.1.52    nas.lan" ;;
    nas.lan) echo "192.168.1.52    STREAM nas.lan" ;;
    *) exit 2 ;;
esac'
    tb_stub avahi-resolve '[[ $2 == 192.168.1.31 ]] && printf "192.168.1.31\tPixel-8.local\n"; exit 0'
}

@test "help prints usage and exits 0" {
    run lan --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: lan "* ]]
}

@test "bad usage exits 2" {
    run lan somehost
    [ "$status" -eq 2 ]
    run lan -P
    [ "$status" -eq 2 ]
    run lan --new -P nas.lan
    [ "$status" -eq 2 ]
}

@test "missing arp-scan and nmap exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/arp-scan"
    tb_without arp-scan nmap
    run lan
    [ "$status" -eq 3 ]
    [[ $output == "lan: needs arp-scan."* ]]
}

@test "lists every device with vendor and name" {
    run lan
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "192.168.1.0/24 on wlp3s0, arp-scan, 256 addresses in 0.0s" ]
    [ "${lines[1]}" = "IP             MAC                VENDOR         NAME" ]
    [ "${lines[2]}" = "192.168.1.1    a4:91:b1:3e:07:c2  Technicolor    router.lan" ]
    [ "${lines[3]}" = "192.168.1.24   8c:16:45:21:9b:e0  -              km-laptop, this one" ]
    [ "${lines[4]}" = "192.168.1.31   f2:3a:9c:44:10:7d  private MAC    Pixel-8.local" ]
    [ "${lines[5]}" = "192.168.1.52   00:11:32:a8:4c:19  Synology       nas.lan" ]
    [ "${lines[6]}" = "4 devices" ]
    [ "$(cat "$BATS_TEST_TMPDIR/arp-scan.args")" = "-I wlp3s0 --localnet --plain" ]
}

@test "--new lists only devices not seen before" {
    run lan --new
    [ "${lines[0]}" = "no earlier scan to compare with, so every device is new" ]
    run lan --new
    [[ ${lines[0]} == "nothing new since the last scan on "* ]]
    touch "$BATS_TEST_TMPDIR/newdev"
    run lan --new
    [[ ${lines[0]} == "1 new since the last scan on "* ]]
    [ "${lines[1]}" = "192.168.1.140  24:0a:c4:7b:31:d2  Espressif      -" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "falls back to nmap when arp-scan is missing" {
    rm "$BATS_TEST_TMPDIR/stubs/arp-scan"
    tb_stub nmap '
echo "$*" > "$BATS_TEST_TMPDIR/nmap.args"
printf "Nmap scan report for 192.168.1.1\nHost is up.\nMAC Address: A4:91:B1:3E:07:C2 (Technicolor CH USA Inc.)\n"
printf "Nmap scan report for 192.168.1.24\nHost is up.\n"'
    tb_without arp-scan
    run lan -q
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "192.168.1.1    a4:91:b1:3e:07:c2  Technicolor    router.lan" ]
    [ "${lines[1]}" = "192.168.1.24   8c:16:45:21:9b:e0  -              km-laptop, this one" ]
    [ "$(cat "$BATS_TEST_TMPDIR/nmap.args")" = "-sn -n -e wlp3s0 192.168.1.0/24" ]
}

@test "a big subnet needs a yes" {
    export LAN_ADDR=10.0.3.7/16
    run lan < /dev/null
    [ "$status" -eq 4 ]
    [[ $output == *"10.0.0.0/16 has 65,536 addresses"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/arp-scan.args" ]
    run lan -y -q
    [ "$status" -eq 0 ]
}

@test "an interface with no MAC exits 1" {
    run lan -i tun0
    [ "$status" -eq 1 ]
    [[ $output == *"tun0 has no MAC address"* ]]
    run lan -i eth9
    [ "$status" -eq 1 ]
    [[ $output == *"no interface named eth9"* ]]
}

@test "-P scans the ports of one device through sudo" {
    tb_stub nmap '
echo "$*" > "$BATS_TEST_TMPDIR/nmap.args"
cat <<X
Nmap scan report for nas.lan (192.168.1.52)
Host is up (0.00040s latency).
Not shown: 998 closed tcp ports (reset)
PORT     STATE SERVICE
22/tcp   open  ssh
5000/tcp open  upnp
MAC Address: 00:11:32:A8:4C:19 (Synology Incorporated)

Nmap done: 1 IP address (1 host up) scanned in 3.40 seconds
X'
    run lan -v -P nas.lan -- -sV
    [ "$status" -eq 0 ]
    local sudo="sudo "
    [ "$EUID" -ne 0 ] || sudo=""
    [ "${lines[0]}" = "+ ${sudo}nmap -sS --top-ports 1000 -T4 -sV 192.168.1.52" ]
    [ "${lines[1]}" = "nas.lan  192.168.1.52  Synology" ]
    [ "${lines[2]}" = "22/tcp    ssh" ]
    [ "${lines[3]}" = "5000/tcp  upnp" ]
    [ "${lines[4]}" = "2 open, 998 closed, 3.4s" ]
}

@test "-P on a host that is down exits 1" {
    tb_stub nmap 'echo "Note: Host seems down. If it is really up, but blocking our ping probes, try -Pn"'
    run lan -P 192.168.1.99
    [ "$status" -eq 1 ]
    [[ $output == *"192.168.1.99 (192.168.1.99) does not answer"* ]]
    run lan -P nowhere.lan
    [ "$status" -eq 1 ]
    [[ $output == *"cannot resolve nowhere.lan"* ]]
}

@test "-P without nmap exits 3" {
    tb_without nmap
    run lan -P nas.lan
    [ "$status" -eq 3 ]
    [[ $output == "lan: needs nmap."* ]]
}
