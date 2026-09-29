# kevents

Show recent events in time order, newest last.

## Synopsis

```
kevents [-n NAMESPACE | -A] [-w] [--since TIME] [-f] [OBJECT] [-- kubectl options]
```

## Description

Events are the cluster's own log. The scheduler writes one when it cannot place a pod, the kubelet when a pull
fails or a container crashes, and a controller when it scales a ReplicaSet. `kubectl get events` shows them, but
not in time order, with wide columns that cut long messages, and with events up to the cluster's limit of an hour
or more.

`kevents` sorts events by the time they last happened, newest at the bottom next to your prompt, and prints each
in two lines. The first has the time, the type, the object and the reason. The second has the full message,
indented. That reads well in a narrow terminal and keeps long scheduler messages whole. A message that ends in
`in pod NAME_NAMESPACE(UID)`, as the kubelet's BackOff does, loses that end, since the first line names the pod.

An event that repeated shows its count, such as `BackOff x14`, at the time it last happened. Warnings are yellow
in a terminal. By default `kevents` shows the last hour of one namespace, and ends with a count of events and
warnings.

Give an object such as `pod/api-5b8c9d7f6-mk4tn` or `deploy/api` to see only its events. `-f` keeps printing new
events as they arrive.

`kevents` only reads.

## Options

| Option | What it does |
|---|---|
| `-n`, `--namespace NS` | Events of this namespace. The context's own namespace by default. |
| `-A`, `--all-namespaces` | Events of every namespace. Objects get a `namespace/` prefix. |
| `-w`, `--warnings` | Only warnings. |
| `--since TIME` | Only events newer than TIME, such as `30s`, `10m`, `2h` or `1d`. `1h` by default. `all` shows every event the cluster still keeps. |
| `-f`, `--follow` | After the list, keep printing new events until Ctrl+C. |
| `-q`, `--quiet` | No summary line and no notes. |
| `-v`, `--verbose` | Print each kubectl command before it runs. |
| `-h`, `--help` | Show the help. |

`-A` and `-n` together are a usage error, and so are two objects.

## Objects

The object is `KIND/NAME` or a bare `NAME`. The kind can be a short name kubectl knows, such as `po`, `deploy`,
`rs`, `svc`, `sts`, `ds`, `job`, `cj`, `pvc`, `hpa`, `ing`, `cm` or `no`. `kevents` turns it into the Kind that
events carry and asks the cluster for events with that kind and name. A bare `NAME` matches any kind with that
name.

Events belong to the exact object. A Deployment's events are about scaling. The crashes are events of its pods,
and the pods' names carry a hash. `kevents -w` without an object shows both.

When `KIND/NAME` has no events, `kevents` asks whether the object exists. An object that exists and was quiet gets
`no events for pod/api-1 in the last 1h` and exit 0. One that does not exist is most likely a typo, so `kevents`
names the closest match and exits 1.

```console
$ kevents -n demo pod/crashr
kevents: no pod crashr in demo. Did you mean crasher?
```

With `-f`, the same line is only a warning and `kevents` goes on following, since you may be waiting for an
object you are about to create. A bare `NAME` and `-A` skip the check. A bare name could be any kind, and `-A`
has no one namespace to look in.

## Times

The time is `HH:MM:SS` for today and `Mon DD HH:MM` for older days, in your local time zone. It is the last time the
event happened, from `lastTimestamp`, or from the newer `series` and `eventTime` fields that some components
write instead.

The cluster itself deletes events after an hour by default, a setting of the API server. `--since all` cannot
show more than the cluster keeps.

## Pass-through

Options after `--` go to `kubectl get events`.

```console
$ kevents -- --context kind-kind
```

## Needs

`kubectl` and `jq`. The account behind your context needs `list` and, for `-f`, `watch` on events.

## Examples

### The last hour of a namespace

```console
$ kevents -n shop
20:22:03  Normal   deploy/api  ScalingReplicaSet
          Scaled up replica set api-5b8c9d7f6 to 2
20:23:43  Warning  pod/cart-7d9f8c6b54-q2lzx  Failed
          Failed to pull image "registry.example.com/cart:1.4.3"
20:32:03  Warning  pod/api-5b8c9d7f6-mk4tn  BackOff x14
          Back-off restarting failed container api
20:35:23  Warning  pod/worker-6c7b9f5d8-8vhwp  FailedScheduling
          0/1 nodes are available: 1 Insufficient cpu.
4 events, 3 warnings
```

### Warnings only

```console
$ kevents -w
20:23:43  Warning  pod/cart-7d9f8c6b54-q2lzx  Failed
          Failed to pull image "registry.example.com/cart:1.4.3"
20:32:03  Warning  pod/api-5b8c9d7f6-mk4tn  BackOff x14
          Back-off restarting failed container api
20:35:23  Warning  pod/worker-6c7b9f5d8-8vhwp  FailedScheduling
          0/1 nodes are available: 1 Insufficient cpu.
3 events, 3 warnings
```

### One pod

```console
$ kevents pod/api-5b8c9d7f6-mk4tn
20:32:03  Warning  pod/api-5b8c9d7f6-mk4tn  BackOff x14
          Back-off restarting failed container api
1 event, 1 warning
```

### Everything the cluster keeps, in every namespace

```console
$ kevents --since all -A -q
Sep 28 19:37  Normal   shop/pod/old-1  Pulled
              Container image "busybox:1.36" already present on machine
20:22:03  Normal   shop/deploy/api  ScalingReplicaSet
          Scaled up replica set api-5b8c9d7f6 to 2
20:23:43  Warning  shop/pod/cart-7d9f8c6b54-q2lzx  Failed
          Failed to pull image "registry.example.com/cart:1.4.3"
...
```

### Follow warnings everywhere

```console
$ kevents -A -w -f
20:23:43  Warning  shop/pod/cart-7d9f8c6b54-q2lzx  Failed
          Failed to pull image "registry.example.com/cart:1.4.3"
...
3 events, 3 warnings
following warnings in every namespace, Ctrl+C stops
20:32:03  Warning  shop/pod/api-5b8c9d7f6-mk4tn  BackOff x14
          Back-off restarting failed container api
^C
```

The API server closes a watch after 30 to 60 minutes. `kevents -f` then starts a new one, so it keeps following.

### Nothing to show

```console
$ kevents -v -w deploy/api
+ kubectl get events -n shop --field-selector involvedObject.kind=Deployment,involvedObject.name=api,type=Warning -o json
kevents: no warnings for deploy/api in the last 1h
$ echo $?
0
$ kevents --since 10m
kevents: no events in shop in the last 10m
```

No events is a normal answer, so `kevents` exits 0.

## Troubleshooting

An event you saw earlier is gone
: The cluster deleted it. The default is one hour. `kwhy` still shows the pod's state, which lasts longer.

The count grows, but the time stays the same
: Some components report repeats in `series` without updating `lastTimestamp`. `kevents` reads the series time
  when there is one.

`kevents: kubectl failed: ...` with `-f`
: The watch was refused, often for a missing `watch` permission on events. The list without `-f` needs only
  `list`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It printed the events, found none, or stopped following with Ctrl+C. |
| 1 | The object has no events and does not exist, or kubectl failed. |
| 2 | Bad usage, such as `--since` with a word it does not know, or two objects. |
| 3 | kubectl or jq is missing. |

## See also

`kwhy`, `knodes`, `logs`, `kubectl-events(1)`
