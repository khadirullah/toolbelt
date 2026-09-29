#!/usr/bin/env bats
# Tests for kwhy. kubectl is a stub that prints small JSON shaped like
# `kubectl get pods -o json`, so no cluster is needed.

load helpers

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    cat > "$FX/pods.json" <<'JSON'
{"apiVersion":"v1","kind":"List","items":[
{"apiVersion":"v1","kind":"Pod","metadata":{"name":"cart-7d9f8c6b54-q2lzx","namespace":"shop","labels":{"pod-template-hash":"7d9f8c6b54"}},
 "spec":{"containers":[{"name":"cart","image":"registry.example.com/cart:1.4.3","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}],"nodeName":"kind-control-plane"},
 "status":{"phase":"Pending","conditions":[{"type":"PodScheduled","status":"True"},{"type":"Ready","status":"False","reason":"ContainersNotReady"}],
  "containerStatuses":[{"name":"cart","ready":false,"restartCount":0,"image":"registry.example.com/cart:1.4.3","imageID":"","started":false,
   "state":{"waiting":{"reason":"ImagePullBackOff","message":"Back-off pulling image \"registry.example.com/cart:1.4.3\""}},"lastState":{}}]}},
{"apiVersion":"v1","kind":"Pod","metadata":{"name":"api-5b8c9d7f6-mk4tn","namespace":"shop"},
 "spec":{"containers":[{"name":"api","image":"registry.example.com/api:2.3.0"}]},
 "status":{"phase":"Running","conditions":[{"type":"PodScheduled","status":"True"},{"type":"Ready","status":"False"}],
  "containerStatuses":[{"name":"api","ready":false,"restartCount":9,"image":"registry.example.com/api:2.3.0",
   "state":{"waiting":{"reason":"CrashLoopBackOff","message":"back-off 5m0s restarting failed container=api pod=api-5b8c9d7f6-mk4tn_shop(1f0c)"}},
   "lastState":{"terminated":{"exitCode":1,"reason":"Error","startedAt":"2026-09-29T09:12:03Z","finishedAt":"2026-09-29T09:12:04Z"}}}]}},
{"apiVersion":"v1","kind":"Pod","metadata":{"name":"worker-6c7b9f5d8-8vhwp","namespace":"shop"},
 "spec":{"containers":[{"name":"worker","image":"registry.example.com/worker:1.0","resources":{"requests":{"cpu":"2","memory":"1Gi"}}}]},
 "status":{"phase":"Pending","conditions":[{"type":"PodScheduled","status":"False","reason":"Unschedulable","message":"0/1 nodes are available: 1 Insufficient cpu. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod."}],"qosClass":"Burstable"}},
{"apiVersion":"v1","kind":"Pod","metadata":{"name":"web-6d4cf56db6-xk2p9","namespace":"shop"},
 "spec":{"containers":[{"name":"web","image":"nginx:1.27"}]},
 "status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}],
  "containerStatuses":[{"name":"web","ready":true,"restartCount":0,"state":{"running":{"startedAt":"2026-09-29T08:00:00Z"}},"lastState":{}}]}}
]}
JSON
    cat > "$FX/events-api.json" <<'JSON'
{"apiVersion":"v1","kind":"List","items":[
{"kind":"Event","metadata":{"name":"api.1","namespace":"shop","creationTimestamp":"2026-09-29T09:00:00Z"},"involvedObject":{"kind":"Pod","name":"api-5b8c9d7f6-mk4tn","namespace":"shop"},"reason":"Pulled","message":"Container image \"registry.example.com/api:2.3.0\" already present on machine","type":"Normal","lastTimestamp":"2026-09-29T09:12:02Z","count":10},
{"kind":"Event","metadata":{"name":"api.2","namespace":"shop","creationTimestamp":"2026-09-29T09:00:00Z"},"involvedObject":{"kind":"Pod","name":"api-5b8c9d7f6-mk4tn","namespace":"shop"},"reason":"BackOff","message":"Back-off restarting failed container api in pod api-5b8c9d7f6-mk4tn_shop(1f0c)","type":"Warning","lastTimestamp":"2026-09-29T09:12:04Z","count":41}
]}
JSON
    cat > "$FX/events-cart.json" <<'JSON'
{"apiVersion":"v1","kind":"List","items":[
{"kind":"Event","metadata":{"name":"cart.1","namespace":"shop"},"involvedObject":{"kind":"Pod","name":"cart-7d9f8c6b54-q2lzx","namespace":"shop"},"reason":"Failed","message":"Failed to pull image \"registry.example.com/cart:1.4.3\": rpc error: code = NotFound desc = failed to pull and unpack image \"registry.example.com/cart:1.4.3\": manifest unknown","type":"Warning","lastTimestamp":"2026-09-29T09:02:14Z","count":4}
]}
JSON
    jq '{kind: "List", items: [.items[3]]}' "$FX/pods.json" > "$FX/ready.json"
    jq '.items[1]' "$FX/pods.json" > "$FX/api.json"
    # web keeps its old Ready container when its node stops answering.
    jq '.items[1].spec.nodeName = "kind-worker" | .items[3].spec.nodeName = "kind-worker"
        | .items[3].status.conditions[0].status = "False"' "$FX/pods.json" > "$FX/lost.json"
    jq -n --arg t "$(date -u -d @$(( $(date +%s) - 180 )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
        date -u -r $(( $(date +%s) - 180 )) +%Y-%m-%dT%H:%M:%SZ)" '{kind: "List", items: [
        {metadata: {name: "kind-control-plane"}, status: {conditions: [{type: "Ready", status: "True"}]}},
        {metadata: {name: "kind-worker"}, status: {conditions: [{type: "Ready", status: "Unknown",
         lastTransitionTime: $t}]}}]}' > "$FX/nodes.json"
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
if [[ -n ${KUBE_ERR:-} ]]; then echo "$KUBE_ERR" >&2; exit 1; fi
case " $* " in
    *" config view "*) printf 'kind-kind\tshop'; exit 0 ;;
    *" get events "*)
        case " $* " in
            *involvedObject.name=api-*) cat "$FX/events-api.json" ;;
            *involvedObject.name=cart-*) cat "$FX/events-cart.json" ;;
            *) echo '{"apiVersion":"v1","kind":"List","items":[]}' ;;
        esac ;;
    *" get pod nosuch "*)
        echo 'Error from server (NotFound): pods "nosuch" not found' >&2; exit 1 ;;
    *" get pod api-5b8c9d7f6-mk4tn "*) cat "$FX/api.json" ;;
    *" get pod web-6d4cf56db6-xk2p9 "*) jq '.items[0]' "$FX/ready.json" ;;
    *" get nodes "*)
        [[ -n ${NODES:-} ]] || { echo 'Error from server (Forbidden): nodes is forbidden' >&2; exit 1; }
        cat "$FX/$NODES.json" ;;
    *" get pods "*) cat "$FX/${PODS:-pods}.json" ;;
    *" logs "*)
        printf '09:12:04 INFO  loading config\n09:12:04 ERROR DATABASE_URL is not set\npanic: missing DATABASE_URL\n' ;;
