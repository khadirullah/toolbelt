# ksecret

Show a Secret decoded, one key or all.

## Synopsis

```
ksecret [-n NAMESPACE] [--show-keys] NAME [-- kubectl options]
ksecret [-n NAMESPACE] [-c] NAME KEY [-- kubectl options]
```

## Description

A Secret keeps each value in base64, so `kubectl get secret -o yaml` shows strings you cannot read. The usual fix
is a jsonpath and a pipe to `base64 -d` for every key. `ksecret` decodes every key at once and prints them in
aligned columns, with the Secret's namespace, name, type and key count on top.

Values print as text when they are text. A value over several lines is indented under the first, so a config file
stored in a Secret stays readable. An empty value shows `(empty)`. A binary value, such as a keystore, is not
printed. `ksecret` gives its size and the command that saves it to a file.

TLS Secrets get a summary instead of a PEM block. A certificate shows its subject, the date it expires and the days
left, read with `openssl`. A private key shows its type and size and stays hidden, since it is the one value you do
not want in your scrollback or a screen share. `--show-keys` prints it.

With a KEY, `ksecret` prints that one value and nothing else, byte for byte. That makes it safe in scripts and
pipes, such as `ksecret db-creds DB_PASSWORD | psql ...`. A newline is added only when the output is a terminal.
`-c` copies the value to the clipboard with `clip` and prints only how many bytes it copied, so the value never
shows on screen.

`ksecret` only reads. It never changes a Secret.

## Options

| Option | What it does |
|---|---|
| `-n`, `--namespace NS` | The Secret's namespace. The context's own namespace by default. |
| `-c`, `--copy` | Copy the value of KEY to the clipboard and print nothing on stdout. Needs a KEY. |
| `--show-keys` | Print private keys in full when showing every key. |
| `-q`, `--quiet` | No header line. |
| `-v`, `--verbose` | Print each kubectl command before it runs. |
| `-h`, `--help` | Show the help. |

## What each value shows

| Value | What `ksecret` prints |
|---|---|
| Text on one line | The text. |
| Text over several lines | The lines, indented under the value column. |
| Empty | `(empty)` |
| Binary, such as a keystore | `binary, N bytes, save it with: ksecret -n NS NAME KEY > file` |
| A PEM certificate | `CN=..., expires DATE, N days left`, or `CN=..., expired DATE, N days ago` |
| A PEM private key | `RSA 2048 private key, hidden, use --show-keys`, and the same for EC and Ed25519 keys |
| An encrypted or OpenSSH private key | `encrypted private key, hidden, ...` or `OpenSSH private key, hidden, ...` |

Without `openssl`, a certificate shows `PEM certificate, N bytes`, and a private key shows
`private key, hidden, use --show-keys` with no size.

A single KEY always prints its exact bytes, whatever they are.

## Safety

- `ksecret` prints secret values. Run it where nobody reads over your shoulder, and not in a recorded terminal.
- Private keys stay hidden unless you pass `--show-keys`.
- `-c` keeps the value off the screen. `clip` holds it in the clipboard until you copy something else.
- `-v` shows the kubectl commands, never the values.

## Pass-through

Options after `--` go to `kubectl get secret`.

```console
$ ksecret db-creds -- --context kind-kind
$ ksecret -n shop shop-tls -- --kubeconfig ~/.kube/lab.yaml
```

## Needs

`kubectl`, `jq` and `base64`, from coreutils. `openssl`, optional, for certificate and key details. `clip`, from
this toolbelt, for `-c`.

The account behind your context needs `get` on secrets in the namespace. Many clusters give that only to admins.

## Examples

### Every key of a Secret

```console
$ ksecret -n shop db-creds
secret shop/db-creds, type Opaque, 6 keys
DB_HOST      postgres.shop.svc.cluster.local
DB_USER      shop
DB_PASSWORD  fake-pass-123
blob         binary, 4 bytes, save it with: ksecret -n shop db-creds blob > file
app.conf     line one
             line two
empty        (empty)
```

### A TLS Secret

```console
$ ksecret -n shop shop-tls
secret shop/shop-tls, type kubernetes.io/tls, 2 keys
tls.crt  CN=shop.example.com, expires 2026-12-18, 79 days left
tls.key  RSA 2048 private key, hidden, use --show-keys
```

With `--show-keys`, the key prints as PEM, indented like any value over several lines.

```console
$ ksecret -n shop --show-keys shop-tls
secret shop/shop-tls, type kubernetes.io/tls, 2 keys
tls.crt  CN=shop.example.com, expires 2026-12-18, 79 days left
tls.key  -----BEGIN PRIVATE KEY-----
         MIIEvQIBADANBgkqhkiG9w0BAQEFAASC...
```

### One value, for a script

```console
$ ksecret -n shop db-creds DB_USER
shop
$ ksecret -n shop db-creds DB_USER | od -c
0000000   s   h   o   p
0000004
```

The second command shows that no newline was added when the output went to a pipe.

### Copy a password without showing it

```console
$ ksecret -c -n shop db-creds DB_PASSWORD
ksecret: copied DB_PASSWORD (13 bytes) to the clipboard
```

### A typo in the name

```console
$ ksecret -n shop db-cred
ksecret: no Secret db-cred in shop. Did you mean db-creds?
$ ksecret -n shop db-creds NOPE
ksecret: no key NOPE in secret shop/db-creds. Keys are DB_HOST, DB_USER, DB_PASSWORD, blob, app.conf and empty
```

### What it runs

```console
$ ksecret -v -n shop db-creds DB_HOST
+ kubectl get secret db-creds -n shop -o json
ksecret: secret shop/db-creds has 6 keys
postgres.shop.svc.cluster.local
```

## Troubleshooting

`ksecret: the cluster refused: secrets "db-creds" is forbidden ...`
: Your account may not read Secrets in that namespace. That is common and deliberate. Ask for a Role with `get` on
  secrets, or use an admin context with `-- --context NAME`.

`ksecret: -c copies one value, name the key`
: `-c` needs a KEY, since copying every key at once would give you one long blob.

`clip could not copy the value`
: `clip` found no clipboard. Over ssh or on a server with no desktop, print the value and pipe it where it goes.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It printed or copied the values. |
| 1 | No such Secret or key, `clip` failed, or kubectl failed. |
| 2 | Bad usage, such as `-c` without a KEY. |
| 3 | kubectl, jq or base64 is missing. |

## See also

`clip`, `jwtpeek`, `certcheck`, `kyaml`, `base64(1)`, `openssl-x509(1)`
