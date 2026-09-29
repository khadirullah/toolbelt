# waitfor

Wait for a port, a URL or a file.

## Synopsis

```
waitfor [options] HOST:PORT | URL | PATH [-- curl options]
```

## Description

`waitfor` is for scripts that start something and must not go on until it is ready. A database container takes a few
seconds before it accepts connections. A web app answers 503 while it warms up. A daemon writes its socket file a
moment after it starts. `waitfor` tries again and again until the thing is ready, then exits 0. When the time runs
out it exits 1, so the script can stop there.

```console
$ docker compose up -d && waitfor localhost:5432 -t 60 && ./migrate.sh
localhost:5432 open after 7.2s
```

It decides what to wait for from the shape of the argument:

| Argument | Waits until |
|---|---|
| `db:5432`, `10.0.0.5:6443`, `[::1]:8080` | A TCP connection to that port succeeds. |
| `:8080` | A TCP connection to `localhost:8080` succeeds. |
| `http://...` or `https://...` | The URL answers 200, or the code from `-s`. |
| Anything else | The path exists. It can be a file, a folder or a socket. |

A port counts as ready when something accepts the connection. `waitfor` closes it again at once and sends nothing.

A URL counts as ready only on the exact code. A 503 while the app starts, a 404 before the route is loaded, or a
refused connection all mean "try again". Redirects are not followed, so a URL that answers 301 is ready only with
`-s 301`, or with `-- -L` to follow it.

## Timing

`waitfor` tries at once, then once per interval, 1 second by default. It gives up when the timeout has passed, 30
seconds by default. The last try happens at the timeout, so `-t 10` really waits 10 seconds.

Each try has a limit of its own, so one slow try cannot hang the run. A port try waits at most 5 seconds for the
connection, and never past the timeout. A URL try passes the same limit to curl as `--max-time`.

`-t 0` waits for ever. Use it with care in scripts, since a service that never starts then blocks the script for
good.

Both options take fractions, such as `-i 0.2` for five tries a second.

## Output

The result goes to stdout, as one line:

```
db:5432 open after 7.2s
http://localhost:8080/healthz answered 200 after 5.1s
/run/app/app.sock exists after 2.0s
```

In a terminal, one status line on stderr shows each try while it waits and disappears when it is done. With `-v`
every try gets a line of its own, with the reason it was not ready:

```
try 1  connection refused
try 2  connection refused
```

When the time runs out, the error says what the last try saw:

```
waitfor: gave up after 30s, db:5432 is still closed, connection refused
waitfor: gave up after 30s, http://localhost:8080/ last said 503
waitfor: gave up after 30s, /run/app/app.sock does not exist
```

The reasons for a port are `connection refused` (the host is up and nothing listens), `unknown host`,
`no route to host`, `network unreachable` and `no answer in Ns` (a firewall drops the packets). For a URL they are
the HTTP code, `refused`, `unknown host`, `no answer in Ns`, `TLS failed` and `untrusted certificate`.

## Options

| Option | What it does |
|---|---|
| `-t`, `--timeout SEC` | Give up after SEC seconds. 30 by default. `0` waits for ever. |
| `-i`, `--interval SEC` | Seconds between tries. 1 by default. Fractions such as `0.5` work. |
| `-s`, `--status CODE` | For a URL, wait for this HTTP code instead of 200. |
| `-q`, `--quiet` | Only the result line and errors. No status line. |
| `-v`, `--verbose` | Print the command it runs, then one line per try. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` go to curl, and only make sense for a URL. `waitfor` refuses them for a port or a path, with exit
2. Useful ones:

```console
$ waitfor https://localhost:8443/health -- --insecure
$ waitfor http://localhost:8080/api -- -H 'Authorization: Bearer abc123'
$ waitfor http://localhost:8080/ -- -L
```

`--insecure` accepts a self-signed certificate, `-H` sends a header, and `-L` follows redirects.

## Needs

`bash` and `timeout` from coreutils for ports. `waitfor` opens the connection with Bash's own `/dev/tcp`, so it needs
no `nc`. `curl` for URLs, from the `curl` package on every distro. Paths need nothing.

## Examples

### Wait for a database, then migrate

```console
$ waitfor db:5432 -t 60 && ./migrate.sh
db:5432 open after 7.2s
```

### Wait for a health check before a smoke test

```console
$ waitfor http://localhost:8080/healthz && ./smoke-test.sh
http://localhost:8080/healthz answered 200 after 5.1s
```

### See each try

```console
$ waitfor -v :23456
+ bash -c 'exec 3<>/dev/tcp/localhost/23456'
try 1  connection refused
localhost:23456 open after 1.0s
```

### A port that stays closed

```console
$ waitfor -v -t 2 127.0.0.1:23456
+ bash -c 'exec 3<>/dev/tcp/127.0.0.1/23456'
try 1  connection refused
try 2  connection refused
try 3  connection refused
waitfor: gave up after 2.0s, 127.0.0.1:23456 is still closed, connection refused
```

### A host that does not exist

```console
$ waitfor -t 1 nonexistent.invalid:80
waitfor: gave up after 1.0s, nonexistent.invalid:80 is still closed, unknown host
```

### A socket file

```console
$ waitfor -t 10 /run/app/app.sock
/run/app/app.sock exists after 2.0s
```

### An API that answers 401 when it is up

```console
$ waitfor -s 401 http://localhost:8080/api
http://localhost:8080/api answered 401 after 0.0s
```

### In a Kubernetes init step or CI job

```bash
kubectl port-forward svc/web 8080:80 &
waitfor -q -t 20 http://localhost:8080/ || exit 1
curl -s http://localhost:8080/version
```

## Troubleshooting

`is still closed, no answer in 5s`
: A firewall drops the connection without refusing it. Check the port is open on the host with `port PORT` there,
  and in the firewall.

`is still closed, unknown host`
: The name does not resolve. In Docker Compose, use the service name from inside the network, and `localhost` with
  the published port from the host.

`last said 404` for a URL you know works
: Check the path. `waitfor` does not follow redirects, so `http://localhost:8080` and `http://localhost:8080/` may
  answer differently.

`last said untrusted certificate`
: The server uses a self-signed certificate. Pass `-- --insecure`, or `-- --cacert ca.pem` with its CA.

The port is open but the service is not ready
: A port can accept connections before the service behind it is ready, as with some databases during recovery. Wait
  for a health URL instead, or run the service's own check, such as `pg_isready`, after `waitfor`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Ready. |
| 1 | The time ran out before it was ready. |
| 2 | Bad usage, such as no target, a bad number, or `--` options for a port. |
| 3 | `curl` is missing for a URL, or `timeout` for a port. |

## See also

`port`, `httptime`, `netcheck`, `curl(1)`, `timeout(1)`
