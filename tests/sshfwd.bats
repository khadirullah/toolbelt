#!/usr/bin/env bats
# Tests for sshfwd. ssh is a stub: a tunnel starts a short sleep as the
# master connection and writes its pid into the control socket path.
# Nothing connects anywhere.

load helpers

setup() {
    tb_setup
    SERVER_PID=""
    FG_PID=""
    tb_stub ssh '
echo "$*" >> "$BATS_TEST_TMPDIR/ssh.args"
sock="" op="" prev="" host="${@: -1}"
for a in "$@"; do
    [[ $prev == -S ]] && sock=$a
    [[ $prev == -O ]] && op=$a
    [[ $prev == -o && $a == ControlPath=* ]] && sock=${a#ControlPath=}
    prev=$a
done
case $op in
    check)
        if [[ -f $sock ]] && kill -0 "$(cat "$sock")" 2>/dev/null; then
            echo "Master running (pid=$(cat "$sock"))" >&2
            exit 0
        fi
        echo "Control socket connect($sock): No such file or directory" >&2
        exit 255 ;;
    exit)
        [[ -f $sock ]] && kill "$(cat "$sock")" 2>/dev/null
        rm -f "$sock"
        exit 0 ;;
esac
if [[ $host == bad* ]]; then
    echo "khadir@$host: Permission denied (publickey)." >&2
    exit 255
fi
nohup sleep 30 >/dev/null 2>&1 &
echo $! > "$sock"
echo $! >> "$BATS_TEST_TMPDIR/masters"
exit 0'
}

teardown() {
    local p
    if [[ -n $FG_PID ]] && kill -0 "$FG_PID" 2>/dev/null; then
        kill "$FG_PID"
    fi
    if [[ -n $SERVER_PID ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
    fi
    if [[ -f $BATS_TEST_TMPDIR/masters ]]; then
        while read -r p; do
            kill -0 "$p" 2>/dev/null && kill "$p"
        done < "$BATS_TEST_TMPDIR/masters"
    fi
    return 0
}

spare_port() {
    bash -c "source '$TB_REPO/lib/common.sh'; tb_free_port $((20000 + RANDOM % 20000))"
}

@test "help prints usage and exits 0" {
    run sshfwd --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: sshfwd "* ]]
}

@test "bad usage exits 2" {
    run sshfwd
    [ "$status" -eq 2 ]
    run sshfwd k8s-master
    [ "$status" -eq 2 ]
    [[ $output == *"name a port to forward, such as: sshfwd k8s-master 8080"* ]]
    run sshfwd k8s-master 99999
    [ "$status" -eq 2 ]
    run sshfwd -R -D host 8080
    [ "$status" -eq 2 ]
    run sshfwd -R host 8080 9090
    [ "$status" -eq 2 ]
    run sshfwd -l 9000 host 8080 9090
    [ "$status" -eq 2 ]
    run sshfwd --stop
    [ "$status" -eq 2 ]
    run sshfwd --stop one
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/ssh.args" ]
}

@test "a missing ssh exits 3" {
    rm "$BATS_TEST_TMPDIR/stubs/ssh"
    tb_without ssh
    run sshfwd k8s-master 8080
    [ "$status" -eq 3 ]
    [[ $output == "sshfwd: needs ssh."* ]]
}

@test "-b opens a tunnel in the background, --list shows it, --stop closes it" {
    local p
    p=$(spare_port)
    run sshfwd -b bastion.example.com "db.example.com:$p" -- -p 2222
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "tunnel 1  localhost:$p to db.example.com:$p" ]
    [ "${lines[1]}" = "          through bastion.example.com" ]
    [[ ${lines[2]} == "in the background, pid "*". Close it with: sshfwd --stop 1" ]]
    grep -q -- "-f -N -L 127.0.0.1:$p:db.example.com:$p -o ExitOnForwardFailure=yes" "$BATS_TEST_TMPDIR/ssh.args"
    grep -q -- " -p 2222 bastion.example.com$" "$BATS_TEST_TMPDIR/ssh.args"
    master=$(head -n1 "$BATS_TEST_TMPDIR/masters")
    kill -0 "$master"

    run sshfwd --list
    [ "${lines[0]}" = "ID  PID      UP     TUNNEL" ]
    [[ ${lines[1]} == "1   $master"*"localhost:$p to db.example.com:$p, through bastion.example.com" ]]

    run sshfwd --stop 1
    [ "$status" -eq 0 ]
    [ "$output" = "closed tunnel 1, localhost:$p to db.example.com:$p" ]
    not kill -0 "$master" 2>/dev/null
    run sshfwd --stop 1
    [ "$status" -eq 1 ]
    [[ $output == *"no tunnel 1"* ]]
}

@test "--stop all closes every tunnel, and --list drops dead ones" {
    run sshfwd -q -b host-a "$(spare_port)"
    [ "$output" = "1" ]
    run sshfwd -q -b host-b "$(spare_port)"
    [ "$output" = "2" ]
    kill "$(head -n1 "$BATS_TEST_TMPDIR/masters")"
    sleep 0.2
    run sshfwd --list
    [[ ${lines[0]} == "tunnel 1 to host-a had stopped, removed it" ]]
    [[ ${lines[2]} == "2   "* ]]
    run sshfwd --stop all
    [[ $output == "closed tunnel 2, localhost:"*" on host-b" ]]
    run sshfwd --list
    [[ $output == "no background tunnels."* ]]
}

@test "a taken local port moves to the next free one" {
    local p
    p=$(spare_port)
    nohup python3 -m http.server "$p" --bind 127.0.0.1 >/dev/null 2>&1 &
    SERVER_PID=$!
    waitfor -q -t 5 -i 0.1 "127.0.0.1:$p" > /dev/null
    run sshfwd -b k8s-master "$p"
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "local $p is taken by "*", using "* ]]
    [[ ${lines[1]} == "tunnel 1  localhost:"*" to port $p on k8s-master" ]]
    [[ ${lines[1]} != "tunnel 1  localhost:$p "* ]]
    run sshfwd -b -l "$p" k8s-master 8080
    [ "$status" -eq 1 ]
    [[ $output == *"local $p is taken by"*"Leave out -l to take a free port"* ]]
}

