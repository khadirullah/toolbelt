# kwhy

Show why pods are not Ready, on one screen.

## Synopsis

```
kwhy [-n NAMESPACE | -A] [--lines N] [POD ...] [-- kubectl options]
```

## Description

A pod that is not Ready has its reason spread over three places. `kubectl describe pod` has the state and the
events, `kubectl get events` has the warnings in order, and `kubectl logs --previous` has the last words of a
container that crashed. You run all three for every broken pod, then read them side by side. `kwhy` runs them for
you and prints the part that matters for each pod.

With no pod names, `kwhy` lists the pods in the namespace and picks the ones that are not Ready. For each one it
prints a row with the pod name, the reason in the words kubectl uses, and the restart count. Under the row come the
details that explain it.

- `image` for pull errors, the image the pod asks for.
- `event` the newest Warning event for the pod, such as a failed pull or a failed schedule.
- `asks` for a Pending pod, the cpu and memory it requests.
- `exit` for a crashed container, the exit code, how long ago it ended and how many log lines follow.
- The log lines themselves, indented. For a container that restarted, they come from the crashed run, the same as
  `kubectl logs --previous`.
- `hint` one line in plain words on the usual cause of that reason.

The first line names the context and the namespace, and counts the pods, such as `3 of 4 pods not Ready`. When
every pod is Ready it says so on one line and exits 0. Pods of finished Jobs count as done, not as broken, and the
line then says `Ready or Completed`.

Name one or more pods to see them even when they are Ready. That is useful for a pod that is Running but whose
service does not answer.

`kwhy` only reads. It never restarts, deletes or changes a pod.

## Options

| Option | What it does |
|---|---|
| `-n`, `--namespace NS` | Look in this namespace. The context's own namespace by default, or `default` when it has none. |
| `-A`, `--all-namespaces` | Look in every namespace. Pod names get a `namespace/` prefix. |
| `--lines N` | Log lines per crashed or failing container, 20 by default. `0` skips the logs. |
| `-q`, `--quiet` | One row per pod, no details and no header line. |
| `-v`, `--verbose` | Print each kubectl command before it runs, as `+ kubectl ...`. |
| `-h`, `--help` | Show the help. |

`-A` and `-n` together are a usage error, and so are `-A` and pod names, since a pod name only means something in
one namespace.

## Reasons and hints

The reason is the first of these that fits the pod.

| Reason | Where it comes from | Hint |
|---|---|---|
| `Terminating` | The pod has a deletion time. | A finalizer or a lost node holds it. |
| `Evicted` | The kubelet removed it. | The node ran short, `kclean` removes evicted pods. |
| `Init:ImagePullBackOff` and other `Init:` reasons | An init container is waiting or failed. | Its logs say why. |
| `ImagePullBackOff`, `ErrImagePull` | The container waits for its image. | Missing tag, refused login or unreachable registry, read from the event. |
| `CreateContainerConfigError` | The container waits for its config. | A Secret or ConfigMap it reads is missing, or a key in it. |
| `CrashLoopBackOff`, `Error` | The container keeps exiting. | Read the log lines. |
| `OOMKilled` | The last run ended for memory. | Raise `resources.limits.memory`. |
| `Pending` | No node took the pod. | Not enough cpu or memory, taints, affinity or an unbound PersistentVolumeClaim, read from the scheduler's message. |
| `Running 1/2` | The process runs but a readiness probe fails. | Read the event and the log lines. |

A container that exits with code 0 and then restarts gets the hint that it must keep running to stay Ready. Exit
code 126 or 127 gets the hint that the command in the image does not exist or cannot run. Exit code 137 counts as
killed for memory, like `OOMKilled`. The first two come up often with images built for a Job and then used in a
Deployment.

For a Pending pod, the hint repeats what the pod asks for, such as `no node has cpu 2, memory 1Gi free, see kres`.
`kres` shows how much each node has left to give.

## Where the logs come from

For each pod, `kwhy` picks the container that explains the reason. That is the first init container that has not
finished, or else the first container that is waiting, crashed or not ready. When that container restarted at
least once, the logs come from its previous run, since the current run has often not written anything yet. When it
never ran, as with a pull error, `kwhy` skips the logs.

