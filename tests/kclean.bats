#!/usr/bin/env bats
# Tests for kclean. kubectl is a stub that prints a pod list shaped like
# `kubectl get pods -o json` and logs every delete to a file.

load helpers

# A pod: namespace name kind [owner-rs] [hash].
pod() {
    local ns=$1 name=$2 kind=$3 rs=${4:-} hash=${5:-} status owner='[]'
    case $kind in
        evicted)   status='{"phase":"Failed","reason":"Evicted","message":"The node was low on resource: memory."}' ;;
        completed) status='{"phase":"Succeeded","containerStatuses":[{"name":"c","ready":false,"restartCount":0,"state":{"terminated":{"exitCode":0,"reason":"Completed"}}}]}' ;;
        crashloop) status='{"phase":"Running","containerStatuses":[{"name":"c","ready":false,"restartCount":9,"state":{"waiting":{"reason":"CrashLoopBackOff"}},"lastState":{"terminated":{"exitCode":1}}}]}' ;;
        running)   status='{"phase":"Running","containerStatuses":[{"name":"c","ready":true,"restartCount":0,"state":{"running":{}}}]}' ;;
    esac
    [[ -n $rs ]] && owner="[{\"apiVersion\":\"apps/v1\",\"kind\":\"ReplicaSet\",\"name\":\"$rs\",\"controller\":true}]"
    printf '{"apiVersion":"v1","kind":"Pod","metadata":{"name":"%s","namespace":"%s","labels":{"pod-template-hash":"%s"},"ownerReferences":%s},"spec":{},"status":%s}' \
        "$name" "$ns" "$hash" "$owner" "$status"
}

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    {
        printf '{"apiVersion":"v1","kind":"List","items":['
        pod shop report-28790640-7xk2p evicted; printf ,
        pod shop report-28790700-lq9ds evicted; printf ,
        pod shop report-28790760-p8wzc evicted; printf ,
        pod shop migrate-2kx9d completed; printf ,
        pod shop backup-28790520-mn4zz completed; printf ,
        pod shop backup-28790580-q7c2x completed; printf ,
        pod shop backup-28790640-t9w3d completed; printf ,
        pod shop backup-28790700-h4k8s completed; printf ,
        pod shop api-5b8c9d7f6-mk4tn crashloop api-5b8c9d7f6 5b8c9d7f6; printf ,
        pod shop web-6d4cf56db6-xk2p9 running web-6d4cf56db6 6d4cf56db6; printf ,
        pod monitoring prometheus-server-7c9d5b8f4-2xkqp evicted; printf ,
        pod kube-system coredns-668d6bf9bc-4wz5m evicted
        printf ']}\n'
    } > "$FX/all.json"
    jq '{kind: "List", items: [.items[] | select(.metadata.namespace == "shop")]}' "$FX/all.json" > "$FX/shop.json"
    jq '{kind: "List", items: [.items[] | select(.metadata.namespace == "kube-system")]}' "$FX/all.json" > "$FX/kube-system.json"
    echo '{"kind":"List","items":[]}' > "$FX/empty.json"
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case " $* " in
    *" config view "*) printf 'kind-kind\tshop' ;;
    *" get pods -A "*) cat "$FX/all.json" ;;
    *" get pods -n "*) cat "$FX/${4}.json" 2>/dev/null || cat "$FX/empty.json" ;;
    *" delete pod "*)
        echo "$*" >> "$BATS_TEST_TMPDIR/deleted"
        shift 5
        for p in "$@"; do [[ $p == -* ]] && break; echo "pod \"$p\" deleted"; done ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

@test "help prints usage and exits 0" {
    run kclean --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: kclean "* ]]
}

@test "bad usage exits 2" {
    run kclean --only broken
    [ "$status" -eq 2 ]
    run kclean -A -n shop
    [ "$status" -eq 2 ]
    run kclean some-pod
    [ "$status" -eq 2 ]
    run kclean --only
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run kclean
    [ "$status" -eq 3 ]
    [[ $output == "kclean: needs kubectl."* ]]
}

