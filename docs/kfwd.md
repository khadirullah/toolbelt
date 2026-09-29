# kfwd

Port-forward a service to a spare local port.

## Synopsis

```
kfwd [-n NAMESPACE] [--local PORT] [--port PORT] [--open] SERVICE [-- kubectl port-forward options]
kfwd [options] deploy/NAME | sts/NAME | pod/NAME
```

## Description

`kubectl port-forward svc/grafana 3000:80` is the quick way to reach a service inside a cluster from your own
machine. It has three habits that make it tiring to use. You have to know the service port and pick a free local
port yourself. It fails with `address already in use` when something else has that port. And it exits for good
the moment the pod behind the service restarts, often with a `lost connection to pod` line you only see later,
when the browser tab stops loading.

`kfwd` takes a service name and does the rest. It reads the service, picks its port, finds a spare local port,
starts `kubectl port-forward` and prints the URL. When the forward drops, it starts it again with a short back-off,
and says so. Ctrl+C stops it and exits 0.

A plain name is a service. `svc/NAME` and `service/NAME` are the same. `kfwd` also takes `deploy/NAME`, `sts/NAME`
and `pod/NAME`, which `kubectl port-forward` accepts too, for apps that have no service yet. A deployment or a
statefulset gets a new pod on each reconnect. A single pod only comes back when a pod of that name does, so a
forward to a deleted pod gives up after 5 tries.

## Options

| Option | What it does |
|---|---|
| `-n`, `--namespace NS` | The service's namespace. The context's own namespace by default. |
| `--local PORT` | Listen on this local port instead of a spare one. |
| `--port PORT` | The service or container port to forward, by number or by name, such as `--port 9090` or `--port http`. |
| `--open` | Open the URL in your browser with `xdg-open` once the forward runs. |
| `-q`, `--quiet` | Print only the URL, and no reconnect messages. |
| `-v`, `--verbose` | Print each kubectl command, the ports it picked, and why a forward stopped. |
| `-h`, `--help` | Show the help. |

`-p` is not an option here. Across this toolbelt `-p` means a password, so ports use `--local` and `--port`.

## How it picks the ports

The service port
: A service with one TCP port uses it. A service with several stops with exit 2 and lists them, so you pick one
  with `--port`. UDP ports are skipped, since `kubectl port-forward` forwards TCP only.

The container port
: For `deploy/`, `sts/` and `pod/`, the ports come from the `ports` list of the containers, and the same rules
  apply. That list is only a note in the spec, since a container can listen on a port it does not list. So a
  `--port` number that is not in the list is used as given, and a pod that lists no ports needs one.

The local port
: `--local PORT` is used as given. When something already listens there, `kfwd` names the program and its pid, as
  `ss` reports it, and exits 1. Without `--local`, `kfwd` looks for a free port starting at the service port, such
  as 9090 for 9090. Ports under 1024 need root to listen on, so for those it starts at 8000 plus the port, such as
  8080 for 80 or 8443 for 443.

The URL
: `http://127.0.0.1:PORT`, or `https://` when the service port is 443 or 8443 or its name has `https` in it.

## Reconnecting

`kubectl port-forward` connects to one pod picked when it starts. When that pod restarts or is replaced, kubectl
exits. `kfwd` notices, prints `the connection to svc/NAME dropped, reconnecting`, and starts a new forward on the
same local port, which picks a pod that is running now. A new forward that comes up prints `back on URL`.

Between tries it waits 1, 2, 3, 4 and then 5 seconds. After 5 failed tries in a row it stops with exit 1 and
kubectl's last error, such as a pod that stays Pending. A successful reconnect resets the count.

Any browser tab or client keeps the same URL through all of this. Open connections break at the moment of the
restart, as they would with the pod itself.

## Stopping

Ctrl+C, or a TERM signal from `kill PID`, stops the kubectl child first and then `kfwd`, which exits 0. `kfwd`
tracks the child by its pid, so nothing keeps listening after it ends. A forward started with `&` in a shell
stops the same way, with `kill %1` or `kill PID`.

## Use from a script

`kfwd` keeps running until you stop it, so `url=$(kfwd -q ...)` would wait forever. Start it in the background
with its output in a file, read the URL once the file has it, and stop it by pid when you are done.

```console
$ kfwd -q -n shop --port 9090 api > /tmp/api-url & pid=$!
$ sleep 2; cat /tmp/api-url
http://127.0.0.1:9090
$ kill $pid; wait $pid; echo $?
0
```

Between the `cat` and the `kill`, the script can reach the service at that URL, with `curl` or anything else.

`-q` also hides the reconnect messages, so the file holds the URL alone.

## Security

- The forward listens on 127.0.0.1 only, so only your own machine reaches it. `-- --address 0.0.0.0` changes that,
  on purpose and never by default.
- The traffic goes from your machine to the API server over the same TLS connection kubectl always uses, and from
  there to the kubelet on the pod's node. Nothing is opened on the node itself.
- The cluster records each port-forward in its audit log, when audit logging is on, under your account.
- `kfwd` never stops a program that holds a port. It names it, so you can decide.

## Pass-through

