# netcheck

Find where the network breaks, step by step.

## Synopsis

```
netcheck [options]
```

## Description

"The internet is down" can mean six different things, and each has a different fix. `netcheck` walks the path your
traffic takes, from the network card to a real website, and tests each piece in order. The first piece that fails is
where the fault is. The last line says so in words, with a command to try when there is one.

```
link      PASS  wlp3s0 up, Wi-Fi Home-5G, signal -61 dBm
address   PASS  192.168.1.24/24 from DHCP
gateway   PASS  192.168.1.1 answers, 2.1 ms
internet  PASS  1.1.1.1 answers, 14 ms
dns       PASS  example.com resolves through 192.168.1.1, 18 ms
https     PASS  https://example.com answers 200, 212 ms
netcheck: all good. If a site still fails, the fault is on its side.
```

Use it to tell a problem on your side from an outage somewhere else. When every step passes and a site still does not
load, the site is down, not your network.

`netcheck` runs every step, then prints the table. In a terminal a status line shows which step it is on.

## The steps

| Step | What it tests | How |
|---|---|---|
| `link` | The network card is on and connected to something, a cable or a Wi-Fi network. | `ip -brief link show IFACE` |
| `address` | The card has an IP address, and it is not a self-made `169.254.x.x` one. | `ip -4 addr show IFACE` |
| `gateway` | The router answers. | `ping -c 2 -W 2` to the default route's gateway |
| `internet` | Traffic gets past the router to the internet. | `ping -c 2 -W 2 1.1.1.1`, then a TCP connection to `1.1.1.1` port 443 when ping fails |
| `dns` | Names turn into addresses. | `getent ahosts HOST`, with a 6 second limit |
| `https` | A real web request works, including TLS. | `curl` to the URL, with a 10 second limit |

Each line has one of four marks:

- `PASS`, the step works.
- `FAIL`, the step does not work. `netcheck` exits 1.
- `WARN`, something is odd but traffic still flows, such as a router that does not answer ping.
- `SKIP`, the step could not run because an earlier one failed. The text says which.

### How the steps depend on each other

Without a link there can be no address, and without an address nothing can be sent. So a `link` failure skips every
other step, and an `address` failure skips the rest too.

After that `netcheck` keeps going, because the later steps tell it more:

- Some routers do not answer ping. When `gateway` fails but `internet` passes, traffic clearly goes through the
  router, so `gateway` becomes `WARN` and does not count as a failure.
- Some networks block ping to the internet. When the ping to `1.1.1.1` fails, `netcheck` opens a TCP connection to
  `1.1.1.1` on port 443. When that works, `internet` passes with `ping is blocked here`.
- `dns` runs even when `internet` fails, because the router often answers DNS questions itself.
- `https` needs `dns`, so a `dns` failure skips it.

### The verdict

The last line names the first step that failed and what to try:

| First failure | Verdict |
|---|---|
| `link` on Wi-Fi | Connect to a Wi-Fi network, with `nmcli device wifi list` to see them. |
| `link` on a cable | Plug the cable in, or check the switch port. |
| `address` | Ask DHCP again, with `nmcli device reapply IFACE` or `sudo dhclient IFACE`. |
| `gateway` | The router does not answer. Restart it, or move closer to it. |
| `internet` | The router answers but nothing gets past it. The line to your provider is down. |
| `dns` | The internet works but DNS does not. Try another server, with the command for this machine. |
| `https` | DNS works, but the site does not answer over HTTPS. It may be down, or a firewall or proxy blocks it. |

For DNS, the command it suggests depends on what runs the network. With systemd-resolved it is
`resolvectl dns IFACE 1.1.1.1`. With NetworkManager and no systemd-resolved it is
`nmcli connection modify 'NAME' ipv4.dns 1.1.1.1`. Otherwise it points at `/etc/resolv.conf`. The change from
`resolvectl` lasts until the next reconnect. The one from `nmcli` stays, and takes effect after
`nmcli connection up 'NAME'`.

### Which interface

By default `netcheck` checks the interface that carries the default route, the one your traffic uses. When there is
no default route, it takes the first interface that is up. `-i` picks one yourself, which also makes the pings go out
through it with `ping -I`.

## Options

