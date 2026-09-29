#!/usr/bin/env bats
# Tests for netcheck. ip, ping, getent, curl and timeout are stubs, so no packet leaves the machine.

load helpers

setup() {
    tb_setup
    export LINK_STATE=UP LINK_FLAGS="<BROADCAST,MULTICAST,UP,LOWER_UP>" ADDR="192.168.1.24/24"
    tb_stub ip '
case "$*" in
    "route show default"*) echo "default via 192.168.1.1 dev wlp3s0 proto dhcp metric 600" ;;
    "-brief link show wlp3s0") echo "wlp3s0 $LINK_STATE 8c:16:45:21:9b:e0 $LINK_FLAGS" ;;
    "-brief link show "*) exit 1 ;;
    "-4 addr show wlp3s0") [ -n "$ADDR" ] && echo "    inet $ADDR brd 192.168.1.255 scope global dynamic noprefixroute wlp3s0" ;;
    "-6 addr show wlp3s0 scope global") ;;
    *) exit 1 ;;
esac'
    export GW_OK=1 NET_OK=1
    tb_stub ping '
target=${@: -1}
if [ "$target" = 1.1.1.1 ]; then ok=$NET_OK; t=14.212; else ok=$GW_OK; t=2.104; fi
[ "$ok" = 1 ] || exit 1
echo "rtt min/avg/max/mdev = 1.000/$t/3.000/0.100 ms"'
    tb_stub getent 'exit 0'
    tb_stub curl 'printf "200 0.212"'
    tb_stub timeout '[[ "$*" == *dev/tcp* ]] && exit 1; shift; exec "$@"'
    tb_stub nmcli 'echo Home-5G'
}

@test "help prints usage and exits 0" {
    run netcheck --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: netcheck "* ]]
}

@test "bad usage exits 2" {
    run netcheck example.com
    [ "$status" -eq 2 ]
    [[ $output == *"got example.com. Use --host for a site"* ]]
    run netcheck -i
    [ "$status" -eq 2 ]
}

@test "a missing tool exits 3" {
    tb_without curl
    run netcheck
    [ "$status" -eq 3 ]
    [[ $output == "netcheck: needs curl."* ]]
}

@test "every step passes" {
    run netcheck
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "link      PASS  wlp3s0 up, Wi-Fi Home-5G" ]
    [ "${lines[1]}" = "address   PASS  192.168.1.24/24 from DHCP" ]
    [ "${lines[2]}" = "gateway   PASS  192.168.1.1 answers, 2.1 ms" ]
    [ "${lines[3]}" = "internet  PASS  1.1.1.1 answers, 14 ms" ]
    [[ ${lines[4]} == "dns       PASS  example.com resolves through "*" ms" ]]
    [ "${lines[5]}" = "https     PASS  https://example.com answers 200, 212 ms" ]
    [ "${lines[6]}" = "netcheck: all good. If a site still fails, the fault is on its side." ]
}

@test "-q prints only the verdict" {
    run netcheck -q
    [ "$status" -eq 0 ]
    [ "$output" = "all good" ]
}

@test "-v shows each command" {
    run netcheck -v -q
    [[ $output == *"+ ip -brief link show wlp3s0"* ]]
    [[ $output == *"+ ping -c 2 -W 2 192.168.1.1"* ]]
    [[ $output == *"+ getent ahosts example.com"* ]]
    [[ $output == *"+ curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 10 https://example.com"* ]]
    [ "${lines[-1]}" = "all good" ]
}

@test "a DNS failure skips https and says what to try" {
    tb_stub getent 'exit 2'
    run netcheck
    [ "$status" -eq 1 ]
    [[ ${lines[4]} == "dns       FAIL  example.com does not resolve through "* ]]
    [ "${lines[5]}" = "https     SKIP  needs dns" ]
    [ "${lines[6]}" = "netcheck: the internet works but DNS does not. Try another server:" ]
    run netcheck -q
    [ "$output" = "fails at dns" ]
}

@test "no link skips everything after it" {
    export LINK_STATE=DOWN LINK_FLAGS="<NO-CARRIER,BROADCAST,MULTICAST,UP>"
    run netcheck
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "link      FAIL  wlp3s0 is up but has no carrier" ]
    [ "${lines[1]}" = "address   SKIP  needs link" ]
    [ "${lines[5]}" = "https     SKIP  needs link" ]
    [[ ${lines[6]} == "netcheck: no link on wlp3s0. Connect to a Wi-Fi network:" ]]
}

@test "no address skips the rest" {
    export ADDR=""
    run netcheck
    [ "$status" -eq 1 ]
    [ "${lines[1]}" = "address   FAIL  wlp3s0 has no address" ]
    [ "${lines[2]}" = "gateway   SKIP  needs an address" ]
}

@test "a router that ignores ping is a warning when traffic passes" {
    export GW_OK=0
    run netcheck
    [ "$status" -eq 0 ]
    [ "${lines[2]}" = "gateway   WARN  192.168.1.1 does not answer ping, but traffic passes through it" ]
}

@test "a dead router is the fault when nothing passes" {
    export GW_OK=0 NET_OK=0
    tb_stub getent 'exit 2'
    run netcheck
    [ "$status" -eq 1 ]
    [ "${lines[2]}" = "gateway   FAIL  192.168.1.1 does not answer" ]
    [ "${lines[3]}" = "internet  FAIL  1.1.1.1 does not answer" ]
    [ "${lines[6]}" = "netcheck: the router at 192.168.1.1 does not answer. Restart it, or move closer to it." ]
}

@test "--host and an https failure" {
    tb_stub curl 'printf "000 0.000"; exit 7'
    run netcheck --host git.example.com/repo
    [ "$status" -eq 1 ]
    [[ ${lines[4]} == "dns       PASS  git.example.com resolves"* ]]
    [ "${lines[5]}" = "https     FAIL  https://git.example.com/repo fails, connection refused" ]
}

@test "an unknown interface fails at link" {
    run netcheck -i eth9
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "link      FAIL  no interface named eth9" ]
    [[ $output == *"there is no eth9"* ]]
}
