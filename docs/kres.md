# kres

Compare node requests with real usage.

## Synopsis

```
kres [--sort cpu|mem] [-- kubectl options]
kres --pods NODE [--sort cpu|mem] [-- kubectl options]
```

## Description

The scheduler places a pod by what it asks for, its requests, and not by what it uses. A node whose pods ask for
90% of its cpu takes no more pods that ask for much, even when that node sits almost idle. That is the usual answer
to a pod that stays Pending with `Insufficient cpu` on a cluster that looks quiet. The other way round hurts too. A
pod that uses far more than it asks for crowds its neighbours, and under memory pressure the kubelet evicts it
first.

`kubectl top nodes` shows usage and `kubectl describe node` shows requests, one node at a time. `kres` puts both on
one row per node, as amounts and as a share of what the node can give, its allocatable cpu and memory. Below the
table it flags every node with 90% or more of its cpu or memory requested, and says how big a new pod can be and
still fit there.

`kres --pods NODE` breaks one node down by pod, with each pod's requests and usage, and flags pods that use more
than twice what they ask for.

`kres` only reads. It never changes requests, limits or pods.

## Options

| Option | What it does |
|---|---|
| `--pods NODE` | List the pods on NODE with their requests and usage. |
| `--sort cpu` or `--sort mem` | Sort rows by requests of that kind, highest first. Node order, or pod order, by default. |
| `-q`, `--quiet` | Print only the table, with no header line, flags or notes. |
| `-v`, `--verbose` | Print each kubectl command before it runs. |
| `-h`, `--help` | Show the help. |

## How it counts

Allocatable
: What the node offers to pods, from the node's `status.allocatable`. It is the node's size minus what the kubelet
  keeps for the system. Percentages are shares of this.

Requests
: The sum over the pods on the node that still hold their requests, so Succeeded and Failed pods do not count. A
  pod counts as the larger of its containers together and its biggest init container, plus its `overhead`. That is
  the same sum the scheduler uses. Containers with no request count as 0.

Used
: What metrics-server measured, from `kubectl top nodes` or `kubectl top pods`. It is a recent sample, not a peak.

Units
: cpu prints in millicores under one core, such as `450m`, and in cores above, such as `1.8`. Memory prints in
  `Mi` under one GiB and in `Gi` above.

## Flags

`! NODE has N% of its cpu requested, new pods asking for more than X will stay Pending there`
: Printed for each node at 90% or more of its cpu or memory requested. X is what is left.

`! POD uses X against a Y memory request`, and the same for cpu
: Printed in the `--pods` view for each pod using more than twice its request. Raise its request, or find out why
  it grew.

The flags are advice. `kres` exits 0 with or without them.

## Pass-through

Options after `--` go to every kubectl call.

```console
$ kres -- --context kubernetes-admin@kubernetes
```

## Needs

`kubectl` and `jq`. The usage columns need metrics-server in the cluster. Without it, `kres` still prints requests
and shows `-` for usage. On kind, install metrics-server with its release manifest and add the argument
`--kubelet-insecure-tls` to its container, since kind's kubelets use self-signed certificates.

The account behind your context needs `list` on nodes and on pods in every namespace, and `get` on the metrics
API for the usage.

## Examples

### Every node

```console
$ kres
context kind-kind, 3 nodes
              CPU                   MEMORY
NODE          requests   used       requests    used
k8s-master    450m 23%   410m 21%   170Mi 4%    2.3Gi 61%
k8s-worker-1  1.8 90%    620m 31%   3.0Gi 79%   2.1Gi 54%
k8s-worker-2  300m 15%   1.4 70%    768Mi 20%   3.4Gi 90%
! k8s-worker-1 has 90% of its cpu requested, new pods
  asking for more than 200m will stay Pending there
```

k8s-worker-1 uses 31% of its cpu and still has room for only 200m of new requests. k8s-worker-2 is the other
way round, with low requests and high real usage.

### Sorted by memory requests

