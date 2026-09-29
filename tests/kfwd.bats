#!/usr/bin/env bats
# Tests for kfwd. kubectl is a stub. Its port-forward prints the line the
# real one prints, then sleeps a little, so the tests start kfwd in the
# background and stop it by pid.

load helpers

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    cat > "$FX/grafana.json" <<'JSON'
{"apiVersion":"v1","kind":"Service","metadata":{"name":"grafana","namespace":"monitoring"},
 "spec":{"type":"ClusterIP","clusterIP":"10.96.12.40","selector":{"app":"grafana"},
  "ports":[{"name":"service","port":80,"protocol":"TCP","targetPort":3000}]}}
JSON
    cat > "$FX/prometheus-server.json" <<'JSON'
{"apiVersion":"v1","kind":"Service","metadata":{"name":"prometheus-server","namespace":"monitoring"},
 "spec":{"type":"ClusterIP","selector":{"app":"prometheus"},
  "ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":9090},
           {"name":"grpc","port":9090,"protocol":"TCP","targetPort":10901}]}}
JSON
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case " $* " in
    *" config view "*) printf 'kind-kind\tmonitoring' ;;
    *" get svc -n "*) printf 'service/grafana\nservice/prometheus-server\n' ;;
    *" get svc "*)
        if [[ -f $FX/$3.json ]]; then cat "$FX/$3.json"; exit 0; fi
        echo "Error from server (NotFound): services \"$3\" not found" >&2; exit 1 ;;
    *" port-forward "*)
        n=$(( $(cat "$BATS_TEST_TMPDIR/pf-count" 2>/dev/null || echo 0) + 1 ))
        echo "$n" > "$BATS_TEST_TMPDIR/pf-count"
        echo $$ >> "$BATS_TEST_TMPDIR/pf-pids"
        [[ -n ${PF_FAIL:-} ]] && { echo "$PF_FAIL" >&2; exit 1; }
        lp=${3%%:*}
        echo "Forwarding from 127.0.0.1:$lp -> ${3#*:}"
        echo "Forwarding from [::1]:$lp -> ${3#*:}"
        if (( n == 1 )) && [[ -n ${PF_DROP:-} ]]; then
            sleep 0.3
            echo "error: lost connection to pod" >&2
            exit 1
        fi
        exec sleep 5 ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

# Wait up to 5 seconds for text to show in a file.
wait_for() {
    local i
    for ((i = 0; i < 50; i++)); do
        grep -q -- "$2" "$1" 2>/dev/null && return 0
        sleep 0.1
    done
    cat "$1" >&2
    return 1
}

@test "help prints usage and exits 0" {
    run kfwd --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: kfwd "* ]]
}

@test "bad usage exits 2" {
    run kfwd
    [ "$status" -eq 2 ]
    run kfwd --local 99999 grafana
    [ "$status" -eq 2 ]
    run kfwd --local x grafana
    [ "$status" -eq 2 ]
    run kfwd grafana loki
    [ "$status" -eq 2 ]
    run kfwd -p 3000 grafana
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run kfwd grafana
    [ "$status" -eq 3 ]
    [[ $output == "kfwd: needs kubectl."* ]]
}

@test "--open without xdg-open exits 3" {
    tb_without xdg-open
    run kfwd --open grafana
    [ "$status" -eq 3 ]
    [[ $output == "kfwd: needs xdg-open."* ]]
}

@test "a service with two ports asks for --port and exits 2" {
    run kfwd prometheus-server
    [ "$status" -eq 2 ]
    [[ $output == *"kfwd: svc/prometheus-server has 2 ports, http 80 and grpc 9090"* ]]
    [[ $output == *"kfwd: pick one with --port 80 or --port 9090"* ]]
    run kfwd --port 7000 prometheus-server
    [ "$status" -eq 2 ]
    [[ $output == *"has no port 7000"* ]]
}

@test "a missing service suggests the closest name" {
    run kfwd grafna
    [ "$status" -eq 1 ]
    [ "$output" = "kfwd: no service grafna in monitoring. Did you mean grafana?" ]
}

@test "a local port in use exits 1 and names the owner" {
    python3 -c 'import socket, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen()
print(s.getsockname()[1], flush=True); time.sleep(10)' > "$BATS_TEST_TMPDIR/port" &
    local lpid=$!
    wait_for "$BATS_TEST_TMPDIR/port" "[0-9]"
    local port
    port=$(cat "$BATS_TEST_TMPDIR/port")
    run kfwd --local "$port" grafana
    kill "$lpid"
    [ "$status" -eq 1 ]
    [[ $output == *"kfwd: port $port is used by python3 (pid $lpid)"* || $output == *"kfwd: port $port is in use"* ]]
    [[ $output == *"leave out --local"* ]]
    ! grep -q port-forward "$CALLS"
}

@test "forwards to a spare port, prints the URL, stops cleanly" {
    kfwd grafana > "$BATS_TEST_TMPDIR/out" 2>&1 &
    local pid=$!
    wait_for "$BATS_TEST_TMPDIR/out" "Ctrl+C stops it"
    kill -TERM "$pid"
    local rc=0
    wait "$pid" || rc=$?
    [ "$rc" -eq 0 ]
    grep -Eq "^forwarding svc/grafana port 80 to http://127.0.0.1:[0-9]+$" "$BATS_TEST_TMPDIR/out"
    grep -Eq "port-forward svc/grafana [0-9]+:80 -n monitoring" "$CALLS"
    local child
    child=$(cat "$BATS_TEST_TMPDIR/pf-pids")
    ! kill -0 "$child" 2>/dev/null
}

@test "-q prints only the URL and --port picks by name" {
    kfwd -q --port grpc prometheus-server > "$BATS_TEST_TMPDIR/out" 2>&1 &
    local pid=$!
    wait_for "$BATS_TEST_TMPDIR/out" "http://"
    kill -TERM "$pid"
    wait "$pid" || true
    grep -Eq "^http://127.0.0.1:[0-9]+$" "$BATS_TEST_TMPDIR/out"
    [ "$(wc -l < "$BATS_TEST_TMPDIR/out")" -eq 1 ]
    grep -Eq "port-forward svc/prometheus-server [0-9]+:9090 " "$CALLS"
}

@test "reconnects when the forward drops" {
    PF_DROP=1 kfwd grafana -- --address 127.0.0.1 > "$BATS_TEST_TMPDIR/out" 2>&1 &
    local pid=$!
    wait_for "$BATS_TEST_TMPDIR/out" "back on http://127.0.0.1:"
    kill -TERM "$pid"
    wait "$pid" || true
    grep -q "kfwd: the connection to svc/grafana dropped, reconnecting" "$BATS_TEST_TMPDIR/out"
    [ "$(cat "$BATS_TEST_TMPDIR/pf-count")" -eq 2 ]
    grep -q -- "--address 127.0.0.1" "$CALLS"
    local child
    for child in $(cat "$BATS_TEST_TMPDIR/pf-pids"); do
        ! kill -0 "$child" 2>/dev/null
    done
}

@test "a failed first start exits 1 with kubectl's reason" {
    PF_FAIL='error: unable to forward port because pod is not running. Current status=Pending' run kfwd grafana
    [ "$status" -eq 1 ]
    [[ $output == *"kfwd: kubectl failed: unable to forward port because pod is not running"* ]]
}