esac
exit 0
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

@test "help prints usage and exits 0" {
    run kwhy --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: kwhy "* ]]
}

@test "bad usage exits 2" {
    run kwhy --nope
    [ "$status" -eq 2 ]
    run kwhy --lines x
    [ "$status" -eq 2 ]
    run kwhy -A -n shop
    [ "$status" -eq 2 ]
    run kwhy -A web-1
    [ "$status" -eq 2 ]
    run kwhy -n
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run kwhy
    [ "$status" -eq 3 ]
    [[ $output == "kwhy: needs kubectl."* ]]
}

@test "missing jq exits 3" {
    tb_without jq
    run kwhy
    [ "$status" -eq 3 ]
    [[ $output == "kwhy: needs jq."* ]]
}

@test "explains each pod that is not Ready and exits 1" {
    run kwhy --lines 3
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "context kind-kind, namespace shop, 3 of 4 pods not Ready" ]
    [[ $output == *"cart-7d9f8c6b54-q2lzx"*"ImagePullBackOff"*"restarts 0"* ]]
    [[ $output == *"  image  registry.example.com/cart:1.4.3"* ]]
    [[ $output == *"hint   the tag does not exist, or the pull secret is wrong"* ]]
    [[ $output == *"api-5b8c9d7f6-mk4tn"*"CrashLoopBackOff"*"restarts 9"* ]]
    [[ $output == *"  event  Back-off restarting failed container api"* ]]
    [[ $output == *"  exit   1, "*" ago, last 3 lines of the crashed container"* ]]
    [[ $output == *"    09:12:04 ERROR DATABASE_URL is not set"* ]]
    [[ $output == *"  event  0/1 nodes are available: 1 Insufficient cpu."* ]]
    [[ $output != *preemption* ]]
    [[ $output == *"  asks   cpu 2, memory 1Gi"* ]]
    [[ $output != *web-6d4cf56db6* ]]
}

@test "reads the crashed container's logs with --previous and -c" {
    run kwhy --lines 3
    grep -q -- "kubectl logs api-5b8c9d7f6-mk4tn -n shop -c api --tail 3 --previous" "$CALLS"
    grep -q -- "get events -n shop --field-selector involvedObject.name=api-5b8c9d7f6-mk4tn -o json" "$CALLS"
}

@test "--lines 0 skips the logs" {
    run kwhy --lines 0
    [ "$status" -eq 1 ]
    ! grep -q "kubectl logs" "$CALLS"
    [[ $output == *"  exit   1, "*" ago"* ]]
}

