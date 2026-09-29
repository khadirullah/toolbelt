#!/usr/bin/env bats
# Tests for kyaml. kubectl is a stub that prints YAML shaped like
# `kubectl get -o yaml`, with the fields the cluster adds.

load helpers

setup() {
    tb_setup
    export FX=$BATS_TEST_TMPDIR/fx CALLS=$BATS_TEST_TMPDIR/calls
    mkdir -p "$FX"
    : > "$CALLS"
    cat > "$FX/deploy.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "3"
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"apps/v1","kind":"Deployment","metadata":{"annotations":{},"name":"api","namespace":"shop"}}
  creationTimestamp: "2026-09-20T08:14:02Z"
  generation: 3
  labels:
    app: api
  managedFields:
  - apiVersion: apps/v1
    fieldsType: FieldsV1
    fieldsV1:
      f:spec:
        f:replicas: {}
    manager: kubectl-client-side-apply
    operation: Update
    time: "2026-09-20T08:14:02Z"
  name: api
  namespace: shop
  resourceVersion: "48213"
  uid: 3f6c1d2e-8a4b-4c1e-9f0a-2b7d5e6c8a91
spec:
  progressDeadlineSeconds: 600
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - image: registry.example.com/api:2.3.0
        name: api
        ports:
        - containerPort: 8080
          protocol: TCP
status:
  availableReplicas: 2
  conditions:
  - lastTransitionTime: "2026-09-20T08:14:10Z"
    message: Deployment has minimum availability.
    reason: MinimumReplicasAvailable
    status: "True"
    type: Available
  observedGeneration: 3
  readyReplicas: 2
  replicas: 2
YAML
    cat > "$FX/svc.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  annotations:
    example.com/owner: shop-team
  creationTimestamp: "2026-09-20T08:14:02Z"
  labels:
    app: api
  name: api
  namespace: shop
  resourceVersion: "48190"
  uid: 7b1e2c3d-4f5a-6b7c-8d9e-0f1a2b3c4d5e
spec:
  clusterIP: 10.96.141.22
  clusterIPs:
  - 10.96.141.22
  internalTrafficPolicy: Cluster
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: api
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
YAML
    cat > "$FX/job.yaml" <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  creationTimestamp: "2026-09-29T10:02:11Z"
  generation: 1
  labels:
    batch.kubernetes.io/controller-uid: 5d1c0e2a-1b2c-4d3e-8f4a-9b0c1d2e3f4a
    batch.kubernetes.io/job-name: once
    controller-uid: 5d1c0e2a-1b2c-4d3e-8f4a-9b0c1d2e3f4a
    job-name: once
  name: once
  namespace: shop
spec:
  backoffLimit: 6
  selector:
    matchLabels:
      batch.kubernetes.io/controller-uid: 5d1c0e2a-1b2c-4d3e-8f4a-9b0c1d2e3f4a
  template:
    metadata:
      labels:
        batch.kubernetes.io/controller-uid: 5d1c0e2a-1b2c-4d3e-8f4a-9b0c1d2e3f4a
        batch.kubernetes.io/job-name: once
        controller-uid: 5d1c0e2a-1b2c-4d3e-8f4a-9b0c1d2e3f4a
        job-name: once
    spec:
      containers:
      - command:
        - echo
        - done
        image: busybox:1.37
        name: once
      restartPolicy: Never
status:
  succeeded: 1
YAML
    cat > "$FX/pod.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: api
  name: api-7d9c5b6f4-x2x9q
  namespace: shop
  ownerReferences:
  - apiVersion: apps/v1
    blockOwnerDeletion: true
    controller: true
    kind: ReplicaSet
    name: api-7d9c5b6f4
    uid: 1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d
spec:
  containers:
  - image: registry.example.com/api:2.3.0
    name: api
  nodeName: worker-2
  restartPolicy: Always
YAML
    cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'SH'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case " $* " in
    *" config view "*) printf 'kind-kind\tshop' ;;
    *" get deploy/api "*) cat "$FX/deploy.yaml" ;;
    *" get svc/api "*) cat "$FX/svc.yaml" ;;
    *" get job/once "*) cat "$FX/job.yaml" ;;
    *" get pod/api-7d9c5b6f4-x2x9q "*) cat "$FX/pod.yaml" ;;
    *" get depoy/api "*) echo "error: the server doesn't have a resource type \"depoy\"" >&2; exit 1 ;;
    *) echo 'Error from server (NotFound): deployments.apps "x" not found' >&2; exit 1 ;;
esac
SH
    chmod +x "$BATS_TEST_TMPDIR/stubs/kubectl"
}

@test "help prints usage and exits 0" {
    run kyaml --help
    [ "$status" -eq 0 ]
    [[ ${lines[0]} == "usage: kyaml "* ]]
}

