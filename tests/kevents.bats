#!/usr/bin/env bats
# Tests for kevents. kubectl is a stub that prints events shaped like
# `kubectl get events -o json`, and a short watch stream for -f.

load helpers

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    local now
    now=$(date +%s)
    jq -n --argjson now "$now" '
        def at($ago): ($now - $ago) | strftime("%Y-%m-%dT%H:%M:%SZ");
        {kind: "List", items: [
        {metadata: {name: "e3", namespace: "shop"}, type: "Warning", reason: "BackOff", count: 14,
         involvedObject: {kind: "Pod", name: "api-1", namespace: "shop"},
         message: "Back-off restarting failed container api", lastTimestamp: at(60)},
        {metadata: {name: "e1", namespace: "shop"}, type: "Normal", reason: "ScalingReplicaSet",
         involvedObject: {kind: "Deployment", name: "api", namespace: "shop"},
         message: "Scaled up replica set api-5b8c9d7f6 to 2", lastTimestamp: at(600)},
        {metadata: {name: "e2", namespace: "shop"}, type: "Warning", reason: "FailedScheduling",
         involvedObject: {kind: "Pod", name: "api-2", namespace: "shop"},
         message: "0/3 nodes are available: 3 Insufficient cpu.", eventTime: at(300)},
        {metadata: {name: "e0", namespace: "shop"}, type: "Normal", reason: "Pulled",
         involvedObject: {kind: "Pod", name: "old-1", namespace: "shop"},
         message: "Container image already present", lastTimestamp: at(172800)}]}' > "$FX/events.json"
    jq -n '{kind: "List", items: []}' > "$FX/none.json"
    jq -n --argjson now "$now" '
        def at($ago): ($now - $ago) | strftime("%Y-%m-%dT%H:%M:%SZ");
        {kind: "List", items: [
        {type: "Warning", reason: "Unhealthy", involvedObject: {kind: "Pod", name: "web-1"},
         message: "Readiness probe failed", lastTimestamp: at(3000),
         series: {count: 9, lastObservedTime: (at(30) | sub("Z$"; ".123456Z"))}},
        {type: "Normal", reason: "Pulled", involvedObject: {kind: "Pod", name: "web-1"},
         message: "pulled", lastTimestamp: at(600)}]}' > "$FX/series.json"
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case " $* " in
    *" config view "*) printf 'kind-kind\tshop' ;;
    *" --watch-only "*)
        [[ -n ${HANG:-} ]] && { echo $$ > "$FX/watch.pid"; exec sleep 30; }
        jq -c '{type: "ADDED", object: .items[0]}' "$FX/events.json"
        jq -c '.items[1]' "$FX/events.json" ;;
    *" get events "*)
        [[ -n ${DOWN:-} ]] && { echo "The connection to the server 127.0.0.1:6443 was refused" >&2; exit 1; }
        cat "$FX/${EVENTS:-events}.json" ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

@test "help prints usage and exits 0" {
    run kevents --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: kevents [-n NAMESPACE | -A] [-w] [--since TIME] [-f] [OBJECT]" ]
}

@test "bad usage exits 2" {
    run kevents --since soon
    [ "$status" -eq 2 ]
    run kevents -A -n shop
    [ "$status" -eq 2 ]
    run kevents pod/a pod/b
    [ "$status" -eq 2 ]
    run kevents --nope
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run kevents
    [ "$status" -eq 3 ]
    [[ $output == "kevents: needs kubectl."* ]]
}

@test "events print oldest first with the message indented" {
    run kevents
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == *[0-9]"  Normal   deploy/api  ScalingReplicaSet" ]]
    [[ ${lines[1]} =~ ^\ {10,14}Scaled\ up\ replica\ set\ api-5b8c9d7f6\ to\ 2$ ]]
    [[ ${lines[2]} == *"  Warning  pod/api-2  FailedScheduling" ]]
    [[ ${lines[4]} == *"  Warning  pod/api-1  BackOff x14" ]]
    [ "${lines[6]}" = "3 events, 2 warnings" ]
    grep -q -- "get events -n shop -o json" "$CALLS"
}

@test "--since all shows older events with the date" {
    run kevents --since all
    [ "$status" -eq 0 ]
    [[ ${lines[0]} =~ ^[A-Z][a-z]{2}\ [0-9]{2}\ [0-9]{2}:[0-9]{2}\ \ Normal\ \ \ pod/old-1\ \ Pulled$ ]]
    [ "${lines[-1]}" = "4 events, 2 warnings" ]
}

@test "--since cuts older events" {
    run kevents --since 2m
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "1 event, 1 warning" ]
}

@test "-A prefixes the namespace and asks every namespace" {
    run kevents -A
    [[ ${lines[0]} == *"  shop/deploy/api  ScalingReplicaSet" ]]
    grep -q -- "get events -A -o json" "$CALLS"
}

@test "an object and -w become a field selector" {
    run kevents -w po/api-1
    [ "$status" -eq 0 ]
    grep -q -- "--field-selector involvedObject.kind=Pod,involvedObject.name=api-1,type=Warning" "$CALLS"
    [[ $output != *Normal* ]]
}

@test "no events says so on stderr and exits 0" {
    bats_require_minimum_version 1.5.0
    EVENTS=none run --separate-stderr kevents deploy/api
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ "$stderr" = "kevents: no events for deploy/api in the last 1h" ]
}

@test "-q drops the summary" {
    run kevents -q
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 6 ]
}

@test "-f follows the watch stream after the list" {
    run kevents -w -f
    [ "$status" -eq 0 ]
    [[ $output == *"following warnings in namespace shop, Ctrl+C stops"* ]]
    [[ ${lines[-2]} == *"  Warning  pod/api-1  BackOff x14" ]]
    grep -q -- "get events -n shop --field-selector type=Warning --watch-only -o json" "$CALLS"
}

@test "stopping -f stops the kubectl watch too" {
    HANG=1 kevents -q -f >/dev/null 2>&1 3>&- &
    local pid=$! i
    for i in $(seq 50); do [ -s "$FX/watch.pid" ] && break; sleep 0.1; done
    [ -s "$FX/watch.pid" ]
    kill -TERM "$pid"
    for i in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$pid" 2>/dev/null; then echo "kevents still running"; false; fi
    wait "$pid"
    if kill -0 "$(cat "$FX/watch.pid")" 2>/dev/null; then echo "kubectl still running"; false; fi
}

@test "an unreachable kind cluster gets a hint" {
    DOWN=1 run kevents
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "kevents: cannot reach the cluster for context kind-kind" ]
    [ "${lines[1]}" = "kevents: is the kind container running? Try: kind get clusters" ]
}

@test "pass-through options reach kubectl" {
    run kevents -- --context kind-kind
    grep -q -- "get events -n shop -o json --context kind-kind" "$CALLS"
    grep -q -- "config view --minify --context kind-kind" "$CALLS"
}

@test "a series time newer than lastTimestamp sorts the event last" {
    EVENTS=series run kevents
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == *"  Normal   pod/web-1  Pulled" ]]
    [[ ${lines[2]} == *"  Warning  pod/web-1  Unhealthy x9" ]]
}
