#!/usr/bin/env bats
# Tests for kres. kubectl is a stub that prints nodes and pods shaped like
# `kubectl get -o json`, and `kubectl top` text.

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
    cat > "$FX/pods.json" <<'JSON'
{"kind":"List","items":[{"metadata":{"name":"kube-apiserver-k8s-master","namespace":"kube-system"},"spec":{"nodeName":"k8s-master","containers":[{"name":"c","resources":{"requests":{"cpu":"250m","memory":"0"}}}]}},{"metadata":{"name":"etcd-k8s-master","namespace":"kube-system"},"spec":{"nodeName":"k8s-master","containers":[{"name":"c","resources":{"requests":{"cpu":"100m","memory":"100Mi"}}}]}},{"metadata":{"name":"coredns-1","namespace":"kube-system"},"spec":{"nodeName":"k8s-master","containers":[{"name":"c","resources":{"requests":{"cpu":"100m","memory":"70Mi"}}}]}},{"metadata":{"name":"api-5b8c9d7f6-2wq8d","namespace":"shop"},"spec":{"nodeName":"k8s-worker-1","containers":[{"name":"c","resources":{"requests":{"cpu":"1500m","memory":"3Gi"}}}],"initContainers":[{"name":"i","resources":{"requests":{"cpu":"1800m"}}}]}},{"metadata":{"name":"prometheus-0","namespace":"monitoring"},"spec":{"nodeName":"k8s-worker-2","containers":[{"name":"c","resources":{"requests":{"cpu":"200m","memory":"512Mi"}}}]}},{"metadata":{"name":"loki-0","namespace":"monitoring"},"spec":{"nodeName":"k8s-worker-2","containers":[{"name":"c","resources":{"requests":{"cpu":"100m","memory":"256Mi"}}}]}}]}
JSON
    printf 'k8s-master     410m   20%%   2356Mi   60%%\nk8s-worker-1   620m   31%%   2100Mi   54%%\nk8s-worker-2   1400m  70%%   3500Mi   90%%\n' > "$FX/topnodes.txt"
    printf 'monitoring   prometheus-0   610m   1946Mi\nmonitoring   loki-0   90m   200Mi\nshop   api-5b8c9d7f6-2wq8d   180m   210Mi\n' > "$FX/toppods.txt"
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case " $* " in
    *" config view "*) printf 'kind-kind\tshop' ;;
    *" get nodes "*) cat "$FX/nodes.json" ;;
    *" get pods -A "*spec.nodeName=k8s-worker-2*)
        jq '{kind: "List", items: [.items[] | select(.spec.nodeName == "k8s-worker-2")]}' "$FX/pods.json" ;;
    *" get pods -A "*) cat "$FX/pods.json" ;;
    *" top "*)
        if [[ -n ${NOMETRICS:-} ]]; then echo "error: Metrics API not available" >&2; exit 1; fi
        if [[ $* == *nodes* ]]; then cat "$FX/topnodes.txt"; else cat "$FX/toppods.txt"; fi ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

@test "help prints usage and exits 0" {
    run kres -h
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: kres "* ]]
}

@test "bad usage exits 2" {
    run kres --sort disk
    [ "$status" -eq 2 ]
    run kres k8s-master
    [ "$status" -eq 2 ]
    run kres --pods
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run kres
    [ "$status" -eq 3 ]
    [[ $output == "kres: needs kubectl."* ]]
}

@test "one row per node with requests and usage" {
    run kres
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "context kind-kind, 3 nodes" ]
    [ "${lines[2]}" = "NODE          requests   used       requests    used" ]
    [ "${lines[3]}" = "k8s-master    450m 23%   410m 21%   170Mi 4%    2.3Gi 61%" ]
    [ "${lines[4]}" = "k8s-worker-1  1.8 90%    620m 31%   3.0Gi 79%   2.1Gi 54%" ]
    [ "${lines[6]}" = "! k8s-worker-1 has 90% of its cpu requested, new pods" ]
    [ "${lines[7]}" = "  asking for more than 200m will stay Pending there" ]
    grep -q -- "get pods -A --field-selector status.phase!=Succeeded,status.phase!=Failed -o json" "$CALLS"
    grep -q -- "top nodes --no-headers" "$CALLS"
}

@test "--sort mem puts the fullest node first, -q drops the extras" {
    run kres --sort mem -q
    [ "${lines[2]%% *}" = "k8s-worker-1" ]
    [ "${lines[4]%% *}" = "k8s-master" ]
    [[ $output != *context* ]]
    [[ $output != *"!"* ]]
}

@test "no metrics API leaves usage empty and still exits 0" {
    NOMETRICS=1 run kres
    [ "$status" -eq 0 ]
    [ "${lines[3]}" = "k8s-master    450m 23%   -          170Mi 4%    -" ]
    [[ $output == *"kres: no metrics API, usage columns are empty."* ]]
    [[ $output == *"kres: install metrics-server to fill them."* ]]
}

@test "--pods breaks one node down and flags heavy users" {
    run kres --pods k8s-worker-2
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "context kind-kind, node k8s-worker-2, 2 pods" ]
    [ "${lines[1]}" = "POD                      CPU req  used   MEM req  used" ]
    [ "${lines[2]}" = "monitoring/prometheus-0  200m     610m   512Mi    1.9Gi" ]
    [[ $output == *"! prometheus-0 uses 1.9Gi against a 512Mi memory request"* ]]
    [[ $output != *"! loki-0"* ]]
    grep -q -- "spec.nodeName=k8s-worker-2" "$CALLS"
}

@test "an unknown node exits 1 and lists the nodes" {
    run kres --pods k8s-worker-3
    [ "$status" -eq 1 ]
    [ "$output" = "kres: no node k8s-worker-3. Nodes are k8s-master, k8s-worker-1 and k8s-worker-2" ]
}

@test "pass-through options reach every kubectl call" {
    run kres -- --context kind-kind
    [ "$(grep -c -- '--context kind-kind' "$CALLS")" -eq 4 ]
}
