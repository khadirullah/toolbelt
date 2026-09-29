# httptime

Where the time goes in one HTTP request.

## Synopsis

```
httptime [options] URL [-- curl options]
```

## Description

"The site is slow" can mean the name lookup is slow, the network is slow, the TLS handshake is slow or the server is
slow. `httptime` sends one request with curl and splits its time into those parts, one line each, with a bar so the
big one stands out.

```
https://example.com/  200, HTTP/2, 713 bytes

dns           11 ms  █████████████
connect       11 ms  ██████████████
tls           15 ms  ███████████████████
first byte    16 ms  ████████████████████
download     0.1 ms  █
total         54 ms
```

The first line has the URL, the HTTP status code, the protocol version and the size of the body.

## The steps

curl measures five moments during a request, each counted from the start: when the name resolved, when the TCP
connection opened, when TLS finished, when the first byte of the answer came, and when the last byte came. Those are
running totals, which are hard to read. `httptime` subtracts each from the next, so every line is one step and the
lines add up to the total.

| Step | What happens | A long time here means |
|---|---|---|
| `dns` | The name turns into an IP address. | A slow or far DNS server. 0 ms means the answer was cached. |
| `connect` | The TCP handshake with the server. It takes one round trip. | The network is slow, or the server is far away. |
| `tls` | The TLS handshake, for `https://` only. One or two more round trips. | Same as connect, or an overloaded server. |
| `first byte` | The server gets the request and works out the answer. | The server or the app behind it is slow. |
| `download` | The body arrives. | A big body, or a slow line. |

The rule of thumb: when `connect` is long, the network is the problem. When `first byte` is long and `connect` is
short, the server is.

For a plain `http://` URL there is no TLS, so the `tls` line is left out.

Times below 10 ms show one decimal, such as `2.1 ms`. The bars are scaled so the longest step fills 20 blocks.

## Several requests

`-n 5` sends five requests one after the other and shows the fastest, the median and the slowest for each step. The
median is the middle value, so one slow request does not pull it up the way it would an average.

```
https://example.com/health  5 runs, all 200

               MIN   MEDIAN      MAX
dns           0 ms     0 ms    11 ms
connect      24 ms    25 ms    31 ms
tls          30 ms    32 ms    44 ms
first byte   41 ms    47 ms   210 ms
total        98 ms   106 ms   296 ms
```

The first request is often the slowest. It pays for the DNS lookup, and caches on the server are cold. When the codes
differ between runs, the first line lists each, such as `200 x4, 503 x1`.

Each request opens a new connection, so every run includes the handshakes.

## Redirects

By default curl does not follow redirects, so `httptime` times the redirect answer itself, often a `301` with a tiny
body. With `-L` curl follows them, and `httptime` adds a `redirects` line with the time spent on every hop before the
last one. The step lines below it then describe the last request only. When a line shows 0 ms after a redirect, curl
reused the connection from the hop before.

## Options

| Option | What it does |
|---|---|
| `-n`, `--count N` | Send N requests, 1 to 100, and show min, median and max. |
| `-L`, `--follow` | Follow redirects, and show the time they took on a line of their own. |
| `-q`, `--quiet` | Print only the total, such as `168 ms`. With `-n`, the median total. |
| `-v`, `--verbose` | Show the curl command before it runs. |
| `-h`, `--help` | Show the help. |

A URL without `http://` or `https://` gets `https://` in front.

## Pass-through

Options after `--` go to curl, before the URL. Use them for the method, headers, a body or a client certificate:

```console
$ httptime https://example.com/api -- -X POST -H 'Content-Type: application/json' -d '{}'
$ httptime https://internal.example.com/ -- --cacert ca.pem
$ httptime https://example.com/ -- --http1.1
$ httptime https://example.com/ -- --resolve example.com:443:203.0.113.10
```

The last one sends the request to a server you name, skipping DNS, which is handy for testing one server behind a
load balancer.

## Needs

`curl`, from the `curl` package on every distro. Any curl from the last ten years works.

## Examples

### One request

```console
$ httptime https://example.com/
https://example.com/  200, HTTP/2, 713 bytes

dns           11 ms  █████████████
connect       11 ms  ██████████████
tls           15 ms  ███████████████████
first byte    16 ms  ████████████████████
download     0.1 ms  █
total         54 ms
```

### A local server over plain HTTP

```console
$ httptime http://127.0.0.1:8000/
http://127.0.0.1:8000/  200, HTTP/1.0, 220 bytes

dns          0.0 ms  █
connect      1.9 ms  ████████████████████
first byte   0.7 ms  ███████
download     0.0 ms  █
total        2.7 ms
```

### Five runs

```console
$ httptime -n 5 http://127.0.0.1:8000/sub/a.txt
http://127.0.0.1:8000/sub/a.txt  5 runs, all 200

               MIN   MEDIAN      MAX
dns         0.0 ms   0.0 ms   0.0 ms
connect     0.1 ms   0.1 ms   0.2 ms
first byte  0.3 ms   0.5 ms   1.8 ms
total       0.5 ms   0.6 ms   1.9 ms
```

### Follow a redirect

```console
$ httptime -L http://127.0.0.1:8000/sub
http://127.0.0.1:8000/sub  200, HTTP/1.0, 230 bytes, 1 redirect

redirects    0.7 ms  ████████████████████
dns          0.0 ms
connect      0.0 ms
first byte   0.4 ms  ███████████
download     0.1 ms  ██
total        1.1 ms
```

### Only the number, for a script

```console
$ httptime -q https://example.com/
54 ms
```

### A server that is down

```console
$ httptime http://127.0.0.1:1/
httptime: could not connect to 127.0.0.1:1 (curl exit 7)
```

## Troubleshooting

`could not resolve HOST (curl exit 6)`
: The name does not exist or DNS does not work. Try `getent hosts HOST`, or run `netcheck`.

`the certificate of HOST is not trusted`
: The server uses a self-signed certificate, or a proxy replaces it. Pass `-- --cacert ca.pem`, or `-- --insecure` to
  time it anyway.

`dns` is always 0 ms
: The answer came from a cache, in systemd-resolved, nscd or the browser-like cache of your DNS server. Only the first
  lookup after the cache expires shows the real time.

`first byte` jumps between runs
: The server does different work each time, such as a cache miss or a garbage collection pause. Use `-n 20` and look
  at the median rather than one run.

An HTTP error such as 500
: `httptime` still exits 0, because the timing is valid. Check the code on the first line in scripts.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The request finished, whatever the HTTP code. |
| 1 | curl failed. The message has the reason and curl's exit code. |
| 2 | Bad usage, such as no URL or a count outside 1 to 100. |
| 3 | curl is missing. |

## See also

`netcheck`, `waitfor`, `speed`, `curl(1)`
