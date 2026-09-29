# lan

Every device on the local network.

## Synopsis

```
lan [options] [-- arp-scan or nmap options]
lan [options] -P HOST [-- nmap options]
```

## Description

`lan` answers "what is on my network?" It scans the subnet of the default interface and lists each device that
answers, with its IP address, its MAC address, the maker of its network card, and a name when one can be found.

```console
$ lan
[sudo] password for khadir:
192.168.1.0/24 on wlp3s0, arp-scan, 256 addresses in 2.1s

IP             MAC                VENDOR         NAME
192.168.1.1    a4:91:b1:3e:07:c2  Technicolor    router.lan
192.168.1.12   dc:a6:32:5f:1a:88  Raspberry Pi   pihole.lan
192.168.1.24   8c:16:45:21:9b:e0  LCFC           km-laptop, this one
192.168.1.31   f2:3a:9c:44:10:7d  private MAC    Pixel-8.local
192.168.1.52   00:11:32:a8:4c:19  Synology       nas.lan
192.168.1.77   50:c7:bf:02:e1:36  TP-LINK        HS110
192.168.1.103  3c:22:fb:9d:05:4e  Apple          -
7 devices
```

It is the command for finding the IP of a Raspberry Pi you just plugged in, checking what a new smart plug is called,
or spotting a device you do not know.

With `-P HOST` it looks at one device instead, and lists the TCP ports open on it.

## How it scans

`lan` sends an ARP request to every address in the subnet. ARP is how devices on one network find each other's MAC
address, and every device answers it, even one whose firewall drops pings. That makes an ARP scan fast and complete,
but it only works on the local network segment. Devices behind a router, or on the far end of a VPN, cannot be
reached this way.

It uses `arp-scan -I IFACE --localnet --plain` when arp-scan is installed, and `nmap -sn -n -e IFACE SUBNET` when it
is not. Both send raw packets, so both need root. `lan` runs them through `sudo` unless it already runs as root, and
sudo asks for your password the first time.

The subnet comes from the IPv4 address of the interface. A laptop at `192.168.1.24/24` scans `192.168.1.0/24`, which
is 256 addresses and takes about two seconds.

A subnet larger than 1,024 addresses, such as a `/16` on an office network, takes minutes. `lan` asks before it
starts such a scan, and refuses with exit 4 when there is no terminal to ask in. `-y` skips the question.

## The columns

| Column | Where it comes from |
|---|---|
| IP | The address that answered. |
| MAC | The hardware address in the answer. |
| VENDOR | The maker of the network card, from the first half of the MAC, as arp-scan or nmap reports it. `lan` shortens it, so "Raspberry Pi Trading Ltd" shows as "Raspberry Pi". |
| NAME | A name from DNS or `/etc/hosts`, through `getent hosts`. When that finds none, an mDNS name from `avahi-resolve`, such as `Pixel-8.local`. A dash when both find nothing. |

This machine never answers its own ARP request, so `lan` adds it from `ip link` and marks it `this one`.

### Private MAC

Phones and newer laptops make up a random MAC address for each Wi-Fi network, so they cannot be tracked from network
to network. A made-up MAC has a bit set that marks it as locally assigned, and no maker owns it. `lan` shows those as
`private MAC`.

The MAC stays the same on one network, so `--new` still recognises the phone next time. The vendor column cannot say
what the device is, though. The mDNS name often does, since phones announce names like `Pixel-8.local` or
`Khadirs-iPhone.local`.

Virtual machines also use locally assigned MACs. QEMU and KVM use `52:54:00`, which arp-scan knows, so a VM shows as
`QEMU virtual` rather than `private MAC`.

## New devices

Every scan saves the MAC addresses it saw, with the time each was first seen, in
`~/.local/state/toolbelt/lan/seen`. `--new` shows only the devices whose MAC is not in that file yet:

```console
$ lan --new
1 new since the last scan on Sep 22
192.168.1.140  24:0a:c4:7b:31:d2  Espressif      -
```

Espressif makes the Wi-Fi chip in many cheap smart plugs and bulbs, so that line is likely the plug you just set up.

The first scan has nothing to compare with, and says so. Delete the folder to start over.

The file keeps MACs from every network the machine has scanned. A laptop that scans at home and at work compares
against both.

## Open ports on one device

`-P HOST` runs an nmap port scan of the 1,000 most common TCP ports on one device:

```console
$ lan -P nas.lan
nas.lan  192.168.1.52  Synology
22/tcp    ssh
80/tcp    http
443/tcp   https
445/tcp   microsoft-ds
5000/tcp  upnp
5001/tcp  commplex-link
6 open, 994 closed, 3.4s
```

The service names come from nmap's list of well-known ports. They are guesses from the port number, so 5000 shows as
`upnp` even when the Synology web page answers there. Pass `-- -sV` to have nmap ask each service what it is, which
takes longer.

With root, or through sudo, nmap uses a SYN scan (`-sS`). It sends half a handshake, which is fast. Without sudo it
falls back to a full TCP connect scan (`-sT`), which is slower and shows up in the device's logs.

Scan only devices on your own network, or ones you have permission to scan. A port scan of someone else's machine is
unwelcome at best, and against the rules of most networks.

## Options