`kubectl logs` can fail for a pod whose node is gone or whose logs were rotated away. `kwhy` then prints
`kubectl could not read the logs` with kubectl's own reason and carries on with the next pod. A container that
wrote nothing shows `(no output)`.

## When a node is NotReady

A node that stops answering takes every pod on it down at once, and each pod looks broken in its own way. Its
kubelet no longer reports, so a pod that was fine still says `Running 1/1` while the cluster counts it as not
Ready, and `kubectl logs` cannot reach the node at all.

When some pods are not Ready, `kwhy` also lists the nodes. A node that is not Ready gets one line under the header,
with how long it has been down and how many of the listed pods are on it.

```console
$ kwhy -n demo
context kind-toolbelt, namespace demo, 3 of 3 pods not Ready
node toolbelt-control-plane is NotReady since 2m, 3 pods on it, see knodes
crasher                Error              restarts 17
  event  Back-off restarting failed container main
  exit   1, 4m ago
  logs   not readable while the node is NotReady
  hint   fix the node first
web-58ccdc5667-btlc4   not Ready          restarts 0
  hint   the node is NotReady, the pod may be fine
web-58ccdc5667-z8xjx   not Ready          restarts 0
  hint   the node is NotReady, the pod may be fine
```

A pod that only looked `Running` shows as `not Ready`, since the app in it may be fine. Other pods on the node keep
their reason and event, skip the logs and get the hint `fix the node first`. When your account may not list nodes,
`kwhy` skips this check and prints what it did before.

## Pass-through

Options after `--` go to every kubectl call, so a context or a kubeconfig reaches all of them.

```console
$ kwhy -A -- --context kubernetes-admin@kubernetes
$ kwhy -n shop -- --kubeconfig ~/.kube/lab.yaml
```

`--context` and `--kubeconfig` also go to the `kubectl config view` call that finds the context name for the
header.

## Needs

`kubectl` and `jq`. On Debian and Ubuntu, `kubectl` comes from the Kubernetes apt repository or the `kubectl`
package, on Fedora and openSUSE from `kubernetes-client`, and on Arch and Alpine from `kubectl`. `jq` has the same
name everywhere.

`kwhy` reads pods, events and logs, so the account behind your context needs `get` and `list` on pods and events
and `get` on `pods/log` in the namespaces you look at.
`list` on nodes is optional. Without it, `kwhy` cannot name a NotReady node.

## Examples

### What is wrong in this namespace

```console
$ kwhy
context kind-kind, namespace shop, 3 of 4 pods not Ready
cart-7d9f8c6b54-q2lzx    ImagePullBackOff   restarts 0
  image  registry.example.com/cart:1.4.3
  event  Failed to pull image "registry.example.com/cart:1.4.3": rpc error: code = NotFound desc = failed to pull and unpack image "registry.example.com/cart:1.4.3": manifest unknown
  hint   the tag does not exist, or the pull secret is wrong
api-5b8c9d7f6-mk4tn      CrashLoopBackOff   restarts 9
  event  Back-off restarting failed container api in pod api-5b8c9d7f6-mk4tn_shop(1f0c)
  exit   1, 5h ago, last 20 lines of the crashed container
    2026/09/29 10:31:58 loading config from /etc/api/config.yaml
    2026/09/29 10:31:58 connecting to postgres at db:5432
    panic: dial tcp 10.96.12.4:5432: connect: connection refused
  hint   the app stops on start, read the log lines above
worker-6c7b9f5d8-8vhwp   Pending            restarts 0
  event  0/1 nodes are available: 1 Insufficient cpu.
  asks   cpu 2, memory 1Gi
  hint   no node has cpu 2, memory 1Gi free, see kres
$ echo $?
1
```

Three pods, three different causes. The cart image tag does not exist, the api cannot reach its database, and the
worker asks for more cpu than any node has free.

### Only the rows

```console
$ kwhy -q
cart-7d9f8c6b54-q2lzx    ImagePullBackOff   restarts 0
api-5b8c9d7f6-mk4tn      CrashLoopBackOff   restarts 9
worker-6c7b9f5d8-8vhwp   Pending            restarts 0
```

