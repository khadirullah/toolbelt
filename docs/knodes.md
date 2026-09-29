# knodes

Show node health and pressure at a glance.

## Synopsis

```
knodes [NODE] [-- kubectl options]
```

## Description

`kubectl get nodes` says Ready or NotReady and little else. A node can be Ready and still be in trouble. Under
MemoryPressure, DiskPressure or PIDPressure the kubelet refuses new pods and evicts running ones, and
`get nodes` shows none of that. You find it in `kubectl describe node`, one node at a time, in a long block of
conditions.

`knodes` prints one row per node with its status, roles, age and kubelet version. A CONDITIONS column appears when
any node has a problem, and says `ok` for the others. When every node is fine, the table ends with
`all conditions normal`.

Each problem then gets a short block under the table.

- The first line names the node, the condition and how long it has held, such as `MemoryPressure since 12m`.
- `kubelet` or `message` is what the kubelet reported, such as `has insufficient memory available`.
- `evicted` for a pressure condition, the number of pods the kubelet evicted from that node in the last hour.
- `top` for MemoryPressure, the three pods on the node that use the most memory, as metrics-server measured.

Name a node to see only that one.

`knodes` only reads. It never cordons, drains or changes a node.

## Options

| Option | What it does |
|---|---|
| `-q`, `--quiet` | Print only the table, no detail blocks and no closing line. |
| `-v`, `--verbose` | Print each kubectl command before it runs. |
| `-h`, `--help` | Show the help. |

## What counts as a problem

| Condition | A problem when | What it means |
|---|---|---|
| `Ready` | not `True` | The kubelet is down, or has not reported in time. Shown as `NotReady`. |
| `MemoryPressure` | `True` | The node is low on memory. The kubelet evicts pods, those most over their memory request first. |
| `DiskPressure` | `True` | The node is low on disk or inodes. The kubelet deletes unused images and then evicts pods. |
| `PIDPressure` | `True` | The node is running out of process ids. |
| `NetworkUnavailable` | `True` | The network plugin has not set up the node's network. |

The STATUS column also shows `SchedulingDisabled` for a cordoned node, as `kubectl get nodes` does. The ROLE
column lists the `node-role.kubernetes.io/` labels, or `worker` for a node with none.

## Pass-through

Options after `--` go to every kubectl call.

```console
$ knodes -- --context kind-kind
```

## Needs

`kubectl` and `jq`. metrics-server, optional, for the `top` line. Without it, the line is left out and the rest
still prints.

The account behind your context needs `list` on nodes, and on events and pods in every namespace for the detail
lines.

## Examples

### A node under memory pressure

```console
$ knodes
NODE           STATUS  ROLE           AGE  VERSION  CONDITIONS
k8s-master     Ready   control-plane  41d  v1.35.2  ok
k8s-worker-1   Ready   worker         41d  v1.35.2  ok
k8s-worker-2   Ready   worker         41d  v1.35.2  MemoryPressure
k8s-worker-2   MemoryPressure since 6h
  kubelet  has insufficient memory available
  evicted  2 pods in the last hour
  top      prometheus-0 1.9Gi, loki-0 820Mi, api-2wq8d 210Mi
$ echo $?
1
```

prometheus-0 is the pod to look at. `kres --pods k8s-worker-2` shows it uses far more than it requests.

### A node that stopped reporting

```console
$ knodes
NODE           STATUS                       ROLE           AGE  VERSION  CONDITIONS
k8s-master     Ready                        control-plane  41d  v1.35.2  ok
k8s-worker-1   NotReady,SchedulingDisabled  worker         41d  v1.35.2  NotReady
k8s-worker-2   Ready                        worker         41d  v1.35.2  ok
k8s-worker-1   NotReady since 25m
  message  Kubelet stopped posting node status.
```

The node is down or cut off from the API server. After 5 minutes by default, its pods are marked for eviction and
their owners start copies on the other nodes.

### A healthy node

```console
$ knodes k8s-master
NODE         STATUS  ROLE           AGE  VERSION
k8s-master   Ready   control-plane  41d  v1.35.2
all conditions normal
$ echo $?
0
```

### Only the table

```console
$ knodes -q
NODE           STATUS  ROLE           AGE  VERSION  CONDITIONS
k8s-master     Ready   control-plane  41d  v1.35.2  ok
k8s-worker-1   Ready   worker         41d  v1.35.2  ok
k8s-worker-2   Ready   worker         41d  v1.35.2  MemoryPressure
```

### What it runs

```console
$ knodes -v > /dev/null
+ kubectl get nodes -o json
+ kubectl get events -A --field-selector reason=Evicted -o json
+ kubectl top pods -A --no-headers
+ kubectl get pods -A --field-selector spec.nodeName=k8s-worker-2 -o json
```

The last three run only when a node is under pressure.

### A typo in the node name

```console
$ knodes nope
knodes: no node nope. Nodes are k8s-master, k8s-worker-1 and k8s-worker-2
```

## Troubleshooting

`evicted` says 0 pods, but pods were evicted
: Events expire after an hour by default, and some clusters keep them for less. An eviction older than that leaves
  only the pod itself with the status Evicted, which `kclean` lists.

No `top` line
: metrics-server is not installed or not ready. `kres` says which.

A kind node is NotReady right after `kind create cluster`
: The network plugin takes a few seconds to start. Wait and run `knodes` again.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every node looked at is Ready with no pressure. |
| 1 | A node is NotReady or has a problem, no such node, or kubectl failed. |
| 2 | Bad usage, such as two node names. |
| 3 | kubectl or jq is missing. |

## See also

`kres`, `kclean`, `kwhy`, `mem`, `kubectl-describe(1)`