| Option | What it does |
|---|---|
| `-i`, `--iface IFACE` | Scan the subnet on this interface instead of the one with the default route. |
| `--new` | Only devices whose MAC was not seen in an earlier scan. |
| `-P`, `--ports HOST` | Scan the 1,000 common TCP ports on one device. HOST can be a name or an IP. |
| `-y`, `--yes` | Scan a subnet bigger than 1,024 addresses without asking. |
| `-q`, `--quiet` | Only the device lines, with no header, table heading or count. |
| `-v`, `--verbose` | Print the scan command before it runs. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` go to arp-scan, or to nmap when arp-scan is missing, and always to nmap for `-P`:

```console
$ lan -- --retry=3
$ lan -P nas.lan -- -sV
$ lan -P 192.168.1.1 -- -p 1-65535
```

`--retry=3` makes arp-scan ask each address three times, which helps on busy Wi-Fi where answers get lost. `-p
1-65535` makes nmap check every port instead of the common 1,000.

## Needs

`arp-scan` or `nmap`, and `sudo` unless you run `lan` as root. `nmap` for `-P`.

| Distro | Install |
|---|---|
| Debian, Ubuntu | `sudo apt install arp-scan nmap` |
| Fedora | `sudo dnf install arp-scan nmap` |
| Arch | `sudo pacman -S arp-scan nmap` |
| openSUSE | `sudo zypper install arp-scan nmap` |
| Alpine | `sudo apk add arp-scan nmap` |

`avahi-resolve` is optional and adds mDNS names. It comes from `avahi-utils` on Debian and Ubuntu, `avahi-tools` on
Fedora and Alpine, and `avahi` on Arch. It needs the avahi daemon running. `ip` from iproute2 finds the interface and
subnet.

## Examples

### Every device on the home network

```console
$ lan
192.168.122.0/24 on enp2s0, arp-scan, 256 addresses in 2.0s

IP               MAC                VENDOR         NAME
192.168.122.1    52:54:00:3e:07:c2  QEMU virtual   fedora
192.168.122.12   dc:a6:32:5f:1a:88  Raspberry Pi   -
192.168.122.31   f2:3a:9c:44:10:7d  private MAC    -
192.168.122.77   50:c7:bf:02:e1:36  TP-LINK        -
192.168.122.103  3c:22:fb:9d:05:4e  Apple          -
192.168.122.210  42:4c:03:87:4d:42  private MAC    debian, this one
6 devices
```

The IP column grows to fit the longest address.

### Find the Raspberry Pi you just plugged in

```console
$ lan -q | grep -i raspberry
192.168.1.12   dc:a6:32:5f:1a:88  Raspberry Pi   -
```

### Only what is new

```console
$ lan --new
1 new since the last scan on Sep 22
192.168.1.140  24:0a:c4:7b:31:d2  Espressif      -
```

### A second network card

```console
$ lan -i enp0s31f6
10.20.0.0/24 on enp0s31f6, arp-scan, 256 addresses in 1.9s
...
```

### With nmap, when arp-scan is missing

```console
$ lan -v
lan: scanning 192.168.1.0/24 on wlp3s0 with nmap
+ sudo nmap -sn -n -e wlp3s0 192.168.1.0/24
192.168.1.0/24 on wlp3s0, nmap, 256 addresses in 2.4s
...
```

### Ports on the NAS, with service versions

```console
$ lan -v -P nas.lan -- -sV
+ sudo nmap -sS --top-ports 1000 -T4 -sV 192.168.1.52
nas.lan  192.168.1.52  Synology
22/tcp    ssh
...
```

### Nothing installed

```console
$ lan
lan: needs arp-scan. Install it with: sudo dnf install arp-scan
```

## Troubleshooting

A device you know is there does not show up
: It may be asleep. Phones drop off Wi-Fi when the screen is off. Wake it and scan again. On busy Wi-Fi, answers can
  get lost, so try `lan -- --retry=3`.

Only this machine and the router show up
: The interface may be a VPN, a Docker bridge or a VM network. Check which one `lan` scanned on the first line, and
  name the right one with `-i`. `myip` lists them all.

`has no MAC address, so there is no LAN to scan on it`
: The interface is a VPN or other point-to-point link. ARP does not work there. Use `-i` with the Wi-Fi or wired
  interface.

`has no IPv4 address`
: The interface is not connected, or only has IPv6. Run `netcheck`.

Every name is a dash
: The router does not publish names in DNS, and avahi is not installed or not running. Install `avahi-utils` and
  start `avahi-daemon`. Many routers also list connected devices with names in their admin page.

sudo asks for a password every time
: That is sudo's own timeout. `lan` cannot scan without root.

`-P` says the host does not answer
: The device drops every probe, or it is off. Pass `-- -Pn` to scan it anyway without the first ping.

## Exit status

| Code | Meaning |
|---|---|
| 0 | The scan finished. |
| 1 | It failed, such as no interface, no IPv4 address, a failed scan, or a device that does not answer. |
| 2 | Bad usage, such as an argument without `-P`, or `--new` with `-P`. |
| 3 | `arp-scan` and `nmap` are both missing, or `nmap` for `-P`, or `sudo`. |
| 4 | Refused a subnet over 1,024 addresses with no terminal to ask in. |
| 5 | You answered no. |

## See also

`myip`, `netcheck`, `port`, `share`, `arp-scan(1)`, `nmap(1)`