### One pod, with the commands it runs

```console
$ kwhy -v --lines 2 api-5b8c9d7f6-mk4tn
kwhy: context kind-kind, namespace shop
+ kubectl get pod api-5b8c9d7f6-mk4tn -n shop -o json
context kind-kind, namespace shop, 1 of 1 pod not Ready
api-5b8c9d7f6-mk4tn   CrashLoopBackOff   restarts 9
+ kubectl get events -n shop --field-selector involvedObject.name=api-5b8c9d7f6-mk4tn -o json
  event  Back-off restarting failed container api in pod api-5b8c9d7f6-mk4tn_shop(1f0c)
  exit   1, 5h ago, last 2 lines of the crashed container
+ kubectl logs api-5b8c9d7f6-mk4tn -n shop -c api --tail 2 --previous
    2026/09/29 10:31:58 connecting to postgres at db:5432
    panic: dial tcp 10.96.12.4:5432: connect: connection refused
  hint   the app stops on start, read the log lines above
```

The `+` lines go to stderr, so `kwhy -v 2>/dev/null` prints the report alone.

### A pod that is fine

```console
$ kwhy web-6d4cf56db6-xk2p9
context kind-kind, namespace shop, 1 pod Ready
web-6d4cf56db6-xk2p9   Ready              restarts 0
$ echo $?
0
```

### Every namespace

```console
$ kwhy -A
context kind-kind, all namespaces, 3 of 4 pods not Ready
shop/cart-7d9f8c6b54-q2lzx    ImagePullBackOff   restarts 0
  image  registry.example.com/cart:1.4.3
...
```

On a healthy cluster the same command prints one line.

```console
$ kwhy -A
context kind-kind, 1 pod Ready in 1 namespace
```

### Skip the logs

```console
$ kwhy --lines 0 worker-6c7b9f5d8-8vhwp
context kind-kind, namespace shop, 1 of 1 pod not Ready
worker-6c7b9f5d8-8vhwp   Pending            restarts 0
  event  0/1 nodes are available: 1 Insufficient cpu.
  asks   cpu 2, memory 1Gi
  hint   no node has cpu 2, memory 1Gi free, see kres
```

### A pod name with a typo

```console
$ kwhy nope
kwhy: no pod nope in shop. List them with: kubectl get pods -n shop
$ echo $?
1
```

### The cluster is down

```console
$ kwhy
kwhy: cannot reach the cluster for context kind-kind
kwhy: is the kind container running? Try: kind get clusters
```

For a context that is not a kind cluster, the second line says `check it with: kubectl cluster-info`.

## Troubleshooting

`kwhy: kubectl has no cluster set up. Pick one with: kubectl config use-context NAME`
: kubectl has no current context, so it would talk to `localhost:8080`. Run `kubectl config get-contexts` and pick
  one, or pass `-- --context NAME`.

`kwhy: cannot reach the cluster for context NAME`
: The API server did not answer. A kind or minikube cluster may be stopped, a VPN may be down, or the kubeconfig
  may point to an old address. `kubectl cluster-info` shows the address kubectl uses.

`kwhy: the cluster did not accept your login for context NAME, log in again`
: The token or certificate in the kubeconfig expired. Cloud clusters renew it with their own CLI, such as
  `aws eks update-kubeconfig`.

`kwhy: the cluster refused: pods is forbidden ...`
: Your account may not list pods in that namespace. Name a namespace you can read with `-n`, or ask for a Role
  with `get` and `list` on pods and events.

`kubectl could not read the logs` under a pod
: The container never started, its node is gone, or the runtime rotated its logs away. The event line usually
  says more.

The event line is empty
: Events expire after an hour by default. A pod that has been broken for a day may have no events left, while its
  state still shows the reason.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every pod looked at is Ready or Completed, or the namespace has no pods. |
| 1 | Some pods are not Ready, a named pod does not exist, or kubectl failed. |
| 2 | Bad usage, such as `-A` with `-n` or with pod names. |
| 3 | kubectl or jq is missing. |

## See also

`kevents`, `kres`, `kclean`, `knodes`, `kubectl-describe(1)`, `kubectl-logs(1)`
