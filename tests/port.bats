#!/usr/bin/env bats
# Tests for port. The kill tests stop only a server the test started itself.

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

# A spare port well away from the ones people use by hand.
spare_port() {
    bash -c "source '$TB_REPO/lib/common.sh'; tb_free_port $((20000 + RANDOM % 20000))"
}

# The spaces after a port/proto column of 10.
pad() { printf "%*s" $(( 10 - ${#1} )) ""; }

# Start a tiny web server of our own and wait until it listens.
start_server() {
    PORT=$(spare_port)
    nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
    SERVER_PID=$!
    local i
    for ((i = 0; i < 50; i++)); do
        ss -H -tln "sport = :$PORT" | grep -q . && return 0
        sleep 0.1
    done
    return 1
}

@test "help prints usage and exits 0" {
    run port --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: port "* ]]
}

@test "bad usage exits 2" {
    run port 70000
    [ "$status" -eq 2 ]
    [[ $output == *"70000 is not a port number"* ]]
    run port web
    [ "$status" -eq 2 ]
    run port --nope
    [ "$status" -eq 2 ]
    run port -k
    [ "$status" -eq 2 ]
    [[ $output == *"--kill needs a port number"* ]]
    run port -y 8000
    [ "$status" -eq 2 ]
}

@test "with neither ss nor lsof it exits 3" {
    tb_without ss lsof
    run port 8000
    [ "$status" -eq 3 ]
    [[ $output == "port: needs lsof."* ]]
}

@test "it names the process on a port our server holds" {
    start_server
    run port "$PORT"
    [ "$status" -eq 0 ]
    [[ $output == "$PORT/tcp$(pad "$PORT/tcp")127.0.0.1  pid $SERVER_PID  $(id -un)  python3 -m http.server $PORT --bind 127.0.0.1" ]]
    run port ":$PORT"
    [ "$status" -eq 0 ]
}

@test "a free port says nobody listens and exits 1" {
    local p
    p=$(spare_port)
    run port "$p"
    [ "$status" -eq 1 ]
    [[ $output == "$p/tcp"*"nobody listens" ]]
}

@test "several ports, one per line" {
    start_server
    local p
    p=$(spare_port)
    run port "$PORT" "$p"
    [ "$status" -eq 1 ]
    [[ ${lines[0]} == "$PORT/tcp"*" 127.0.0.1  pid $SERVER_PID"* ]]
    [[ ${lines[1]} == "$p/tcp"*"nobody listens" ]]
}

@test "-v shows the ss command" {
    start_server
    run port -v "$PORT"
    [[ ${lines[0]} == "+ ss -H -tlnp 'sport = :$PORT'" ]]
}

@test "pass-through options go to ss" {
    tb_stub ss 'echo "$*" > "$BATS_TEST_TMPDIR/ss.args"'
    run port 5353 -u -- -4
    [ "$(cat "$BATS_TEST_TMPDIR/ss.args")" = "-H -ulnp -4 sport = :5353" ]
}

@test "no port lists every listener, sorted" {
    tb_stub ss 'printf "%s\n" "LISTEN 0 5 0.0.0.0:9000 0.0.0.0:* users:((\"web\",pid=11,fd=3))" "LISTEN 0 5 127.0.0.1:22 0.0.0.0:*"'
    run port
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "22/tcp    127.0.0.1  owner hidden, run it with sudo to see the process" ]
    [[ ${lines[1]} == "9000/tcp  0.0.0.0  pid 11  "* ]]
}

@test "a rootless podman port names the container" {
    tb_stub ss 'echo "LISTEN 0 5 0.0.0.0:5432 0.0.0.0:* users:((\"rootlessport\",pid=$$,fd=3))"'
    tb_stub podman 'printf "web\t0.0.0.0:8080->80/tcp\npg-dev\t0.0.0.0:5432->5432/tcp\n"'
    run port 5432
    [ "$status" -eq 0 ]
    [[ $output == *"rootlessport, container pg-dev" ]]
}

@test "without ss it falls back to lsof" {
    tb_stub lsof 'printf "p4121\ncpython3\nn*:8000\n"'
    tb_without ss
    run port 8000
    [ "$status" -eq 0 ]
    [[ $output == "8000/tcp  0.0.0.0  pid 4121  "* ]]
}

@test "--kill stops our server with --yes" {
    start_server
    run port -k -y "$PORT"
    [ "$status" -eq 0 ]
    [[ ${lines[-1]} == "stopped after "*". $PORT/tcp is free." ]]
    sleep 0.2
    not kill -0 "$SERVER_PID" 2>/dev/null
}

@test "--kill asks first, and a no leaves it running" {
    start_server
    tb_tty
    run bash -c "echo n | port -k $PORT"
    [ "$status" -eq 5 ]
    [[ $output == *"Stop pid $SERVER_PID (python3)? [y/N]"* ]]
    kill -0 "$SERVER_PID"
    run bash -c "echo y | port -k $PORT"
    [ "$status" -eq 0 ]
    sleep 0.2
    not kill -0 "$SERVER_PID" 2>/dev/null
}

@test "--kill without a terminal or --yes refuses" {
    start_server
    run port -k "$PORT" </dev/null
    [ "$status" -eq 4 ]
    kill -0 "$SERVER_PID"
}

@test "--kill refuses a hidden owner and another user's process" {
    tb_stub ss 'echo "LISTEN 0 5 127.0.0.1:631 0.0.0.0:*"'
    run port -k -y 631
    [ "$status" -eq 1 ]
    [[ $output == *"cannot see who holds 631/tcp"* ]]
    tb_stub ss 'echo "LISTEN 0 5 0.0.0.0:22 0.0.0.0:* users:((\"systemd\",pid=1,fd=3))"'
    run port -k -y 22
    [ "$status" -eq 4 ]
    [[ $output == *"pid 1 holds 22/tcp for socket activation"* ]]
}

@test "--free prints a port between 8000 and 8999 that nobody uses" {
    run port --free
    [ "$status" -eq 0 ]
    (( output >= 8000 && output < 9000 ))
    run port "$output"
    [ "$status" -eq 1 ]
}
