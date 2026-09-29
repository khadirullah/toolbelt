# sysinfo

The whole machine on one screen.

## Synopsis

```
sysinfo [-q | -v]
```

## Description

When someone asks "what are you running?", the answer is spread over a dozen commands. `hostnamectl`,
`cat /etc/os-release`, `uname -r`, `lscpu`, `free -h`, `df -h /`, `uptime` and `ip addr` each give one piece, in
their own layout, with lines you do not need. `sysinfo` reads the same sources and prints one labelled line for
each fact, short enough to paste into a bug report or a chat.

| Line | Where it comes from |
|---|---|
| host | The host name, then the maker and model from `/sys/class/dmi/id`, then a VM or container type. Lenovo keeps the model name in `product_version`, so `sysinfo` reads it from there. |
| distro | `PRETTY_NAME` from `/etc/os-release`, or `/usr/lib/os-release`. |
| kernel | `/proc/sys/kernel/osrelease`, the same as `uname -r`. |
| cpu | The model name from `lscpu`, with `(R)`, `(TM)` and the clock speed taken out, then cores and threads. |
| ram | Total and used from `/proc/meminfo`, then zram swap and other swap from `/proc/swaps`. |
| disk | Size, filesystem and use of `/`, from `df` and `/proc/mounts`. |
| uptime | `/proc/uptime`, in days, hours and minutes. |
| ip | Each IPv4 address on a real network card, and the gateway on the card with the default route. |
| pkg | Every package manager it finds: apt, dnf, pacman, zypper, apk, then flatpak, snap, nix and brew. |
| init | The name of process 1, and the systemd version when that is systemd. |
| session | The desktop and whether it runs on Wayland or X11, or how you are logged in when there is no desktop. |

The ip line leaves out loopback, docker bridges, veth pairs and VPN tunnels. It keeps a card only when it has a
device in `/sys/class/net/NAME/device`, which only real and virtual hardware has, or when it carries the default
route. That is why a laptop with docker shows one line and not six.

The host line says `virtual machine, kvm` or `container, docker` when `systemd-detect-virt` says so. Without
systemd it looks for `/.dockerenv` and `/run/.containerenv`. Makers leave placeholder text such as `To Be Filled
By O.E.M.` or `System Product Name` in the DMI fields, and `sysinfo` drops those.

Every source is optional. When a file cannot be read or a tool is missing, that line falls back or is left out,
and the rest still prints. That makes `sysinfo` work in a minimal container, in a chroot and on Alpine.

`sysinfo` only reads. It needs no root and changes nothing.

## Options

| Option | What it does |
|---|---|
| `-q`, `--quiet` | One line with host, distro, kernel, short CPU name, RAM and uptime. |
| `-v`, `--verbose` | Show each file it reads and each command it runs, in order, before its line. |
| `-h`, `--help` | Show the help. |

The labels are bold in a terminal and plain in a file or pipe, or when `NO_COLOR` is set.

## Per-distro notes

Debian and Ubuntu
: Everything works on a desktop or server install. The `debian` and `ubuntu` container images have neither
  `ip` nor `lscpu`, so the ip line says so and the cpu line comes from `/proc/cpuinfo`.

Fedora
: The ram line usually shows zram swap, which Fedora sets up at install.

Arch
: `iproute2` and `util-linux` come with the base install, so every line shows.

Alpine
: BusyBox gives `df` and a small `ip`. Install `util-linux` or `lscpu` for the cleaner CPU name, and `iproute2`
  for the ip line. The init line shows `init`, since Alpine uses OpenRC and not systemd.

Raspberry Pi and other ARM boards
: `/proc/cpuinfo` has no model name, so the cpu line uses the `Hardware` field when lscpu gives no name.

## Needs

`/proc` and `/sys`, which every Linux system has. The rest adds lines and is optional.

| Tool | Package | Adds |
|---|---|---|
| `lscpu` | `util-linux`, or `lscpu` on Alpine | Cores per socket. Without it, `/proc/cpuinfo` gives the model and counts. |
| `ip` | `iproute2`, or `iproute` on Fedora | The ip line. Without it, the line says so. |
| `df` | `coreutils` | The disk line. |
| `systemd-detect-virt` | `systemd` | The VM and container type. |
| `systemctl` | `systemd` | The systemd version on the init line. |

## Examples

### A virtual machine

```console
$ sysinfo
host     debian, QEMU Standard PC (Q35 + ICH9, 2009), virtual machine, kvm
distro   Debian GNU/Linux 13 (trixie)
kernel   6.12.107+deb13-amd64
cpu      12th Gen Intel Core i3-12100, 2 cores, 4 threads
ram      7.7GB, 4.9GB used, swap 5.9GB
disk     /  48GB ext4, 43GB used (95%)
uptime   17 hours, 11 minutes
ip       192.168.122.210/24 on enp2s0, gateway 192.168.122.1
pkg      apt
init     systemd 257
session  Cinnamon on X11
```

### A laptop with zram

```console
$ sysinfo
host     km-laptop, Lenovo ThinkPad T480
distro   Fedora Linux 44 (Workstation Edition)
kernel   6.19.8-200.fc44.x86_64
cpu      Intel Core i5-8250U, 4 cores, 8 threads
ram      7.6GB, 5.2GB used, zram swap 7.6GB
disk     /  237GB btrfs, 214GB used (90%)
uptime   3 days, 6 hours
ip       192.168.1.24/24 on wlp3s0, gateway 192.168.1.1
pkg      dnf, flatpak
init     systemd 258
session  GNOME on Wayland
```

### One line

```console
$ sysinfo -q
debian  Debian 13  6.12.107+deb13-amd64  i3-12100  7.7GB  up 17h 11m
```

### Inside a container

```console
$ sysinfo
host     km-laptop, container, docker
distro   Debian GNU/Linux 13 (trixie)
kernel   6.12.107+deb13-amd64
cpu      Intel Core i5-8250U, 4 cores, 8 threads
ram      7.6GB, 5.2GB used, no swap
uptime   3 days, 6 hours
ip       unknown, the ip command is not installed
init     bash
session  none, text console
```

A container shares the host's kernel, CPU and RAM, so those lines describe the host. The disk line is missing
because the image has no `df`.

### See where each line comes from

```console
$ sysinfo -v 2>&1 | head -8
+ cat /proc/sys/kernel/hostname
+ cat /sys/class/dmi/id/sys_vendor
+ cat /sys/class/dmi/id/product_name
+ cat /sys/class/dmi/id/product_version
+ systemd-detect-virt -c
+ systemd-detect-virt -v
host     debian, QEMU Standard PC (Q35 + ICH9, 2009), virtual machine, kvm
distro   Debian GNU/Linux 13 (trixie)
```

### Keep it for a bug report

```console
$ sysinfo > machine.txt
```

The file has no bold codes, since the output is not a terminal.

## Troubleshooting

The host line has no model
: The machine has no DMI table, as on a Raspberry Pi and most ARM boards, or the maker left placeholders. The
  host name still shows.

The ip line says `none, no network card has an IPv4 address`
: The machine has only IPv6, or the network is down. Check with `ip addr`.

The distro line says only `Linux`
: `/etc/os-release` and `/usr/lib/os-release` are both missing, as in some minimal images.

The session line says `none, logged in over ssh` on a desktop
: The desktop's variables are not passed to ssh sessions. That line describes the shell you run `sysinfo` from.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked, even when some lines were left out. |
| 2 | Bad usage, such as an argument. |

## See also

`mem`, `pkg`, `hostnamectl(1)`, `lscpu(1)`, `os-release(5)`