```console
$ kres --sort mem
context kind-kind, 3 nodes
              CPU                   MEMORY
NODE          requests   used       requests    used
k8s-worker-1  1.8 90%    620m 31%   3.0Gi 79%   2.1Gi 54%
k8s-worker-2  300m 15%   1.4 70%    768Mi 20%   3.4Gi 90%
k8s-master    450m 23%   410m 21%   170Mi 4%    2.3Gi 61%
! k8s-worker-1 has 90% of its cpu requested, new pods
  asking for more than 200m will stay Pending there
```

### The pods on one node

```console
$ kres --pods k8s-worker-2
context kind-kind, node k8s-worker-2, 2 pods
POD                      CPU req  used   MEM req  used
monitoring/prometheus-0  200m     610m   512Mi    1.9Gi
monitoring/loki-0        100m     240m   256Mi    820Mi
! prometheus-0 uses 1.9Gi against a 512Mi memory request
! prometheus-0 uses 610m cpu against a 200m request
! loki-0 uses 820Mi against a 256Mi memory request
! loki-0 uses 240m cpu against a 100m request
```

Both pods ask for a fraction of what they use. That is why the node is at 90% memory while its requests are at
20%, and why it is the first to evict.

### No request, no usage yet

```console
$ kres --pods k8s-master --sort mem
context kind-kind, node k8s-master, 3 pods
POD                                    CPU req  used   MEM req  used
kube-system/etcd-k8s-master            100m     -      100Mi    -
kube-system/coredns-1                  100m     -      70Mi     -
kube-system/kube-apiserver-k8s-master  250m     -      -        -
```

`-` under a request means the pod asks for none. `-` under used means metrics-server has no sample for the pod,
which is normal for a minute after it starts.

### No metrics-server

```console
$ kres
context kind-kind, 3 nodes
              CPU                   MEMORY
NODE          requests   used       requests    used
k8s-master    450m 23%   -          170Mi 4%    -
k8s-worker-1  1.8 90%    -          3.0Gi 79%   -
k8s-worker-2  300m 15%   -          768Mi 20%   -
! k8s-worker-1 has 90% of its cpu requested, new pods
  asking for more than 200m will stay Pending there
kres: no metrics API, usage columns are empty.
kres: install metrics-server to fill them.
```

### Only the table

```console
$ kres -q
              CPU                   MEMORY
NODE          requests   used       requests    used
k8s-master    450m 23%   410m 21%   170Mi 4%    2.3Gi 61%
k8s-worker-1  1.8 90%    620m 31%   3.0Gi 79%   2.1Gi 54%
k8s-worker-2  300m 15%   1.4 70%    768Mi 20%   3.4Gi 90%
```

### What it runs

```console
$ kres -v > /dev/null
+ kubectl get nodes -o json
+ kubectl get pods -A --field-selector 'status.phase!=Succeeded,status.phase!=Failed' -o json
+ kubectl top nodes --no-headers
```

### A node that does not exist

```console
$ kres --pods nope
kres: no node nope. Nodes are k8s-master, k8s-worker-1 and k8s-worker-2
```

## Troubleshooting

The usage columns show `-` although metrics-server runs
: metrics-server needs a minute after it starts, and it fails quietly when it cannot reach the kubelets. Check
  `kubectl -n kube-system logs deploy/metrics-server` for certificate errors.

A pod stays Pending, and every node shows room
: `kres` sums cpu and memory only. A pod can also wait for a node with a label it selects, a taint it tolerates, a
  free host port, or a volume in its zone. `kwhy` shows the scheduler's own message.

The totals are lower than `kubectl describe node` on a node with sidecars
: Sidecar containers declared as init containers with `restartPolicy: Always` run next to the app for the pod's
  whole life, so the scheduler adds them to the app's request. `kres` counts them as plain init containers, so a
  pod with sidecars shows a little less than the scheduler reserves.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It printed the table, with or without flags. |
| 1 | No such node, or kubectl failed. |
| 2 | Bad usage, such as `--sort` with another word. |
| 3 | kubectl or jq is missing. |

## See also

`knodes`, `kwhy`, `mem`, `kubectl-top(1)`