@test "lists evicted, completed and crashing pods" {
    run kclean -y
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "context kind-kind, namespace shop" ]
    [ "${lines[1]}" = "evicted    3  report-28790640-7xk2p report-28790700-lq9ds" ]
    [ "${lines[2]}" = "              report-28790760-p8wzc" ]
    [ "${lines[3]}" = "completed  5  migrate-2kx9d backup-28790520-mn4zz and 3 more" ]
    [ "${lines[4]}" = "crashloop  1  api-5b8c9d7f6-mk4tn, restarts 9, owned by deploy/api" ]
    [ "${lines[5]}" = "deleted 9 pods" ]
    [[ $output != *web-6d4cf56db6* ]]
}

@test "deletes in one call per namespace, never a running pod" {
    run kclean -y
    [ "$(wc -l < "$BATS_TEST_TMPDIR/deleted")" -eq 1 ]
    grep -q "^delete pod -n shop --ignore-not-found report-28790640-7xk2p" "$BATS_TEST_TMPDIR/deleted"
    grep -q "api-5b8c9d7f6-mk4tn" "$BATS_TEST_TMPDIR/deleted"
    not grep -q "web-6d4cf56db6" "$BATS_TEST_TMPDIR/deleted"
}

@test "answering no deletes nothing and exits 5" {
    tb_tty
    run bash -c 'echo n | kclean'
    [ "$status" -eq 5 ]
    [[ $output == *"Delete 9 pods in shop? They cannot be restored. [y/N]"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/deleted" ]
}

@test "answering yes deletes" {
    tb_tty
    run bash -c 'echo y | kclean -q'
    [ "$status" -eq 0 ]
    [[ $output == *"deleted 9 pods" ]]
    [ -e "$BATS_TEST_TMPDIR/deleted" ]
}

@test "no terminal and no --yes refuses with 4" {
    run kclean
    [ "$status" -eq 4 ]
    [[ $output == *"evicted    3"* ]]
    [[ $output == *"pass --yes"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/deleted" ]
}

@test "--only keeps one kind" {
    run kclean -y --only completed
    [[ $output != *evicted* ]]
    [[ $output == *"deleted 5 pods"* ]]
    run kclean -y --only evicted --only crashloop
    [[ $output == *"deleted 4 pods"* ]]
}

@test "-A skips kube-system unless --system" {
    run kclean -A -y -v --only evicted
    [[ $output == *"context kind-kind, all namespaces, kube-system skipped"* ]]
    [[ $output == *"monitoring/prometheus-server-7c9d5b8f4-2xkqp"* ]]
    [[ $output != *coredns* ]]
    [[ $output == *"deleted 4 pods"* ]]
    grep -q -- "delete pod -n monitoring" "$BATS_TEST_TMPDIR/deleted"
    run kclean -A -y -v --system --only evicted
    [[ $output == *coredns* ]]
}

@test "-n kube-system needs --system" {
    run kclean -n kube-system -y
    [ "$status" -eq 4 ]
    [[ $output == *"Add --system"* ]]
    run kclean -n kube-system --system -y
    [ "$status" -eq 0 ]
}

@test "nothing to clean exits 0" {
    run kclean -n quiet -y
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "nothing to clean in quiet" ]
}

@test "--dry-run=client passes through and skips the question" {
    run kclean -n shop -- --dry-run=client
    [ "$status" -eq 0 ]
    [[ $output == *"dry run, 9 pods would be deleted"* ]]
    grep -q -- "--dry-run=client" "$BATS_TEST_TMPDIR/deleted"
    not grep -q "get pods .*--dry-run" "$CALLS"
}

@test "-v lists every name" {
    run kclean -v -y --only completed
    [[ $output == *"backup-28790700-h4k8s"* ]]
    [[ $output == *"+ kubectl delete pod -n shop --ignore-not-found"* ]]
}