@test "ssh failing exits 1 with its reason" {
    run sshfwd badhost-1 "$(spare_port)"
    [ "$status" -eq 1 ]
    [ "$output" = "sshfwd: ssh to badhost-1 failed. Permission denied (publickey)." ]
}

@test "-D opens a SOCKS proxy, and a port below 1024 moves up" {
    run sshfwd -b -v -D bastion.example.com
    [ "$status" -eq 0 ]
    grep -q -- "-D 127.0.0.1:" "$BATS_TEST_TMPDIR/ssh.args"
    [[ $output == *"tunnel 1  127.0.0.1:"*" through bastion.example.com"* ]]
    if (( EUID != 0 )); then
        run sshfwd -b k8s-master 80
        [[ ${lines[0]} == "local 80 needs root, using 8080"* ]]
    fi
}

@test "-R opens a port on the host" {
    run sshfwd -b -R k8s-master 23999
    [ "$status" -eq 0 ]
    grep -q -- "-R 23999:localhost:23999" "$BATS_TEST_TMPDIR/ssh.args"
    [[ $output == *"nothing listens on local 23999 yet"* ]]
    [[ $output == *"tunnel 1  port 23999 on k8s-master leads to localhost:23999"* ]]
}

@test "a foreground tunnel closes when sshfwd stops, and reports a drop" {
    local p
    p=$(spare_port)
    nohup sshfwd k8s-master "$p" > out 2>&1 &
    FG_PID=$!
    for _ in $(seq 50); do grep -q "Ctrl+C closes it." out && break; sleep 0.1; done
    [ "$(head -n1 out)" = "tunnel  localhost:$p to port $p on k8s-master" ]
    master=$(head -n1 "$BATS_TEST_TMPDIR/masters")
    kill "$FG_PID"
    wait "$FG_PID" || true
    FG_PID=""
    ! kill -0 "$master" 2>/dev/null || grep -qs '^State:[[:space:]]*Z' "/proc/$master/status"

    nohup sshfwd k8s-master "$p" > out 2>&1 &
    FG_PID=$!
    for _ in $(seq 50); do grep -q "Ctrl+C closes it." out && break; sleep 0.1; done
    kill "$(tail -n1 "$BATS_TEST_TMPDIR/masters")"
    rc=0
    wait "$FG_PID" || rc=$?
    FG_PID=""
    [ "$rc" -eq 1 ]
    grep -q "sshfwd: the tunnel to k8s-master dropped" out
}