@test "every pod Ready exits 0" {
    PODS=ready run kwhy
    [ "$status" -eq 0 ]
    [ "$output" = "context kind-kind, namespace shop, 1 pod Ready" ]
}

@test "-A counts namespaces and prefixes names" {
    PODS=ready run kwhy -A
    [ "$status" -eq 0 ]
    [ "$output" = "context kind-kind, 1 pod Ready in 1 namespace" ]
    run kwhy -A -q
    [[ $output == *"shop/api-5b8c9d7f6-mk4tn"* ]]
    grep -q -- "get pods -o json -A" "$CALLS"
}

@test "-q prints one line per pod" {
    run kwhy -q
    [ "$status" -eq 1 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ $output != *event* ]]
}

@test "named pods show even when Ready" {
    run kwhy web-6d4cf56db6-xk2p9
    [ "$status" -eq 0 ]
    [[ $output == *"web-6d4cf56db6-xk2p9"*"Ready"*"restarts 0"* ]]
    run kwhy -q api-5b8c9d7f6-mk4tn
    [ "$status" -eq 1 ]
    [[ $output == "api-5b8c9d7f6-mk4tn"*"CrashLoopBackOff"* ]]
}

@test "a pod that does not exist exits 1" {
    run kwhy nosuch
    [ "$status" -eq 1 ]
    [[ $output == *"kwhy: no pod nosuch in shop"* ]]
}

@test "pass-through options reach every kubectl call" {
    run kwhy --lines 1 -- --context kind-kind
    grep -q -- "get pods -o json -n shop --context kind-kind" "$CALLS"
    grep -q -- "logs .* --context kind-kind" "$CALLS"
    grep -q -- "config view --minify --context kind-kind" "$CALLS"
}

@test "an unreachable cluster exits 1 with a hint" {
    KUBE_ERR='E0929 dial tcp 127.0.0.1:38211: connect: connection refused
The connection to the server 127.0.0.1:38211 was refused - did you specify the right host or port?' run kwhy
    [ "$status" -eq 1 ]
    [[ $output == *"kwhy: cannot reach the cluster for context "* ]]
}

@test "kind contexts get the kind hint" {
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
case " $* " in
    *" config view "*) printf 'kind-kind\t' ;;
    *) echo "The connection to the server 127.0.0.1:38211 was refused - did you specify the right host or port?" >&2; exit 1 ;;
esac
SH
    run kwhy
    [ "$status" -eq 1 ]
    [[ $output == *"cannot reach the cluster for context kind-kind"* ]]
    [[ $output == *"Try: kind get clusters"* ]]
}

@test "a stopped container shows its own log, not the one before" {
    jq '.status.containerStatuses[0].state = {terminated: {exitCode: 1, reason: "Error", finishedAt: "2026-09-29T09:13:00Z"}}' \
        "$FX/api.json" > "$FX/api-stopped.json"
    sed -i 's|cat "$FX/api.json"|cat "$FX/${API:-api}.json"|' "$BATS_TEST_TMPDIR/stubs/kubectl"
    API=api-stopped run kwhy api-5b8c9d7f6-mk4tn
    grep 'logs api-5b8c9d7f6-mk4tn' "$CALLS" | grep -vq -- '--previous'
    [[ $output == *"  event  Back-off restarting failed container api"$'\n'* ]]
    [[ $output == *"    panic: missing DATABASE_URL"* ]]
}

@test "logs the node already removed get a plain message" {
    sed -i 's|        printf .09:12:04 INFO.*|        printf "unable to retrieve container logs for containerd://abc" ;;|' "$BATS_TEST_TMPDIR/stubs/kubectl"
    run kwhy api-5b8c9d7f6-mk4tn
    [[ $output == *"    the node no longer keeps that container's logs"$'\n'"  hint   "* ]]
}

@test "a NotReady node is named once and its pods blame it" {
    PODS=lost NODES=nodes run kwhy
    [ "$status" -eq 1 ]
    [ "${lines[1]}" = "node kind-worker is NotReady since 3m, 2 pods on it, see knodes" ]
    [[ $output == *"  exit   1, "*" ago"$'\n'"  logs   not readable while the node is NotReady"$'\n'"  hint   fix the node first"* ]]
    [[ $output == *"web-6d4cf56db6-xk2p9     not Ready          restarts 0"$'\n'"  hint   the node is NotReady, the pod may be fine"* ]]
    # cart is on a Ready node and keeps its own hint.
    [[ $output == *"  hint   the tag does not exist, or the pull secret is wrong"* ]]
    [ -z "$(grep ' logs ' "$CALLS")" ]
}

@test "a login that cannot list nodes changes nothing" {
    PODS=lost run kwhy
    [ "$status" -eq 1 ]
    [[ $output != *"NotReady"* ]]
    [[ $output == *"web-6d4cf56db6-xk2p9     Running 1/1"* ]]
    grep -q ' logs api-' "$CALLS"
}
