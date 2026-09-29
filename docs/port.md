# port

Show who is listening on a port.

## Synopsis

```
port [options] [PORT ...] [-- ss options]
port --free
```

## Description

`port` answers the question you ask when a server will not start because "address already in use". For each port
you name, it prints one line per listening socket with the port, the address it listens on, the process id, the user
that owns the process and the full command line.

```
8000/tcp  0.0.0.0  pid 4121  me  python3 -m http.server 8000
```

The address tells you who can reach the server:

- `0.0.0.0` or `[::]` means every network interface. Other machines on your network can connect.
- `127.0.0.1` or `[::1]` means this machine only.
- Any other address, such as `192.168.1.24`, means that one interface.

A server that listens on both IPv4 and IPv6 shows two lines, one per address.

With no port, `port` lists every listening port on the machine, sorted by number. With `-u` it looks at UDP instead
of TCP. UDP has no "listening" state, so for UDP `port` shows every socket bound to the port.

`port` reads the sockets with `ss` from iproute2. When `ss` is missing it uses `lsof`. It reads the command line and
the owner from `/proc`.

### Processes of other users

Linux only shows you the process behind a socket when you own the process, or when you are root. For a port that a
system service holds, such as CUPS on 631, `port` still sees that something listens, but not what:

```
631/tcp   127.0.0.1  owner hidden, run it with sudo to see the process
```

Run `sudo port 631` to see it, if `port` is in root's `PATH`, or `sudo ss -tlnp 'sport = :631'`.

### Containers

A port that a container publishes is held by a helper process, not by the program inside the container. For rootless
podman that helper is `rootlessport` or `pasta`, and for Docker it is `docker-proxy`. When `port` sees one of these,
it asks podman or docker which container publishes that port and names it:

```
5432/tcp  0.0.0.0  pid 1790  me  rootlessport, container pg-dev
```

Stop the container with `podman stop pg-dev` rather than killing the helper.

## Options

| Option | What it does |
|---|---|
| `-u`, `--udp` | Look at UDP sockets instead of TCP. |
| `-k`, `--kill` | Stop the process that holds each port. It asks first. |
| `-y`, `--yes` | With `--kill`, stop without asking. It is a usage error without `--kill`. |
| `--free` | Print a TCP port between 8000 and 8999 that nothing listens on, then exit. |
| `-q`, `--quiet` | Show only the result lines. `port` has no other output, so this changes little. |
| `-v`, `--verbose` | Show the `ss`, `lsof` and `kill` commands before they run. |
| `-h`, `--help` | Show the help. |

A port may be written as `8000` or `:8000`. Anything outside 1 to 65535 is a usage error.

## How --kill works

`--kill` stops the process, not the port. It goes like this for each process on the port:

1. It prints the line for the port, so you see what you are about to stop.
2. It asks `Stop pid 4121 (python3)? [y/N]`. Only `y` or `yes` goes on. With `-y` it does not ask.
3. It sends `TERM`, the polite signal. Most programs close their files and exit.
4. It waits up to 5 seconds, checking every tenth of a second.
5. When the process is still running after 5 seconds, it asks again before it sends `KILL`. `KILL` cannot be caught,
   so the program gets no chance to save anything.
6. It checks the port again and prints `stopped after 0.1s. 8000/tcp is free.`

When a service manager such as systemd restarts the process, the port is taken again at once. `port` notices and
says so. Stop the service instead, with `systemctl stop NAME`.

## Safety checks

`--kill` refuses in these cases:

- The process is pid 1. That is systemd holding the port for socket activation, and it starts the real service the
  next time something connects. `port` tells you to stop the `.socket` unit, which `systemctl list-sockets` shows.
  Exit 4.
- The process is the shell that runs `port`. Exit 4.
- The process belongs to another user and you are not root. `port` prints the `sudo kill` line to run yourself.
  Exit 1.
- `port` cannot see the process at all, because another user owns it. Exit 1.
- There is no terminal to ask in and no `-y`. Exit 4.

`port` never kills anything without first printing what it is.

## --free