Options after `--` go to `kubectl port-forward`, and `--context` and `--kubeconfig` also to the call that reads the
service.

```console
$ kfwd grafana -- --address 0.0.0.0
$ kfwd -n monitoring grafana -- --context kind-kind
```

`--address 0.0.0.0` makes the port reachable from other machines on your network. Only do that on a network you
trust, since the service gets no login of its own from `kfwd`.

## Needs

`kubectl` and `jq`. `ss`, from iproute2, to name the program that holds a port, and `xdg-open`, from xdg-utils, for
`--open`. Both are optional.

The account behind your context needs `get` on services and pods and `create` on `pods/portforward`.

## Examples

### Grafana on a spare port

```console
$ kfwd -n monitoring grafana
forwarding svc/grafana port 80 to http://127.0.0.1:8080
Ctrl+C stops it
kfwd: the connection to svc/grafana dropped, reconnecting
kfwd: back on http://127.0.0.1:8080
^C
$ echo $?
0
```

The Grafana pod restarted halfway through. The URL stayed the same.

### A service with two ports

```console
$ kfwd -n shop api
kfwd: svc/api has 2 ports, http 80 and grpc 9090
kfwd: pick one with --port 80 or --port 9090
$ echo $?
2
$ kfwd -n shop api --port 8080
kfwd: svc/api has no port 8080. Its ports are http 80 and grpc 9090
```

8080 was the container's port. `--port` takes the service's own port, or its name, such as `--port grpc`.

### Only the URL, for a script

```console
$ kfwd -q -n shop --port 9090 api
http://127.0.0.1:9090
```

It keeps running after it prints the URL, until Ctrl+C. The section on use from a script shows how to read the URL
and carry on.

### What it runs

```console
$ kfwd -v -n monitoring prometheus-server
+ kubectl get svc prometheus-server -n monitoring -o json
kfwd: service port 9090 (web), local port 9090
+ kubectl port-forward svc/prometheus-server 9090:9090 -n monitoring
forwarding svc/prometheus-server port 9090 to http://127.0.0.1:9090
Ctrl+C stops it
```

### A local port that is taken

```console
$ kfwd --local 8820 -n monitoring grafana
kfwd: port 8820 is used by python (pid 390057)
kfwd: pick another, or leave out --local for a spare one
$ echo $?
1
```

`kfwd` only reports the program. It never stops it.

### A typo in the service name

```console
$ kfwd -n monitoring grafna
kfwd: no service grafna in monitoring. Did you mean grafana?
```

### A deployment with no service

```console
$ kfwd -n demo deploy/web
forwarding deploy/web port 8080 to http://127.0.0.1:8080
Ctrl+C stops it
```

The container lists port 8080, and 8080 was free, so both sides use it.

### The pod does not come back

```console
$ kfwd -n monitoring grafana
forwarding svc/grafana port 80 to http://127.0.0.1:8080
Ctrl+C stops it
kfwd: the connection to svc/grafana dropped, reconnecting
kfwd: gave up after 5 tries: error: unable to forward port because pod is not running. Current status=Pending
$ echo $?
1
```

`kwhy -n monitoring` shows why the new pod stays Pending.

### Open it in the browser

```console
$ kfwd --local 3000 --open -n monitoring grafana
forwarding svc/grafana port 80 to http://127.0.0.1:3000
Ctrl+C stops it
```

The browser opens on the URL once the forward runs, not before, so the first page load does not fail.

## Troubleshooting

`kfwd: svc/NAME has no TCP ports to forward`
: The service has only UDP ports, such as a DNS service, or no ports at all. `kubectl port-forward` cannot forward
  those.

`kfwd: pod/NAME lists no container ports, give one with --port`
: The pod spec has no `ports` list. Give the port the app listens on, such as `--port 8080`.

`kfwd: cannot listen on port PORT: ...`
: kubectl could not open the local port, for example a port under 1024 without root. Leave out `--local`, or pick a
  port above 1024.

The URL loads, but the page is empty or says bad gateway
: The forward goes to the service port, which reaches the container's `targetPort`. When the app listens on
  another port than the service's `targetPort`, the connection opens and nothing answers. Compare them with
  `kyaml svc/NAME`.

`error: unable to forward port because pod is not running`
: The service has no running pod behind it. `kwhy` shows why.

The forward stops every few minutes
: Some load balancers and proxies in front of the API server close idle connections. `kfwd` reconnects each time,
  so the URL keeps working. To stop the drops, raise the idle timeout on that load balancer.

No `Handling connection for PORT` lines
: kubectl prints one for each new connection. `kfwd` keeps kubectl's output out of your terminal and reads it only
  to see when the forward is up and why it stopped. `-v` prints the reason a forward stopped.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Stopped with Ctrl+C or a TERM signal. |
| 1 | The local port is taken, no such service or workload, kubectl failed, or it gave up after 5 tries. |
| 2 | Bad usage, a type other than svc/, deploy/, sts/ or pod/, several ports and no `--port`, a service `--port` it does not have, or no container ports and no `--port` number. |
| 3 | kubectl or jq is missing. |

## See also

`sshfwd`, `port`, `kwhy`, `kyaml`, `kubectl-port-forward(1)`
