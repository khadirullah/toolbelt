#!/usr/bin/env bats
# Tests for httptime. A curl stub gives fixed timings; one test uses the real
# curl against a tiny local server the test starts itself.

load helpers

setup() {
    tb_setup
    SERVER_PID=""
    # code version bytes namelookup connect appconnect starttransfer total redirects redirect
    tb_stub curl 'echo "$*" >> "$BATS_TEST_TMPDIR/curl.args"; echo "200 2 1256 0.012 0.038 0.071 0.164 0.168 0 0"'
}

teardown() {
    if [[ -n $SERVER_PID ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
    fi
}

@test "help prints usage and exits 0" {
    run httptime --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: httptime "* ]]
}

@test "bad usage exits 2" {
    run httptime
    [ "$status" -eq 2 ]
    [[ $output == *"name a URL to time"* ]]
    run httptime -n 0 https://example.com/
    [ "$status" -eq 2 ]
    run httptime -n many https://example.com/
    [ "$status" -eq 2 ]
    run httptime https://a/ https://b/
    [ "$status" -eq 2 ]
}

@test "a missing curl exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/curl"
    tb_without curl
    run httptime https://example.com/
    [ "$status" -eq 3 ]
    [[ $output == "httptime: needs curl."* ]]
}

@test "the running totals become one line per step" {
    run httptime https://example.com/
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://example.com/  200, HTTP/2, 1,256 bytes" ]
    [[ ${lines[1]} == "dns           12 ms  "* ]]
    [[ ${lines[2]} == "connect       26 ms  "* ]]
    [[ ${lines[3]} == "tls           33 ms  "* ]]
    [[ ${lines[4]} == "first byte    93 ms  ████████████████████" ]]
    [[ ${lines[5]} == "download     4.0 ms  "* ]]
    [ "${lines[6]}" = "total        168 ms" ]
}

@test "-q prints the total only, and -v the curl command" {
    run httptime -q https://example.com/
    [ "$output" = "168 ms" ]
    run httptime -q -v https://example.com/
    [[ ${lines[0]} == "+ curl -s -o /dev/null -w '%{http_code} "* ]]
    [ "${lines[1]}" = "168 ms" ]
}

@test "-n shows min, median and max" {
    tb_stub curl '
n=$(cat "$BATS_TEST_TMPDIR/n" 2>/dev/null || echo 0); echo $((n + 1)) > "$BATS_TEST_TMPDIR/n"
case $n in
    0) echo "200 2 10 0.011 0.035 0.075 0.250 0.296 0 0" ;;
    1) echo "200 2 10 0 0.024 0.054 0.095 0.098 0 0" ;;
    *) echo "200 2 10 0 0.025 0.057 0.104 0.106 0 0" ;;
esac'
    run httptime -n 3 https://example.com/health
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://example.com/health  3 runs, all 200" ]
    [ "${lines[1]}" = "               MIN   MEDIAN      MAX" ]
    [ "${lines[2]}" = "dns         0.0 ms   0.0 ms    11 ms" ]
    [ "${lines[3]}" = "connect      24 ms    24 ms    25 ms" ]
    [ "${lines[5]}" = "first byte   41 ms    47 ms   175 ms" ]
    [ "${lines[6]}" = "total        98 ms   106 ms   296 ms" ]
}

@test "an HTTP error code still exits 0" {
    tb_stub curl 'echo "503 1.1 0 0.001 0.002 0 0.010 0.011 0 0"'
    run httptime http://localhost:8080/
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "http://localhost:8080/  503, HTTP/1.1, 0 bytes" ]
    [[ $output != *tls* ]]
}

@test "a curl failure exits 1 with the reason" {
    tb_stub curl 'exit 6'
    run httptime https://stage.example.com/
    [ "$status" -eq 1 ]
    [ "$output" = "httptime: could not resolve stage.example.com (curl exit 6)" ]
}

@test "-L and pass-through options reach curl" {
    run httptime -L https://example.com/api -- -X POST -d '{}'
    [[ $(cat "$BATS_TEST_TMPDIR/curl.args") == *" -L -X POST -d {} -- https://example.com/api" ]]
}

@test "redirects get a line of their own" {
    tb_stub curl 'echo "200 2 10 0.050 0.060 0.080 0.120 0.130 1 0.040"'
    run httptime -L https://example.com/old
    [ "${lines[0]}" = "https://example.com/old  200, HTTP/2, 10 bytes, 1 redirect" ]
    [[ ${lines[1]} == "redirects     40 ms  "* ]]
    [ "${lines[-1]}" = "total        130 ms" ]
}

@test "the real curl against a local server" {
    rm "$BATS_TEST_TMPDIR/stubs/curl"
    local port
    port=$(bash -c "source '$TB_REPO/lib/common.sh'; tb_free_port $((20000 + RANDOM % 20000))")
    printf 'hello\n' > index.html
    nohup python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 &
    SERVER_PID=$!
    run waitfor -q -t 5 -i 0.1 "127.0.0.1:$port"
    run httptime "http://127.0.0.1:$port/"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "http://127.0.0.1:$port/  200, HTTP/1.0, 6 bytes" ]
    [[ ${lines[-1]} == "total  "*" ms" ]]
}
