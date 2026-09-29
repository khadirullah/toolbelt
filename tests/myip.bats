#!/usr/bin/env bats
# Tests for myip. ip, curl, dig and nmcli are stubs, so nothing leaves the machine.

load helpers

setup() {
    tb_setup
    tb_stub ip '
case "$*" in
    "-o link show up")
        printf "%s\n" "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536" \
            "2: wlp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500" \
            "3: enp0s31f6: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500" \
            "4: virbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500" \
            "5: tailscale0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1280" \
            "6: veth1a2b@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500" ;;
    "-o addr show"|"-o -4 addr show"|"-o -6 addr show")
        {
        printf "%s\n" "1: lo    inet 127.0.0.1/8 scope host lo" \
            "2: wlp3s0    inet 192.168.1.24/24 brd 192.168.1.255 scope global dynamic wlp3s0" \
            "2: wlp3s0    inet6 fe80::6c3d:9a1f:4b20:e17c/64 scope link" \
            "4: virbr0    inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0" \
            "5: tailscale0    inet 100.101.7.52/32 scope global tailscale0"
        } | case "$*" in
            *-4*) grep -v inet6 ;;
            *-6*) grep inet6 ;;
            *) cat ;;
        esac ;;
    "route show default") echo "default via 192.168.1.1 dev wlp3s0 proto dhcp src 192.168.1.24 metric 600" ;;
    "-6 route show default") ;;
    "route get 1.1.1.1") echo "1.1.1.1 via 192.168.1.1 dev wlp3s0 src 192.168.1.24 uid 1000" ;;
    *) exit 1 ;;
esac'
    tb_stub nmcli 'echo Home-5G'
    tb_stub curl 'echo "$*" > "$BATS_TEST_TMPDIR/curl.args"; echo 203.0.113.47'
    tb_stub dig 'echo 198.51.100.9'
    tb_stub resolvectl 'echo "Link 2 (wlp3s0): 192.168.1.1"'
}

@test "help prints usage and exits 0" {
    run myip --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: myip "* ]]
}

@test "bad usage exits 2" {
    run myip eth0
    [ "$status" -eq 2 ]
    run myip --local --public
    [ "$status" -eq 2 ]
    [[ $output == *"--local and --public cannot go together"* ]]
    run myip --nope
    [ "$status" -eq 2 ]
}

@test "a missing ip exits 3" {
    tb_without ip
    run myip
    [ "$status" -eq 3 ]
    [[ $output == "myip: needs ip."* ]]
}

@test "--public with neither curl nor dig exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/curl" "$BATS_TEST_TMPDIR/stubs/dig"
    tb_without curl dig
    run myip --public
    [ "$status" -eq 3 ]
    [[ $output == "myip: needs curl."* ]]
}

@test "every interface that is up, with what it is, then gateway, dns and public" {
    run myip
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "wlp3s0      192.168.1.24/24       Wi-Fi Home-5G" ]
    [ "${lines[1]}" = "            fe80::6c3d:9a1f:4b20:e17c/64" ]
    [ "${lines[2]}" = "enp0s31f6   no address            no cable" ]
    [ "${lines[3]}" = "virbr0      192.168.122.1/24      libvirt bridge" ]
    [ "${lines[4]}" = "tailscale0  100.101.7.52/32       VPN" ]
    [ "${lines[5]}" = "gateway     192.168.1.1 on wlp3s0" ]
    [[ ${lines[6]} == "dns         "* ]]
    [ "${lines[7]}" = "public      203.0.113.47" ]
    [[ $output != *lo* ]]
    [[ $output != *veth* ]]
}

@test "--local never calls curl" {
    run myip --local
    [ "$status" -eq 0 ]
    [[ $output != *public* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.args" ]
}

@test "-q prints the address of the default route only" {
    run myip -q
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.1.24" ]
}

@test "-4 leaves out IPv6 addresses" {
    run myip -4 --local
    [[ $output != *fe80* ]]
    [[ $output == *"192.168.1.24/24"* ]]
}

@test "--public prints only the public IP, and -v shows the curl command" {
    run myip -v --public
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "+ curl -s --max-time 5 https://ifconfig.me" ]
    [ "${lines[1]}" = "203.0.113.47" ]
}

@test "pass-through options go to curl" {
    run myip --public -- --interface tailscale0
    [ "$(cat "$BATS_TEST_TMPDIR/curl.args")" = "-s --max-time 5 --interface tailscale0 https://ifconfig.me" ]
}

@test "without an answer from curl it tries dig" {
    tb_stub curl 'exit 28'
    run myip --public
    [ "$status" -eq 0 ]
    [ "$output" = "198.51.100.9" ]
}

@test "no answer at all exits 1 with a pointer to netcheck" {
    tb_stub curl 'echo "<html>error</html>"'
    tb_stub dig 'exit 9'
    run myip --public
    [ "$status" -eq 1 ]
    [ "$output" = "myip: no answer from ifconfig.me in 5s. Check the link with: netcheck" ]
    run myip
    [ "$status" -eq 1 ]
    [[ $output == *"gateway     192.168.1.1 on wlp3s0"* ]]
}