| Option | What it does |
|---|---|
| `-i`, `--iface IFACE` | Check this interface instead of the one with the default route. |
| `--host URL` | The site for the `dns` and `https` steps. `https://example.com` by default. A bare name such as `git.example.com` gets `https://` in front. |
| `-q`, `--quiet` | Print only the verdict, `all good` or `fails at STEP`. |
| `-v`, `--verbose` | Show each `ip`, `ping`, `getent` and `curl` command before it runs. |
| `-h`, `--help` | Show the help. |

`netcheck` has no pass-through. Each step calls a different tool, and `-v` shows each command so you can run it by
hand.

## Needs

- `ip` from `iproute2`, or `iproute` on Fedora.
- `ping` from `iputils-ping` on Debian and Ubuntu, or `iputils` on Fedora, Arch, openSUSE and Alpine. Minimal
  container images often lack it.
- `getent`, part of the C library on every distro. On Alpine it comes from `musl-utils`.
- `curl`.
- `timeout` from coreutils.

Optional: `nmcli` from NetworkManager, or `iw`, adds the Wi-Fi network name. The signal comes from
`/proc/net/wireless`, so it needs no tool. `resolvectl` names the real DNS server behind systemd-resolved.

`netcheck` exits 3 with the install line when `ip`, `ping`, `getent` or `curl` is missing.

## Examples

### Everything works

```console
$ netcheck
link      PASS  enp2s0 up
address   PASS  192.168.122.210/24 from DHCP
gateway   PASS  192.168.122.1 answers, 0.1 ms
internet  PASS  1.1.1.1 answers, 10 ms
dns       PASS  example.com resolves through 192.168.122.1, 25 ms
https     PASS  https://example.com answers 200, 53 ms
netcheck: all good. If a site still fails, the fault is on its side.
```

### A name that does not resolve

```console
$ netcheck --host https://nonexistent.invalid
link      PASS  enp2s0 up
address   PASS  192.168.122.210/24 from DHCP
gateway   PASS  192.168.122.1 answers, 0.3 ms
internet  PASS  1.1.1.1 answers, 11 ms
dns       FAIL  nonexistent.invalid does not resolve through 192.168.122.1
https     SKIP  needs dns
netcheck: the internet works but DNS does not. Try another server:
          nmcli connection modify 'Wired connection 1' ipv4.dns 1.1.1.1
```

Here DNS works and the name simply does not exist. When `netcheck` with the default `example.com` fails at `dns`,
your DNS server is the problem.

### An interface with no link

```console
$ netcheck -i docker0
link      FAIL  docker0 is up but has no carrier
address   SKIP  needs link
gateway   SKIP  needs link
internet  SKIP  needs link
dns       SKIP  needs link
https     SKIP  needs link
netcheck: no link on docker0. Plug the cable in, or check the switch port.
```

A Docker bridge has no carrier while no container runs, so this one is expected.

### In a script

```console
$ netcheck -q && ./deploy.sh
all good
```

### See every command

```console
$ netcheck -v -q
+ ip route show default
+ ip -brief link show enp2s0
+ ip -4 addr show enp2s0
+ ip route show default
+ ping -c 2 -W 2 192.168.122.1
+ ping -c 2 -W 2 1.1.1.1
+ getent ahosts example.com
+ curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 10 https://example.com
all good
```

## Troubleshooting

`address FAIL only 169.254.x.x, a self-made address. DHCP gave none`
: The machine asked for an address and nothing answered. The router's DHCP server may be off, or the Wi-Fi joined
  but the password was wrong on a network that checks it late. Reconnect, then restart the router.

`gateway FAIL` on a laptop with a strong signal
: Captive portals in hotels and trains often block everything until you accept terms in a browser. Open
  `http://neverssl.com` in a browser.

`https FAIL ... the certificate is not trusted, a proxy may be in the way`
: A company proxy or antivirus tool that inspects HTTPS uses its own certificate. Install the company's root
  certificate, or ask IT.

`dns` passes but slowly, over 1000 ms
: The first query after a while is slower because nothing is cached. Run `netcheck` again. When it stays slow, try
  another DNS server with the command from the verdict.

`netcheck: needs ping` in a container
: Minimal images leave ping out. Install `iputils-ping` on Debian and Ubuntu, or `iputils` elsewhere.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every step passed. A `WARN` still counts as passed. |
| 1 | At least one step failed. The verdict names the first. |
| 2 | Bad usage. |
| 3 | `ip`, `ping`, `getent` or `curl` is missing. |

## See also

`myip`, `httptime`, `lan`, `ping(8)`, `ip(8)`, `resolvectl(1)`
