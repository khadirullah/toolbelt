# kclean

Delete evicted, completed and crashing pods.

## Synopsis

```
kclean [-n NAMESPACE | -A] [--only KIND] [--system] [-y] [-- kubectl delete options]
```

## Description

Pods pile up in a namespace. The kubelet evicts pods when a node runs short of memory or disk, and an evicted
pod stays in the list with the status `Evicted` until someone deletes it. A CronJob leaves a finished pod behind
for every run it keeps. A pod in CrashLoopBackOff keeps restarting and fills `kubectl get pods` with noise. None of
them does anything useful, and all of them hide the pods you want to look at.

`kclean` finds those three kinds of pods, lists them grouped by kind, and asks once before it deletes them. The
list names each pod, and for a crashing pod also its restart count and its owner. The owner tells you what
happens after the delete. A pod owned by a Deployment, StatefulSet or DaemonSet comes back as a fresh copy, so
deleting a crashing one is a restart. A pod with no owner is gone for good.

Pods cannot go to a trash. The question names the count and the namespace, and says so. Without a terminal to
ask, `kclean` refuses unless you pass `-y`. With `-- --dry-run=client`, kubectl reports what it would delete and
nothing is deleted.

`kclean` never touches pods that are Running and healthy, Pending, or already being deleted.

## Options

| Option | What it does |
|---|---|
| `-n`, `--namespace NS` | Clean this namespace. The context's own namespace by default. |
| `-A`, `--all-namespaces` | Clean every namespace except kube-system. |
| `--only KIND` | Only `evicted`, `completed` or `crashloop` pods. Repeat it for two kinds. |
| `--system` | Include kube-system. Needed with `-A` to reach it, and with `-n kube-system`. |
| `-y`, `--yes` | Delete without asking. |
| `-q`, `--quiet` | Print only the result line. |
| `-v`, `--verbose` | List every pod name, print each kubectl command before it runs, and show kubectl's own output. |
| `-h`, `--help` | Show the help. |

`-A` and `-n` together are a usage error. `kclean` takes no pod names. It finds the pods itself, and
`kubectl delete pod NAME` is the tool for one pod you already know.

## What counts

| Kind | What `kclean` looks for | What deleting it does |
|---|---|---|
| `evicted` | Status `Failed` with reason `Evicted`. | Removes the record. The owner made a new pod when this one was evicted. |
| `completed` | Status `Succeeded`, such as a finished Job run. | Removes the pod and its logs. The Job object stays. |
| `crashloop` | Any container or init container waiting with reason `CrashLoopBackOff`. | Restarts it when an owner makes a new one. Stops it for good when it has no owner. |

Pods with a deletion time are already on their way out and never count.

## The list

Each kind gets one line with its label and count, followed by the pod names. Names wrap at 72 columns, and a
kind with more than three pods shows the first two and `and N more`. `-v` shows every name.

Crashing pods get one line each, since the owner matters there. The owner comes from the pod's
ownerReferences. A ReplicaSet made by a Deployment shows as the Deployment, such as `deploy/api`, found by taking
the `pod-template-hash` off the ReplicaSet name.

With `-A`, names get a `namespace/` prefix and the question counts the namespaces.

## Safety

- It always asks first, with the count and the namespace, and says the pods cannot be restored.
- No terminal and no `-y` means exit 4 and nothing deleted. A cron job or script must pass `-y` on purpose.
- kube-system holds the cluster's own pods, such as CoreDNS and the API server on kubeadm clusters. `-A` skips it,
  and `-n kube-system` refuses with exit 4, unless you pass `--system`.
- Deletes use `--ignore-not-found`, so a pod that went away between the list and the delete is not an error.
- `-- --dry-run=client` or `-- --dry-run=server` skips the question and deletes nothing.

## On different clusters

kind and minikube
: Evicted pods are common, since the node is your laptop and shares its memory with everything else. Clean them
  after a heavy test run.

kubeadm clusters
: The API server, etcd, the scheduler and the controller manager run as static pods in kube-system. The kubelet
  owns them, so deleting one only makes the kubelet start it again. That is one more reason `kclean` skips
  kube-system.

Managed clusters such as EKS, GKE and AKS
: The provider runs its own agents in kube-system and sometimes in namespaces of its own. `-A` still visits those
  other namespaces, so read the list before you answer.

## Pass-through

Options after `--` go to `kubectl delete pod`. The list call gets only `--context` and `--kubeconfig` from them.

```console
$ kclean --only completed -- --grace-period 0
$ kclean -n shop -- --dry-run=client
$ kclean -A -- --context kind-kind
```

`--grace-period 0` matters for crashing pods, which may otherwise wait the full 30 seconds to stop.

## Needs

`kubectl` and `jq`. The account behind your context needs `list` and `delete` on pods in the namespaces it
cleans.

## Examples

### Clean the current namespace

