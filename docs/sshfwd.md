# sshfwd

SSH tunnels without remembering -L, -R and -D.

## Synopsis

```
sshfwd [options] HOST [TARGET:]PORT ... [-- ssh options]
sshfwd [options] -R HOST PORT [-- ssh options]
sshfwd [options] -D HOST [PORT] [-- ssh options]
sshfwd --list | --stop ID | --stop all
```

## Description

SSH can carry other connections inside it. That is how you reach a web page that listens only on a server's
localhost, a database that only a bastion host can see, or your laptop's dev server from a remote machine. The ssh
options for it, `-L 127.0.0.1:5433:db.example.com:5432` and friends, are easy to get backwards. `sshfwd` takes the
host and the port and builds the options for you.

```console
$ sshfwd k8s-master 8080
tunnel  localhost:8080 to port 8080 on k8s-master
open    http://localhost:8080
Ctrl+C closes it.
```

It prints the local address to use, and a URL when the port usually speaks HTTP. The tunnel stays open until Ctrl+C.
With `-b` it keeps running in the background instead, and `--list` and `--stop` manage it later.

## The three kinds of tunnel

### Local forward, the default

`sshfwd HOST PORT` opens a port on your machine that leads to a port on the host. Your browser or client connects to
`localhost:PORT`, and ssh carries the connection to the host, where it reaches `localhost:PORT` as seen from there.

Use it for things that listen only on the server itself, such as a Grafana on `127.0.0.1:3000`, a Kubernetes
dashboard, or a database that refuses outside connections.

`sshfwd HOST TARGET:PORT` goes one step further. The host connects on to TARGET, which only has to be reachable from
the host. That is the bastion pattern, where a private database is only open to one jump server:

```console
$ sshfwd bastion.example.com db.example.com:5432
tunnel  localhost:5432 to db.example.com:5432
        through bastion.example.com
Ctrl+C closes it.
```

TARGET is resolved on the host, so private DNS names work even when your machine cannot resolve them. An IPv6 target
goes in brackets, such as `[fd00::5]:5432`.

Several ports go through one connection: `sshfwd k8s-master 8080 9090 3000`.

### Remote forward, -R

`sshfwd -R HOST PORT` is the other way round. It opens PORT on the host, and connections to it come back to PORT on
your machine. Use it to show a dev server on your laptop to a remote machine, or to let a server reach a service that
runs only on your side.

```console
$ sshfwd -R k8s-master 5173
remote  port 5173 on k8s-master leads to localhost:5173
Ctrl+C closes it.
```

The port on the host listens on its localhost only, unless the host's sshd has `GatewayPorts yes`. `sshfwd` warns when
nothing listens on your side of the port yet, since the tunnel then leads nowhere.

### SOCKS proxy, -D

`sshfwd -D HOST` starts a SOCKS proxy on `127.0.0.1:1080`. Any program that speaks SOCKS then reaches the network as
if it ran on the host. It suits a browser that needs to see several internal sites at once.

```console
$ sshfwd -D bastion.example.com
socks   127.0.0.1:1080 through bastion.example.com
try it  curl --socks5-hostname 127.0.0.1:1080 https://example.com
Ctrl+C closes it.
```

In Firefox, set it under Settings, Network settings, Manual proxy, SOCKS host `127.0.0.1`, port 1080, SOCKS v5, and
tick "Proxy DNS when using SOCKS v5" so internal names resolve on the host.

## Local ports

Every local port `sshfwd` opens listens on `127.0.0.1` only, so other machines on your network cannot use your
tunnel.

The local port is the same number as the remote one when it is free. `sshfwd` changes it in two cases and says so:

| Case | What happens |
|---|---|
| The port is taken on your machine | It takes the next free port above it, and names the program holding the taken one. |
| The port is below 1024 and you are not root | Only root can open those, so it uses the port plus 8000. Port 80 becomes 8080 and 443 becomes 8443. |

```
local 5432 is taken by rootlessport (pid 1790), using 5433
```

`-l PORT` asks for one exact local port. When that port is taken, `sshfwd` stops with exit 1 rather than take
another, since you asked for that one.

## Background tunnels

`-b` leaves the tunnel running after `sshfwd` returns, and gives it a small number:

```console
$ sshfwd -b bastion.example.com db.example.com:5432
local 5432 is taken by rootlessport (pid 1790), using 5433
tunnel 1  localhost:5433 to db.example.com:5432
          through bastion.example.com
in the background, pid 7012. Close it with: sshfwd --stop 1
```

`--list` shows the ones still running, and how long each has been up:

```console
$ sshfwd --list
ID  PID      UP     TUNNEL
1   7012     2h     localhost:5433 to db.example.com:5432, through bastion.example.com
2   7240     5m     localhost:8080 to port 8080 on k8s-master
```

A tunnel whose ssh has died, because the network dropped or the host rebooted, is removed from the list with a note.
`--stop 1` closes one tunnel, and `--stop all` closes every one.

`sshfwd` keeps a record per tunnel in `~/.local/state/toolbelt/sshfwd`, with the ssh control socket and a log of
ssh's messages. The folder is readable only by you. Nothing in it outlives the tunnel.

## How it runs ssh

`sshfwd` runs one ssh command, which `-v` prints first:

```
ssh -f -N -L 127.0.0.1:8080:localhost:8080 -o ExitOnForwardFailure=yes
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=yes
    -o ControlPath=SOCKET -o ControlPersist=no k8s-master
```