`port --free` prints the first TCP port from 8000 up that nothing listens on. Use it when you start a test server
and do not care about the number:

```console
$ python3 -m http.server "$(port --free)"
```

It checks `/proc/net/tcp` and `/proc/net/tcp6`, so it needs neither `ss` nor `lsof`. Another program can still take
the port between the check and your server starting. For a test that is rare enough not to matter.

## Pass-through

Options after `--` go to `ss`, or to `lsof` when `ss` is missing. With `ss`, the useful ones are `-4` and `-6`, to
see only IPv4 or IPv6 sockets:

```console
$ port 5353 -u -- -4
5353/udp  0.0.0.0  owner hidden, run it with sudo to see the process
```

## Needs

`ss` from the `iproute2` package, which almost every distro installs. On Fedora the package is `iproute`. When `ss`
is missing, `port` uses `lsof` from the `lsof` package, and exits 3 with the install line when both are missing.
`stat` and `tr` come with coreutils. `podman` or `docker` are only asked when a container helper holds the port.

## Examples

### Who holds a port

```console
$ port 8000
8000/tcp  0.0.0.0  pid 4121  me  python3 -m http.server 8000
```

### Several ports at once

```console
$ port 80 443 8000
80/tcp    nobody listens
443/tcp   nobody listens
8000/tcp  0.0.0.0  pid 4121  me  python3 -m http.server 8000
```

The exit code is 1 here, because nothing listens on 80 or 443.

### Every listening port

```console
$ port
631/tcp   127.0.0.1  owner hidden, run it with sudo to see the process
631/tcp   [::1]  owner hidden, run it with sudo to see the process
8000/tcp  0.0.0.0  pid 4121  me  python3 -m http.server 8000
```

### Stop what holds a port

```console
$ port -v -k 8000
+ ss -H -tlnp 'sport = :8000'
8000/tcp  0.0.0.0  pid 4121  me  python3 -m http.server 8000
Stop pid 4121 (python3)? [y/N] y
+ kill -TERM 4121
+ ss -H -tlnp 'sport = :8000'
stopped after 0.1s. 8000/tcp is free.
```

### A port that belongs to root

```console
$ port -k 631
631/tcp   127.0.0.1  owner hidden, run it with sudo to see the process
631/tcp   [::1]  owner hidden, run it with sudo to see the process
port: cannot see who holds 631/tcp. Find it with: sudo ss -tlnp 'sport = :631'
```

### UDP

```console
$ port -u 5353
5353/udp  0.0.0.0  owner hidden, run it with sudo to see the process
5353/udp  [::]  owner hidden, run it with sudo to see the process
```

### A spare port for a test server

```console
$ port --free
8000
```

## Troubleshooting

`owner hidden, run it with sudo to see the process`
: Another user, often root or a system account, owns the process. Run `sudo ss -tlnp 'sport = :PORT'` to see it.

The server says "address already in use" but `port` says nobody listens
: The old socket may be in the `TIME_WAIT` state for up to a minute after the server stopped. It is not listening, so
  `port` does not show it. Wait a minute, or start the server with `SO_REUSEADDR`. Also check UDP with `-u`, and
  check that the server binds the address you think it does.

The server runs, but other machines cannot connect
: The server may listen on `127.0.0.1`, which only this machine can reach, or a firewall blocks the port. Look at the
  address column, then check `sudo firewall-cmd --list-ports` on Fedora or `sudo ufw status` on Ubuntu.

`--kill` stops the process but the port is taken again at once
: A service manager restarted it. Find the unit with `systemctl status PID` and stop that.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Something listens on every port given, or `--kill` stopped it. |
| 1 | Nothing listens on at least one of the ports, or the process could not be stopped. |
| 2 | Bad usage, such as a port above 65535 or `--kill` with no port. |
| 3 | Both `ss` and `lsof` are missing. |
| 4 | Refused. pid 1, this shell, or no terminal and no `-y`. |
| 5 | You answered no. |

## See also

`proc`, `sshfwd`, `ss(8)`, `lsof(8)`, `kill(1)`
