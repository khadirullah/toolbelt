#!/usr/bin/env bats
# Tests for knodes. kubectl is a stub that prints nodes, events and pods
# shaped like `kubectl get -o json`, and `kubectl top pods` text.

load helpers

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    cat > "$FX/nodes.json" <<'JSON'
{"apiVersion":"v1","kind":"List","items":[
{"kind":"Node","metadata":{"name":"k8s-master","creationTimestamp":"2026-08-19T10:00:00Z","labels":{"node-role.kubernetes.io/control-plane":""}},"spec":{},"status":{"allocatable":{"cpu":"2","memory":"3880Mi","pods":"110"},"capacity":{"cpu":"2","memory":"3982Mi"},"conditions":[{"type":"MemoryPressure","status":"False"},{"type":"DiskPressure","status":"False"},{"type":"PIDPressure","status":"False"},{"type":"Ready","status":"True","reason":"KubeletReady","message":"kubelet is posting ready status"}],"nodeInfo":{"kubeletVersion":"v1.35.2"}}},
{"kind":"Node","metadata":{"name":"k8s-worker-1","creationTimestamp":"2026-08-19T10:05:00Z","labels":{}},"spec":{},"status":{"allocatable":{"cpu":"2","memory":"3880Mi"},"conditions":[{"type":"MemoryPressure","status":"False"},{"type":"Ready","status":"True"}],"nodeInfo":{"kubeletVersion":"v1.35.2"}}},
{"kind":"Node","metadata":{"name":"k8s-worker-2","creationTimestamp":"2026-08-19T10:05:00Z","labels":{}},"spec":{},"status":{"allocatable":{"cpu":"2","memory":"3880Mi"},"conditions":[{"type":"MemoryPressure","status":"True","reason":"KubeletHasInsufficientMemory","message":"kubelet has insufficient memory available","lastTransitionTime":"2026-09-29T09:09:00Z"},{"type":"Ready","status":"True"}],"nodeInfo":{"kubeletVersion":"v1.35.2"}}}
]}
JSON
    jq '{kind: "List", items: [.items[0]]}' "$FX/nodes.json" > "$FX/one.json"
    jq '.items[0].spec.taints = [{key: "node-role.kubernetes.io/control-plane", effect: "NoSchedule"}]
        | .items[1].spec.taints = [{key: "dedicated", value: "db", effect: "NoSchedule"},
            {key: "gpu", effect: "PreferNoSchedule"},
            {key: "node.kubernetes.io/unschedulable", effect: "NoSchedule"}]
        | .items[2].spec.taints = [{key: "node-role.kubernetes.io/control-plane", effect: "NoSchedule"}]
        | .items[2].status.conditions[0].status = "False"' "$FX/nodes.json" > "$FX/tainted.json"
    jq '.items[1].status.conditions[1] = {type: "Ready", status: "Unknown", reason: "NodeStatusUnknown",
        message: "Kubelet stopped posting node status.", lastTransitionTime: "2026-09-29T09:00:00Z"}
        | .items[1].spec.unschedulable = true' "$FX/nodes.json" > "$FX/down.json"
    local now
    now=$(date -u +%FT%TZ)
    jq -n --arg now "$now" '{kind: "List", items: [
        {kind: "Event", metadata: {name: "e1", namespace: "monitoring"}, reason: "Evicted", type: "Warning",
         involvedObject: {kind: "Pod", name: "prometheus-1"}, source: {component: "kubelet", host: "k8s-worker-2"},
         message: "The node was low on resource: memory.", lastTimestamp: $now},
        {kind: "Event", metadata: {name: "e2", namespace: "shop"}, reason: "Evicted", type: "Warning",
         involvedObject: {kind: "Pod", name: "report-1"}, source: {component: "kubelet", host: "k8s-worker-2"},
         message: "The node was low on resource: memory.", lastTimestamp: $now},
        {kind: "Event", metadata: {name: "e3", namespace: "shop"}, reason: "Evicted", type: "Warning",
         involvedObject: {kind: "Pod", name: "old-1"}, source: {component: "kubelet", host: "k8s-worker-2"},
         message: "old", lastTimestamp: "2026-09-01T00:00:00Z"}]}' > "$FX/evicted.json"
    cat > "$FX/onnode.json" <<'JSON'
{"kind":"List","items":[
{"metadata":{"name":"prometheus-0","namespace":"monitoring","labels":{}}},
{"metadata":{"name":"loki-0","namespace":"monitoring","labels":{}}},
{"metadata":{"name":"api-5b8c9d7f6-2wq8d","namespace":"shop","labels":{"pod-template-hash":"5b8c9d7f6"}}},
{"metadata":{"name":"tiny-0","namespace":"shop","labels":{}}}
]}
JSON
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case " $* " in
    *" config view "*) printf 'kind-kind\tshop' ;;
    *" get nodes "*) cat "$FX/${NODES:-nodes}.json" ;;
    *" get events "*) cat "$FX/evicted.json" ;;
    *" get pods -A "*) cat "$FX/onnode.json" ;;
    *" top pods "*)
        [[ -n ${NOMETRICS:-} ]] && { echo "error: Metrics API not available" >&2; exit 1; }
        printf 'monitoring   prometheus-0   610m   1946Mi\nmonitoring   loki-0   240m   820Mi\n'
        printf 'shop   api-5b8c9d7f6-2wq8d   180m   210Mi\nshop   tiny-0   1m   12Mi\nshop   elsewhere-0   1m   3000Mi\n' ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