@test "bad usage exits 2" {
    run kyaml api
    [ "$status" -eq 2 ]
    [[ $output == *"give a kind and a name, for example deploy/api or svc/api"* ]]
    run kyaml
    [ "$status" -eq 2 ]
    run kyaml a b c
    [ "$status" -eq 2 ]
    run kyaml a/b/c
    [ "$status" -eq 2 ]
    run kyaml -o
    [ "$status" -eq 2 ]
}

@test "missing kubectl exits 3" {
    tb_without kubectl
    run kyaml deploy/api
    [ "$status" -eq 3 ]
    [[ $output == "kyaml: needs kubectl."* ]]
}

@test "removes what the cluster added" {
    run kyaml -n shop deploy/api
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "apiVersion: apps/v1" ]
    for gone in managedFields uid: resourceVersion creationTimestamp generation: status: \
            last-applied revision availableReplicas fieldsV1 annotations:; do
        [[ $output != *"$gone"* ]] || { echo "still has $gone"; return 1; }
    done
    [[ $output == *"  namespace: shop"* ]]
    [[ $output == *"      - image: registry.example.com/api:2.3.0"* ]]
    [[ $output == *"        - containerPort: 8080"* ]]
    [ "${lines[${#lines[@]}-1]}" = "          protocol: TCP" ]
    grep -q -- "get deploy/api -n shop -o yaml" "$CALLS"
}

@test "services lose clusterIP and keep other annotations" {
    run kyaml svc api
    [ "$status" -eq 0 ]
    [[ $output != *clusterIP* ]]
    [[ $output != *10.96.141.22* ]]
    [[ $output == *"  annotations:"*"    example.com/owner: shop-team"* ]]
    [[ $output == *"  ipFamilies:"*"  - IPv4"* ]]
}

@test "a headless service keeps clusterIP None" {
    sed -i 's/10\.96\.141\.22/None/' "$FX/svc.yaml"
    run kyaml svc/api
    [ "$status" -eq 0 ]
    [[ $output == *"  clusterIP: None"*"  clusterIPs:"*"  - None"* ]]
}

@test "a job loses the selector and labels its controller made" {
    run kyaml job/once
    [ "$status" -eq 0 ]
    [[ $output != *controller-uid* ]]
    [[ $output != *job-name* ]]
    [[ $output != *"  selector:"* ]]
    [[ $output == *"  backoffLimit: 6"*"      restartPolicy: Never"* ]]
    run kyaml -v job/once
    [[ $output == *"kyaml: removed "*"selector"* ]]
}

@test "a job with manualSelector keeps its selector" {
    sed -i 's/^  backoffLimit: 6$/  backoffLimit: 6\n  manualSelector: true/' "$FX/job.yaml"
    run kyaml job/once
    [ "$status" -eq 0 ]
    [[ $output == *"  selector:"*"      batch.kubernetes.io/controller-uid: "* ]]
}

@test "a pod loses its owner and its node" {
    run kyaml pod/api-7d9c5b6f4-x2x9q
    [ "$status" -eq 0 ]
    [[ $output != *ownerReferences* ]]
    [[ $output != *ReplicaSet* ]]
    [[ $output != *nodeName* ]]
    [[ $output == *"  labels:"*"    app: api"*"  restartPolicy: Always"* ]]
}

@test "--status and --no-namespace" {
    run kyaml --status --no-namespace deploy/api
    [[ $output == *"status:"*"  availableReplicas: 2"* ]]
    [[ $output != *"namespace: shop"* ]]
}

@test "-v lists what it removed" {
    run kyaml -v deploy/api
    [[ $output == *"+ kubectl get deploy/api -n shop -o yaml"* ]]
    [[ $output == *"kyaml: removed "*"managedFields (8 lines)"*"status"* ]]
}

@test "-o writes a file and refuses to overwrite it" {
    run kyaml svc/api -o api-svc.yaml
    [ "$status" -eq 0 ]
    [ "$output" = "kyaml: wrote api-svc.yaml, 23 lines" ]
    [ "$(wc -l < api-svc.yaml)" -eq 23 ]
    echo keep > api-svc.yaml
    run kyaml svc/api -o api-svc.yaml
    [ "$status" -eq 4 ]
    [[ $output == *"api-svc.yaml exists"* ]]
    [ "$(cat api-svc.yaml)" = keep ]
}

@test "a missing object or kind exits 1" {
    run kyaml deploy/nosuch
    [ "$status" -eq 1 ]
    [ "$output" = "kyaml: no deploy/nosuch in shop. List them with: kubectl get deploy -n shop" ]
    run kyaml depoy/api
    [ "$status" -eq 1 ]
    [[ $output == *"no resource type depoy"* ]]
}

@test "pass-through options reach kubectl" {
    run kyaml deploy/api -- --context kind-kind
    grep -q -- "get deploy/api -n shop -o yaml --context kind-kind" "$CALLS"
}
