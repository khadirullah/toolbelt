#!/usr/bin/env bats
# Tests for waitfor. Ports use a tiny local server the test starts, URLs use a curl stub.

load helpers

setup() {
    tb_setup
    SERVER_PID=""
}

teardown() {
    if [[ -n $SERVER_PID ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
    fi
}

spare_port() {
    bash -c "source '$TB_REPO/lib/common.sh'; tb_free_port $((20000 + RANDOM % 20000))"
}

@test "help prints usage and exits 0" {
    run waitfor --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: waitfor "* ]]
}

@test "bad usage exits 2" {
    run waitfor
    [ "$status" -eq 2 ]
    [[ $output == *"name a HOST:PORT, a URL or a path"* ]]
    run waitfor a b
    [ "$status" -eq 2 ]
    run waitfor -t soon db:5432
    [ "$status" -eq 2 ]
    run waitfor -s ok http://x/
    [ "$status" -eq 2 ]
    run waitfor db:70000
    [ "$status" -eq 2 ]
    run waitfor db:5432 -- --insecure
    [ "$status" -eq 2 ]
    [[ $output == *"only a URL uses curl"* ]]
}

@test "a missing curl exits 3 for a URL" {
    tb_without curl
    run waitfor http://localhost:8080/
    [ "$status" -eq 3 ]
    [[ $output == "waitfor: needs curl."* ]]
}

@test "a port that is open" {
    PORT=$(spare_port)
    nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
    SERVER_PID=$!
    run waitfor -t 10 -i 0.2 "127.0.0.1:$PORT"
    [ "$status" -eq 0 ]
    [[ $output == "127.0.0.1:$PORT open after "* ]]
    run waitfor -q ":$PORT"
    [ "$status" -eq 0 ]
    [[ $output == "localhost:$PORT open after "* ]]
}

@test "a closed port gives up after the timeout with exit 1" {
    local p
    p=$(spare_port)
    run waitfor -v -t 1 -i 0.3 "127.0.0.1:$p"
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "+ bash -c 'exec 3<>/dev/tcp/127.0.0.1/$p'" ]
    [ "${lines[1]}" = "try 1  connection refused" ]
    [[ ${lines[-1]} == "waitfor: gave up after 1."*"s, 127.0.0.1:$p is still closed, connection refused" ]]
}

@test "a URL waits for 200, counting other codes as not ready" {
    tb_stub curl '
n=$(cat "$BATS_TEST_TMPDIR/n" 2>/dev/null || echo 0)
echo $((n + 1)) > "$BATS_TEST_TMPDIR/n"
case $n in 0) exit 7 ;; 1) printf 503 ;; *) printf 200 ;; esac'
    run waitfor -v -i 0.1 http://localhost:8080/healthz
    [ "$status" -eq 0 ]
    [[ $output == *"try 1  refused"* ]]
    [[ $output == *"try 2  503"* ]]
    [[ ${lines[-1]} == "http://localhost:8080/healthz answered 200 after "* ]]
}

@test "--status waits for another code, and pass-through reaches curl" {
    tb_stub curl 'echo "$*" > "$BATS_TEST_TMPDIR/args"; printf 401'
    run waitfor -s 401 https://localhost:8443/ -- --insecure
    [ "$status" -eq 0 ]
    [[ $(cat "$BATS_TEST_TMPDIR/args") == *"--insecure -- https://localhost:8443/" ]]
}

@test "a URL that never gets ready says what it last answered" {
    tb_stub curl 'printf 503'
    run waitfor -t 0.5 -i 0.2 http://localhost:8080/
    [ "$status" -eq 1 ]
    [[ $output == "waitfor: gave up after "*"http://localhost:8080/ last said 503" ]]
}

@test "a file that appears" {
    (sleep 0.5; touch app.sock) &
    run waitfor -t 5 -i 0.2 app.sock
    [ "$status" -eq 0 ]
    [[ $output == "app.sock exists after "* ]]
}

@test "a file that never appears" {
    run waitfor -t 0.5 -i 0.2 missing.sock
    [ "$status" -eq 1 ]
    [[ $output == "waitfor: gave up after "*"missing.sock does not exist" ]]
}