```console
$ kclean
context kind-kind, namespace shop
evicted    2  cart-7d9f8c6b54-8kq1r cart-7d9f8c6b54-v2m7t
completed  4  report-28791440-x7k2p report-28791500-m4n8q and 2 more
crashloop  2  api-5b8c9d7f6-mk4tn, restarts 14, owned by deploy/api
              debug-shell, restarts 6, no owner, it will not come back
Delete 8 pods in shop? They cannot be restored. [y/N] y
deleted 8 pods
```

The api pod comes back as a fresh copy. The debug-shell pod had no owner, so it is gone.

### Every namespace, evicted pods only

```console
$ kclean -A --only evicted
context kind-kind, all namespaces, kube-system skipped
evicted    3  shop/cart-7d9f8c6b54-8kq1r shop/cart-7d9f8c6b54-v2m7t
              monitoring/grafana-5f7c-abcde
Delete 3 pods in 2 namespaces? They cannot be restored. [y/N] n
Nothing changed.
$ echo $?
5
```

### Dry run first

```console
$ kclean -v -n shop -- --dry-run=client
+ kubectl get pods -n shop -o json
context kind-kind, namespace shop
evicted    2  cart-7d9f8c6b54-8kq1r cart-7d9f8c6b54-v2m7t
completed  4  report-28791440-x7k2p report-28791500-m4n8q migrate-9fz2c
              report-28791560-q9w3e
crashloop  2  api-5b8c9d7f6-mk4tn, restarts 14, owned by deploy/api
              debug-shell, restarts 6, no owner, it will not come back
+ kubectl delete pod -n shop --ignore-not-found report-28791440-x7k2p report-28791500-m4n8q migrate-9fz2c report-28791560-q9w3e cart-7d9f8c6b54-8kq1r cart-7d9f8c6b54-v2m7t api-5b8c9d7f6-mk4tn debug-shell --dry-run=client
pod "report-28791440-x7k2p" deleted (dry run)
...
dry run, 8 pods would be deleted
```

`-v` lists every completed pod, where the plain list stopped at two.

### From a script or cron job

```console
$ kclean -n shop -q -y --only completed
deleted 4 pods
```

Without `-y` and without a terminal, the list prints and nothing is deleted.

```console
$ kclean < /dev/null
context kind-kind, namespace shop
...
kclean: not asking without a terminal, pass --yes to go ahead
$ echo $?
4
```

### Nothing to do

```console
$ kclean -n monitoring --only completed
context kind-kind, namespace monitoring
nothing to clean in monitoring
$ echo $?
0
```

### kube-system

```console
$ kclean -n kube-system
kclean: kube-system holds the cluster's own pods. Add --system to clean it
$ echo $?
4
$ kclean -A --system -y --only evicted
context kind-kind, all namespaces
evicted    4  shop/cart-7d9f8c6b54-8kq1r shop/cart-7d9f8c6b54-v2m7t
              and 2 more
deleted 4 pods
```

### Restart crashing pods at once

```console
$ kclean -n shop --only crashloop -y -- --grace-period 0
context kind-kind, namespace shop
crashloop  2  api-5b8c9d7f6-mk4tn, restarts 14, owned by deploy/api
              debug-shell, restarts 6, no owner, it will not come back
deleted 2 pods
```

The Deployment makes a new api pod with a restart count of 0, which resets the back-off. Use it after you fixed
what made the pod crash, such as a missing Secret.

### A kind it does not know

```console
$ kclean --only oops
kclean: --only takes evicted, completed or crashloop, not oops
Try 'kclean --help' for the options.
```

## Troubleshooting

Evicted pods come back after a while
: The node is still short of memory or disk, so the kubelet keeps evicting. `knodes` shows which node is under
  pressure, and `kres` shows how full its requests are.

Completed pods come back after every run
: That is the CronJob keeping its history. Set `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` on the
  CronJob, or `ttlSecondsAfterFinished` on the Job, and the cluster cleans them itself.

A crashing pod comes straight back as CrashLoopBackOff
: Deleting it restarts it, which does not fix the cause. `kwhy` shows the exit code and the last log lines of the
  crashed container.

`kclean: kubectl delete failed in NS: ...`
: The account may list pods but not delete them. The pods in other namespaces are still deleted, and `kclean`
  exits 1.

`kclean: the cluster refused: pods is forbidden ...`
: The account may not list pods in that namespace. Pick a namespace with `-n`, or a context with more rights.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Nothing to clean, the pods were deleted, or a dry run listed them. |
| 1 | kubectl failed, to list or to delete. |
| 2 | Bad usage, such as `-A` with `-n`, a pod name, or an unknown `--only` kind. |
| 3 | kubectl or jq is missing. |
| 4 | Refused. No terminal to ask and no `-y`, or kube-system without `--system`. |
| 5 | You answered no. |

## See also

`kwhy`, `knodes`, `kres`, `kevents`, `kubectl-delete(1)`
