# kyaml

Print clean YAML of a live object, ready to reuse.

## Synopsis

```
kyaml [-n NAMESPACE] [-o FILE] [--status] [--no-namespace] KIND/NAME [-- kubectl options]
kyaml [options] KIND NAME
```

## Description

`kubectl get -o yaml` prints an object the way the cluster stores it, not the way you wrote it. Half of it is
bookkeeping. There are managedFields, which can run to hundreds of lines, and there is the status block. On top of
that come the uid, resourceVersion, creationTimestamp and generation, and the last-applied annotation that holds a
second copy of the whole object as JSON. Apply that output to another namespace or cluster and some of it fails,
since a uid or resourceVersion from one cluster means nothing in another.

`kyaml` runs `kubectl get -o yaml` and removes what the cluster added. The rest is the object as a person would
write it, with its labels, annotations of your own, and the spec. You can read it, diff it against the file in
git, or save it and apply it somewhere else.

`kyaml` only reads the cluster. It writes a file only with `-o`, and never over a file that exists.

## Options

| Option | What it does |
|---|---|
| `-n`, `--namespace NS` | The object's namespace. The context's own namespace by default. |
| `-o`, `--out FILE` | Write to FILE instead of stdout. It refuses when FILE exists. |
| `--status` | Keep the `status` block. |
| `--no-namespace` | Drop `metadata.namespace` too. |
| `-q`, `--quiet` | No line about the file it wrote. |
| `-v`, `--verbose` | Print the kubectl command and the list of fields it removed. |
| `-h`, `--help` | Show the help. |

The object is `KIND/NAME` as kubectl writes it, such as `deploy/api`, `svc/api` or `configmap/app-config`, or the
same as two words. Any short name kubectl knows works, since `kyaml` hands it to kubectl as it is.

## What it removes

| Field | Why it goes |
|---|---|
| `status` | The cluster writes it. Keep it with `--status`. |
| `metadata.managedFields` | Server-side apply bookkeeping, often most of the output. |
| `metadata.uid` | Unique to this cluster. |
| `metadata.resourceVersion` | A version counter for this copy. Applying it elsewhere can fail with a conflict. |
| `metadata.creationTimestamp` | The cluster sets it. |
| `metadata.generation` | The cluster counts it. |
| `metadata.selfLink` | Left over in objects from older clusters. |
| `kubectl.kubernetes.io/last-applied-configuration` | A JSON copy of the object that `kubectl apply` keeps. |
| `deployment.kubernetes.io/revision` | The Deployment controller's counter. |
| `spec.clusterIP`, `spec.clusterIPs` of a Service | The cluster picks the address. Copying it clashes in another cluster. A headless Service keeps `clusterIP: None` and `clusterIPs: [None]`. |
| `metadata.ownerReferences` | Points at the owner's uid in this cluster. In another cluster the copy has no owner, and the garbage collector deletes it. |
| `spec.selector` and the `controller-uid` and `job-name` labels of a Job | The Job controller made them for this Job. A copy that keeps them fails to apply. A Job with `manualSelector: true` keeps its selector. |
| `spec.nodeName` of a Pod | Ties the copy to one node, which may not exist. Without it, the scheduler picks. |
| `metadata.namespace` | Only with `--no-namespace`, so `kubectl apply -n OTHER` works on the file. |

An `annotations:` block left empty after that goes too. Every other field stays as the cluster printed it,
including defaults it filled in, such as `progressDeadlineSeconds` or `sessionAffinity`. Those apply cleanly.

## Pass-through

Options after `--` go to `kubectl get`.

```console
$ kyaml deploy/api -- --context kind-kind
```

## Needs

`kubectl`. The filter is built in and uses `awk`, so no YAML tool is needed.

## Examples

### A Deployment, ready to reuse

```console
$ kyaml -n shop deploy/api
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: api
  name: api
  namespace: shop
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
```

### What it took out

```console
$ kyaml -v -n shop deploy/api > api.yaml
+ kubectl get deploy/api -n shop -o yaml
kyaml: removed deployment.kubernetes.io/revision, kubectl.kubernetes.io/last-applied-configuration, creationTimestamp, generation, managedFields (8 lines), resourceVersion, uid, status
```

The `+` and `kyaml:` lines go to stderr, so the file holds only the YAML.

### Save a Service to a file

```console
$ kyaml -v -n shop svc/api -o api-svc.yaml
+ kubectl get svc/api -n shop -o yaml
kyaml: removed creationTimestamp, resourceVersion, uid, clusterIP, clusterIPs, status
kyaml: wrote api-svc.yaml, 23 lines
$ kyaml -n shop svc api -o api-svc.yaml
kyaml: api-svc.yaml exists, pick another name or move it away first
$ echo $?
4
```

### Move an object to another namespace

```console
$ kyaml --no-namespace -n shop svc/api | head -8
apiVersion: v1
kind: Service
metadata:
  annotations:
    example.com/owner: shop-team
  labels:
    app: api
  name: api
$ kyaml --no-namespace -n shop svc/api | kubectl apply -n staging -f -
```

Only the annotation you wrote yourself is left.

### Keep the status

```console
$ kyaml --status -n shop svc/api | tail -3
  type: ClusterIP
status:
  loadBalancer: {}
```

### Mistakes

```console
$ kyaml -n shop api
kyaml: give a kind and a name, for example deploy/api or svc/api
Try 'kyaml --help' for the options.
$ kyaml -n shop deploy/nope
kyaml: no deploy/nope in shop. List them with: kubectl get deploy -n shop
$ kyaml pizza/x
kyaml: the cluster has no resource type pizza. List them with: kubectl api-resources
```

## Troubleshooting

`kubectl apply` of the file says `the object has been modified`
: The file still has a `resourceVersion`. That happens only when the field sits somewhere `kyaml` does not
  look, such as inside a List. Delete the line and apply again.

The Service in the new cluster gets a different IP
: That is on purpose. `kyaml` drops `clusterIP` so the new cluster picks a free address. A headless Service is the
  exception. It keeps `clusterIP: None`, since without it the copy would get an address and stop being headless.

The output still has fields you did not write
: The cluster fills in defaults, such as `terminationMessagePath` or `dnsPolicy`. They are valid and apply cleanly,
  so `kyaml` leaves them.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It printed or wrote the YAML. |
| 1 | No such object or resource type, or kubectl failed. |
| 2 | Bad usage, such as a name without a kind. |
| 3 | kubectl is missing. |
| 4 | Refused, since the file given to `-o` exists. |

## See also

`ksecret`, `yamlcheck`, `kubectl-get(1)`, `kubectl-apply(1)`