@test "help prints usage and exits 0" {
    run knodes --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usage: knodes [NODE] [-- kubectl options]" ]
}

@test "bad usage exits 2" {
    run knodes a b
    [ "$status" -eq 2 ]
    run knodes --nope
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run knodes
    [ "$status" -eq 3 ]
    [[ $output == "knodes: needs kubectl."* ]]
}

@test "a node under pressure gets a detail block and exit 1" {
    run knodes
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "NODE           STATUS  ROLE           AGE  VERSION  CONDITIONS" ]
    [[ ${lines[1]} == "k8s-master     Ready   control-plane  "*"d  v1.35.2  ok" ]]
    [[ ${lines[3]} == "k8s-worker-2   Ready   worker         "*"  v1.35.2  MemoryPressure" ]]
    [[ ${lines[4]} == "k8s-worker-2   MemoryPressure since "* ]]
    [ "${lines[5]}" = "  kubelet  has insufficient memory available" ]
    [ "${lines[6]}" = "  evicted  2 pods in the last hour" ]
    [ "${lines[7]}" = "  top      prometheus-0 1.9Gi, loki-0 820Mi, api-2wq8d 210Mi" ]
    grep -q -- "get pods -A --field-selector spec.nodeName=k8s-worker-2 -o json" "$CALLS"
    grep -q -- "get events -A --field-selector reason=Evicted -o json" "$CALLS"
}

@test "without metrics the top line is left out" {
    NOMETRICS=1 run knodes
    [ "$status" -eq 1 ]
    [[ $output == *"evicted  2 pods"* ]]
    [[ $output != *"  top "* ]]
}

@test "-q prints only the table" {
    run knodes -q
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 4 ]
}

@test "all normal drops the conditions column and exits 0" {
    NODES=one run knodes
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "NODE         STATUS  ROLE           AGE  VERSION" ]
    [[ ${lines[1]} == "k8s-master   Ready   control-plane  "*"  v1.35.2" ]]
    [ "${lines[2]}" = "all conditions normal" ]
    not grep -q "get events" "$CALLS"
}

@test "a NotReady, cordoned node shows the kubelet message" {
    NODES=down run knodes k8s-worker-1
    [ "$status" -eq 1 ]
    [[ ${lines[1]} == "k8s-worker-1   NotReady,SchedulingDisabled  worker"*"NotReady" ]]
    [[ ${lines[2]} == "k8s-worker-1   NotReady since "* ]]
    [ "${lines[3]}" = "  message  Kubelet stopped posting node status." ]
}

@test "naming a node shows only that one" {
    run knodes k8s-master
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "an unknown node exits 1 and lists the nodes" {
    run knodes k8s-worker-3
    [ "$status" -eq 1 ]
    [ "$output" = "knodes: no node k8s-worker-3. Nodes are k8s-master, k8s-worker-1 and k8s-worker-2" ]
}

@test "pass-through options reach kubectl" {
    run knodes -- --context kind-kind
    grep -q -- "get nodes -o json --context kind-kind" "$CALLS"
    grep -q -- "top pods -A --no-headers --context kind-kind" "$CALLS"
}

@test "taints get a line each, except the expected ones" {
    NODES=tainted run knodes
    [ "$status" -eq 0 ]
    [ "${lines[4]}" = "taint  k8s-worker-1  dedicated=db:NoSchedule" ]
    [ "${lines[5]}" = "taint  k8s-worker-1  gpu:PreferNoSchedule" ]
    # The control-plane taint shows only on a node without the control-plane role.
    [ "${lines[6]}" = "taint  k8s-worker-2  node-role.kubernetes.io/control-plane:NoSchedule" ]
    [ "${lines[7]}" = "all conditions normal" ]
    [ "${#lines[@]}" -eq 8 ]
}

@test "naming a node shows only its taints, -q none" {
    NODES=tainted run knodes k8s-worker-1
    [ "${#lines[@]}" -eq 5 ]
    [ "${lines[2]}" = "taint  k8s-worker-1  dedicated=db:NoSchedule" ]
    NODES=tainted run knodes -q
    [ "${#lines[@]}" -eq 4 ]
}