| Part | Why |
|---|---|
| `-N` | Run no command on the host, only carry the tunnel. |
| `-f` | Go to the background once logged in and the tunnel is up, so `sshfwd` knows it worked before it prints the address. |
| `ExitOnForwardFailure=yes` | Fail at once when the host refuses the tunnel, instead of logging in with no tunnel. |
| `ServerAliveInterval=30` | Check the link every 30 seconds, and give up after three missed checks, so a dead tunnel does not hang for ever. |
| `ControlMaster`, `ControlPath` | A control socket, so `sshfwd` can find the ssh process and close it cleanly with `ssh -O exit`. |

A password or a key passphrase prompt works as usual, before ssh goes to the background. Your `~/.ssh/config`
applies, so host aliases, `User`, `IdentityFile`, `ProxyJump` and `Port` lines all work.

In the foreground, `sshfwd` checks every second that ssh is still running. When the tunnel drops, it says so and
exits 1. Ctrl+C closes the tunnel and exits 0.

## Options

| Option | What it does |
|---|---|
| `-R`, `--remote` | Open PORT on the host, leading back to PORT on your machine. |
| `-D`, `--socks` | A SOCKS proxy through the host, on local port 1080 unless you name one. |
| `-l`, `--local PORT` | Use this local port. With several forwards, it is refused, since one number cannot fit all. |
| `-b`, `--background` | Keep the tunnel after the command ends. |
| `--list` | List background tunnels. |
| `--stop ID` | Close a background tunnel. `--stop all` closes every one. |
| `-q`, `--quiet` | Print nothing but errors. With `-b`, print only the tunnel ID, for scripts. |
| `-v`, `--verbose` | Print the ssh command before it runs. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` go to ssh, before the host:

```console
$ sshfwd k8s-master 8080 -- -i ~/.ssh/lab_ed25519 -p 2222
$ sshfwd db-internal 5432 -- -J bastion.example.com
$ sshfwd k8s-master 8080 -- -o StrictHostKeyChecking=accept-new
```

`-J` jumps through a bastion first, which is another way to reach a private host.

## Needs

`ssh` from OpenSSH, 6.7 or newer for the control socket commands. It comes from `openssh-client` on Debian and Ubuntu,
`openssh-clients` on Fedora, `openssh` on Arch, and `openssh-client` on Alpine. `ss` from iproute2 names the program
on a taken port, and without it the message says "another program".

The host's sshd must allow forwarding. It does by default. When `AllowTcpForwarding no` is set, every tunnel fails.

## Examples

### A dashboard that listens only on the server

```console
$ sshfwd k8s-master 8080
tunnel  localhost:8080 to port 8080 on k8s-master
open    http://localhost:8080
Ctrl+C closes it.
```

### A database behind a bastion, in the background

```console
$ sshfwd -b bastion.example.com db.example.com:5432
tunnel 1  localhost:5432 to db.example.com:5432
          through bastion.example.com
in the background, pid 7012. Close it with: sshfwd --stop 1
$ psql -h localhost -p 5432 app
```

### A tunnel in a script

```bash
id=$(sshfwd -q -b bastion.example.com db.example.com:5432) || exit 1
pg_dump -h localhost app > app.sql
sshfwd --stop "$id"
```

### A privileged port

```console
$ sshfwd -b k8s-master 22 8080
local 22 needs root, using 8022
tunnel 2  localhost:8022 to port 22 on k8s-master
          localhost:8080 to port 8080 on k8s-master
in the background, pid 7240. Close it with: sshfwd --stop 2
```

### A SOCKS proxy, with the ssh command

```console
$ sshfwd -v -D bastion.example.com
+ ssh -f -N -D 127.0.0.1:1080 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 ...
socks   127.0.0.1:1080 through bastion.example.com
try it  curl --socks5-hostname 127.0.0.1:1080 https://example.com
Ctrl+C closes it.
```

### A key the host does not accept

```console
$ sshfwd k8s-worker-1 9090
sshfwd: ssh to k8s-worker-1 failed. Permission denied (publickey).
```

## Troubleshooting

`Permission denied (publickey)`
: The host does not accept your key. Check you can log in with `ssh HOST` first, and pass the right key with
  `-- -i KEY`.

`remote port forwarding failed` or `administratively prohibited`
: The host's sshd does not allow tunnels, or `-R` asked for a port that is taken on the host. Ask the admin about
  `AllowTcpForwarding`, or pick another port.

The tunnel opens but the page does not load
: The service on the host may listen on another address than `localhost`, such as only the host's LAN IP. Name that
  address as the target: `sshfwd HOST 10.0.0.5:8080`.

`the tunnel to HOST dropped`
: The network went away, the host rebooted, or the laptop slept. Start it again. For tunnels that must come back by
  themselves, use `autossh` or a systemd unit.

`--list` shows nothing but the tunnel still works
: It was started without `-b`, or by plain ssh. Only background tunnels from `sshfwd` get a record.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The tunnel opened, and closed on Ctrl+C. Or the list or stop worked. |
| 1 | ssh failed, the tunnel dropped, the `-l` port is taken, or the tunnel ID does not exist. |
| 2 | Bad usage, such as no port, a bad port number, or `-R` with `-D`. |
| 3 | `ssh` is missing. |
| 143 | sshfwd itself was stopped with a TERM signal. It closes the tunnel first. |

## See also

`port`, `waitfor`, `ssh(1)`, `ssh_config(5)`
