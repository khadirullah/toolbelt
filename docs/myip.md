# myip

Local and public IP addresses, gateway and DNS.

## Synopsis

```
myip [options] [-- curl options]
```

## Description

`myip` shows every address this machine has, on one screen, with a few words on what each network interface is. It
answers "what is my IP" for the three different things that question can mean:

- The local address, the one other machines on your network use to reach you, such as `192.168.1.24`.
- The gateway, the router that carries your traffic out, such as `192.168.1.1`.
- The public address, the one websites see. At home it belongs to your router, and many machines share it.

```
wlp3s0      192.168.1.24/24       Wi-Fi Home-5G
            fe80::6c3d:9a1f:4b20:e17c/64
enp0s31f6   no address            no cable
virbr0      192.168.122.1/24      libvirt bridge
tailscale0  100.101.7.52/32       VPN
gateway     192.168.1.1 on wlp3s0
dns         192.168.1.1 through systemd-resolved
public      203.0.113.47
```

The number after the slash is the prefix length. `/24` means the first three numbers name the network, so every
address from `192.168.1.1` to `192.168.1.254` is on the same local network as you.

### Which interfaces it lists

`myip` lists every interface that is switched on, which is what `ip link show up` prints. It leaves out two kinds:

- `lo`, the loopback interface, which is always `127.0.0.1`.
- `veth` interfaces. Docker, podman and Kubernetes make one per container, as the host end of the container's
  network cable. They have no address of their own and would fill the screen.

An interface that is on but has no address shows `no address`. With `-4` or `-6`, a bridge or VPN with no address of
that family is left out, since it would only add noise.

### What each interface is

The third column comes from the interface name and from `/sys/class/net`:

| Shown | How `myip` knows |
|---|---|
| `Wi-Fi Home-5G` | The interface has a `wireless` folder in `/sys/class/net`. The network name comes from `nmcli`, or from `iw` when NetworkManager is not running. |
| `wired` | A real network card, with a cable in. |
| `no cable` | A real network card whose link flags say `NO-CARRIER`. |
| `VPN` | A name such as `wg0`, `tun0`, `tailscale0` or `ppp0`, or a tun device. |
| `libvirt bridge` | `virbr0` and friends, made by libvirt for virtual machines. |
| `Docker bridge` | `docker0` and `br-...`, made by Docker. |
| `podman bridge` | `podman0`, made by podman. |
| `Kubernetes network` | `cni0`, `flannel.1`, `cali...` and similar. |
| `bridge` | Any other bridge. |

### Gateway and DNS

The gateway comes from the default route in `ip route`. When there is none, `myip` says `none, no default route`,
which means this machine cannot reach anything outside its own network.

The DNS servers come from `/etc/resolv.conf`. On Ubuntu, Fedora and other distros that run systemd-resolved, that
file only names `127.0.0.53`, a small resolver on this machine that passes questions on. `myip` then asks
`resolvectl dns` for the real servers and adds `through systemd-resolved`.

### The public IP

`myip` asks `https://ifconfig.me` with curl, with a 5 second limit. When curl is missing or gets no address back, it
asks OpenDNS with dig, which answers the question `myip.opendns.com` with the address it saw. Use `--local` when
nothing should leave the machine, for example on a network where you do not want to be seen asking.

## Options

| Option | What it does |
|---|---|
| `-4` | Only IPv4 addresses and the IPv4 gateway and public IP. |
| `-6` | Only IPv6 addresses and the IPv6 gateway and public IP. |
| `--local` | Skip the public IP. `myip` sends nothing over the network. |
| `--public` | Print only the public IP. |
| `-q`, `--quiet` | Print only the address that carries the default route. With `--public`, only the public IP. |
| `-v`, `--verbose` | Show each `ip`, `curl` and `dig` command before it runs. |
| `-h`, `--help` | Show the help. |

## In scripts

`myip -q` prints one address and nothing else. It is the address this machine uses when it talks to the internet,
found with `ip route get 1.1.1.1`, which asks the kernel for the route without sending a packet. That is the address
to put in a config file or a URL for other machines on your network.

```console
$ echo "open http://$(myip -q):8000/ on your phone"
open http://192.168.1.24:8000/ on your phone
```

`myip --public` prints only the public address, for a firewall rule or an allow list:

```console
$ myip --public
203.0.113.47
```

## Pass-through

Options after `--` go to curl when it fetches the public IP. Use them to ask through one interface or a proxy:

```console
$ myip --public -- --interface tailscale0
$ myip --public -- --proxy socks5h://127.0.0.1:1080
```

## Needs

`ip` from `iproute2` (`iproute` on Fedora), which every mainstream distro installs. For the public IP, `curl`, or
`dig` from `bind9-dnsutils` on Debian and Ubuntu, `bind-utils` on Fedora and openSUSE, `bind` on Arch and
`bind-tools` on Alpine. `nmcli` from NetworkManager or `iw` adds the Wi-Fi name. `resolvectl` adds the real DNS
servers behind systemd-resolved.

## Examples

### Everything

```console
$ myip
enp2s0           192.168.122.210/24    wired
                 fe80::16f1:c176:5d39:c1fb/64
docker0          172.17.0.1/16         Docker bridge
br-e91152e75d94  172.18.0.1/16         Docker bridge
                 fc00:f853:ccd:e793::1/64
gateway          192.168.122.1 on enp2s0
dns              192.168.122.1
public           203.0.113.47
```

### The address for a script

```console
$ myip -q
192.168.122.210
```

### Only IPv6, and nothing sent out

```console
$ myip -6 --local
enp2s0           fe80::16f1:c176:5d39:c1fb/64  wired
br-e91152e75d94  fc00:f853:ccd:e793::1/64  Docker bridge
gateway          none, no default route
dns              192.168.122.1
```

No IPv6 default route means this machine has no IPv6 internet. The `fe80::` address works only on the local link.

### See the commands

```console
$ myip -v --public
+ curl -s --max-time 5 https://ifconfig.me
203.0.113.47
```

### No internet

```console
$ myip --public
myip: no answer from ifconfig.me in 5s. Check the link with: netcheck
```

## Troubleshooting

`myip: no answer from ifconfig.me in 5s`
: The machine cannot reach the internet, or DNS does not work. Run `netcheck` to find the step that fails.

`gateway none, no default route`
: The machine is not connected, or DHCP gave no router. On NetworkManager systems, `nmcli device` shows the state of
  each interface.

An address starts with `169.254.`
: The interface asked DHCP for an address and got no answer, so it made one up. Nothing outside the cable can reach
  it. Check the router, or run `netcheck`.

The public IP is not the one your router shows
: Your provider may use carrier-grade NAT, where many customers share one public address. Addresses from
  `100.64.0.0` to `100.127.255.255` on the router's outside mean that. Ports you forward on the router then do not
  reach you from the internet.

The Wi-Fi name is missing
: Install NetworkManager's `nmcli`, or `iw`. Without either, `myip` shows only `Wi-Fi`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | The public IP could not be found, or with `-q` there is no default route. The local table still prints. |
| 2 | Bad usage, such as `--local` with `--public`. |
| 3 | `ip` is missing, or `--public` has neither curl nor dig. |

## See also

`netcheck`, `lan`, `ip(8)`, `resolvectl(1)`
