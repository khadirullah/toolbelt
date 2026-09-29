#!/usr/bin/env bats
# Tests for speed. No real test runs: curl, ip, nmcli, iw, librespeed-cli and
# speedtest are stubs, and the upload stream is 250 KB of zeros into a stub.

load helpers

setup() {
    tb_setup
    tb_stub ip 'echo "default via 192.168.1.1 dev wlp3s0 proto dhcp metric 600"'
    tb_stub nmcli '
case "$*" in
    "-t -g GENERAL.METERED device show wlp3s0") echo "${SPEED_METERED:-no}" ;;
    "-t -g GENERAL.CONNECTION device show wlp3s0") echo "Pixel-8 hotspot" ;;
esac'
    tb_stub iw 'printf "Connected to 11:22:33:44:55:66 (on wlp3s0)\n\tSSID: Home-5G\n\tfreq: 5180\n\tsignal: -61 dBm\n"'
    # Each stream reports its bytes and seconds. Ping rounds give 18, 21,
    # 18, 21 and 18 ms, so ping is 18 and jitter 3.
    tb_stub curl '
echo "$*" >> "$BATS_TEST_TMPDIR/curl.args"
url="${@: -1}"
case $url in
    */cdn-cgi/trace)
        n=$(cat "$BATS_TEST_TMPDIR/n" 2>/dev/null || echo 0); echo $((n + 1)) > "$BATS_TEST_TMPDIR/n"
        printf "fl=1\ncolo=MAA\n"
        if (( n % 2 )); then printf "\nrtt=0.033 0.012\n"; else printf "\nrtt=0.030 0.012\n"; fi ;;
    *__down*)
        b=${url##*bytes=}
        echo "$b 8.48" ;;
    */__up)
        b=$(wc -c)
        echo "$b 19.1" ;;
esac'
}

@test "help prints usage and exits 0" {
    run speed --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: speed "* ]]
}

@test "bad usage exits 2" {
    run speed -d -u
    [ "$status" -eq 2 ]
    run speed -s 0
    [ "$status" -eq 2 ]
    run speed -s lots
    [ "$status" -eq 2 ]
    run speed now
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/curl.args" ]
}

@test "a missing curl exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/curl"
    tb_without curl librespeed-cli speedtest
    run speed
    [ "$status" -eq 3 ]
    [[ $output == "speed: needs curl."* ]]
}

@test "curl against Cloudflare, both ways" {
    run speed -s 1
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "server    Cloudflare MAA, ping 18 ms, jitter 3 ms" ]
    [ "${lines[1]}" = "download    0.9 Mbit/s  ████████████████████" ]
    [ "${lines[2]}" = "upload      0.4 Mbit/s  █████████" ]
    [[ ${lines[3]} == "used      1.0 MB down, 1.0 MB up in "* ]]
    [ "${lines[4]}" = "wifi      Home-5G, 5 GHz, signal -61 dBm" ]
    [ "$(grep -c '__down?bytes=250000$' "$BATS_TEST_TMPDIR/curl.args")" -eq 4 ]
    [ "$(grep -c -- '-X POST .* -T - https://speed.cloudflare.com/__up$' "$BATS_TEST_TMPDIR/curl.args")" -eq 4 ]
}

@test "-d downloads only, and -q prints only numbers" {
    run speed -d -s 1
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "download  0.9 Mbit/s, 1.0 MB in 8.5s" ]
    ! grep -q __up "$BATS_TEST_TMPDIR/curl.args"
    run speed -q -s 1
    [ "$output" = "0.9 0.4" ]
    run speed -q -u -s 1
    [ "$output" = "0.4" ]
}

@test "a metered connection asks first" {
    export SPEED_METERED="yes (guessed)"
    run speed -s 1 < /dev/null
    [ "$status" -eq 4 ]
    [ "${lines[0]}" = "speed: Pixel-8 hotspot is a metered connection, and the test" ]
    [ ! -e "$BATS_TEST_TMPDIR/curl.args" ]
    tb_tty
    run speed -s 1 <<< "n"
    [ "$status" -eq 5 ]
    [[ $output == *"       uses about 2 MB. Run it anyway? [y/N] "* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.args" ]
    run speed -y -q -s 1
    [ "$status" -eq 0 ]
    [ "$output" = "0.9 0.4" ]
}

@test "no answer from Cloudflare exits 1" {
    tb_stub curl 'exit 6'
    run speed -s 1
    [ "$status" -eq 1 ]
    [[ $output == *"no answer from speed.cloudflare.com"* ]]
}

@test "librespeed-cli is used when installed" {
    tb_stub librespeed-cli '
echo "$*" > "$BATS_TEST_TMPDIR/libre.args"
echo "[{\"timestamp\":\"2026-09-29T16:00:00Z\",\"server\":{\"name\":\"Chennai, India (Example)\",\"url\":\"https://x\"},\"bytes_sent\":52000000,\"bytes_received\":118000000,\"ping\":17.6,\"jitter\":2.8,\"upload\":41.84,\"download\":94.31,\"share\":\"\"}]"'
    run speed -- --server 52
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "server    Chennai, India (Example), ping 18 ms, jitter 3 ms" ]
    [[ ${lines[1]} == "download   94.3 Mbit/s  "* ]]
    [[ ${lines[2]} == "upload     41.8 Mbit/s  "* ]]
    [[ ${lines[3]} == "used      118 MB down, 52 MB up in "* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/libre.args")" = "--json --server 52" ]
    [ ! -e "$BATS_TEST_TMPDIR/curl.args" ]
}

@test "Ookla speedtest is used when installed" {
    tb_stub speedtest '
[[ $1 == --version ]] && { echo "Speedtest by Ookla 1.2.0.84"; exit 0; }
echo "{\"type\":\"result\",\"ping\":{\"jitter\":1.2,\"latency\":12.4},\"download\":{\"bandwidth\":11787500,\"bytes\":120000000,\"elapsed\":10200},\"upload\":{\"bandwidth\":5225000,\"bytes\":50000000,\"elapsed\":9800},\"server\":{\"id\":1,\"name\":\"Airtel\",\"location\":\"Chennai\"}}"'
    run speed -q
    [ "$output" = "94.3 41.8" ]
    run speed
    [ "${lines[0]}" = "server    Airtel Chennai, ping 12 ms, jitter 1 ms" ]
}
