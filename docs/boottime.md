# boottime

Where the boot time went.

## Synopsis

```
boottime [options] [-- systemd-analyze options]
```

## Description

`boottime` shows how long the last boot took and what took the time. It splits the boot into its stages, from
the firmware to the login screen, lists the slowest services, and points at the one that held everything up
when there is one. With `--history` it shows the boot time of every boot the journal still remembers, so you
can see when booting got slow.

It reads what systemd measured during the boot, through `systemd-analyze` and the journal. It never changes a
service, never disables anything, and never needs root.

### The stages of a boot

The first line gives the total time and the goal the boot reached. `to the desktop` means the graphical login
screen was up. `to the login prompt` means a server or console machine was ready for a text login. The lines
under it split the total.

| Stage | What runs |
|---|---|
| `firmware` | The UEFI or BIOS, from power on until it starts the boot loader. Only UEFI machines report it. |
| `loader` | The boot loader, such as GRUB or systemd-boot, including the time its menu waits. Only UEFI machines report it. |
| `kernel` | The Linux kernel, from its start until it hands over to the initrd or to systemd. |
| `initrd` | The small first-stage system that finds and mounts the real root, and asks for a disk password. |
| `userspace` | systemd starting every service until the goal target is reached. |

A long `loader` stage is usually the GRUB menu timeout. A long `initrd` stage on an encrypted machine includes
the time you took to type the disk password. A long `firmware` stage is set in the firmware setup, such as a
fast boot option or a slow network boot check.

Virtual machines and old BIOS machines report only `kernel` and `userspace`, because their firmware does not
pass its timings to the kernel.

### The slowest units

`systemd-analyze blame` lists every unit by how long it took to start. `boottime` shows the top 5, or as many
as `-n` asks for. A unit that took long did not always delay the boot, because systemd starts many units at the
same time. A 10-second unit that nothing waits for costs nothing.

### The hint

`boottime` prints a hint when the slowest unit took at least 2 seconds and at least 40% of the userspace stage.
Such a unit very likely held up the boot. The hint names the command that shows the chain of units that waited
for it.

The most common case is a unit that waits for the network, such as `NetworkManager-wait-online.service` or
`systemd-networkd-wait-online.service`. These wait until the network is fully up. The hint then points at
`network-online.target`, because the real question is which service asked to wait for the network. Often it is
a network mount or a service that does not need to wait at all.

### History

`--history` reads the journal. systemd writes one "Startup finished" line at the end of each boot, and the
journal keeps it for as long as it keeps that boot. `boottime` lists each boot with its start time, the total
and the userspace stage, newest first.

A boot that took more than 1.5 times the middle value, and more than 5 seconds longer, is marked `slow`, with
the `logs` command that shows the errors from that boot.

A boot that never finished, such as one that hung and was powered off, has no line in the journal, so it does
not appear.

### Containers

Inside a container, systemd is usually not PID 1 and there is no boot to time. `boottime` checks for
`/run/systemd/system`, which exists only when systemd runs the machine, and stops with a clear message when it
is missing.

## Options

| Option | What it does |
|---|---|
| `-n`, `--top COUNT` | How many of the slowest units to list. 5 by default. |
| `--history` | Show total and userspace time for each boot in the journal, instead of the last boot in detail. |
| `-q`, `--quiet` | Print only the lines of `systemd-analyze time`, as they are. |
| `-v`, `--verbose` | Show every step, and each command before it runs. |
| `-h`, `--help` | Show the help. |

## Pass-through

Options after `--` go to `systemd-analyze`, for both the time and the blame commands. The useful ones are these.

| Option | What it does |
|---|---|
| `--user` | Time your own user session instead of the machine. |
| `-H user@host` | Ask another machine over ssh. |
| `-M name` | Ask a local container that runs systemd. |

`--history` reads the journal and ignores these options.

## Per-distro notes

- **Every systemd distro.** Debian, Ubuntu, Fedora, Arch and openSUSE all work the same way.
- **Alpine, Devuan, Gentoo with OpenRC, Void.** These do not use systemd, so there is no boot for `boottime` to
  time. It exits with status 1 and says so.
- **Debian 11 and older.** The journal lives in memory by default, so `--history` shows only the current boot.
  Run `sudo mkdir -p /var/log/journal` and reboot to keep it.
- **Journal access.** `--history` reads system entries, which on most distros need the `systemd-journal` group
  or root. Without them it finds no boot times and says so.

## Needs

- `systemd-analyze`, part of systemd.
- `journalctl`, part of systemd, for `--history`.
- systemd running as PID 1.

## Examples

### A laptop that waits for the network

```console
$ boottime
last boot  Sep 29 12:04, 22.9s to the desktop
  firmware     8.1s
  loader       2.3s
  kernel       1.8s
  initrd       3.1s
  userspace    7.6s  until graphical.target
slowest units
    3.4s  NetworkManager-wait-online.service
    0.8s  plymouth-quit-wait.service
    0.6s  dev-nvme0n1p3.device
    0.4s  systemd-udev-settle.service
    0.2s  firewalld.service
hint  3.4s went to waiting for the network. See what needs it:
      systemd-analyze critical-chain network-online.target
```

Almost half of userspace went to waiting for the network. The 8.1 seconds of firmware time is worth a look in
the firmware setup too.

### A virtual machine

```console
$ boottime
last boot  Sep 29 00:16, 41.5s to the desktop
  kernel      33.9s
  userspace    7.6s  until graphical.target
slowest units
    2.6s  containerd.service
    2.1s  docker.service
    1.9s  fwupd.service
    1.8s  blueman-mechanism.service
    0.9s  dev-vda1.device
```

No hint here. The slowest unit took 2.6 seconds, about a third of userspace, and several units ran at the same
time. The long kernel stage is the virtual machine's own start.

### Only the top 3

```console
$ boottime -n 3
last boot  Sep 29 00:16, 41.5s to the desktop
  kernel      33.9s
  userspace    7.6s  until graphical.target
slowest units
    2.6s  containerd.service
    2.1s  docker.service
    1.9s  fwupd.service
```

### Every boot the journal remembers

```console
$ boottime --history
BOOT  STARTED        TOTAL  USERSPACE
   0  Sep 29 09:05   12.4s    7.6s
  -1  Sep 26 08:30   46.1s   41.2s  slow, see: logs -b -1
  -2  Sep 25 09:10   12.3s    7.4s
```

The boot on Sep 26 took 34 seconds longer, all of it in userspace. `logs -b -1` shows what went wrong in it.

### The raw numbers for a script

```console
$ boottime -q
Startup finished in 33.880s (kernel) + 7.585s (userspace) = 41.465s
graphical.target reached after 7.585s in userspace.
```

### Your own session

```console
$ boottime -n 3 -- --user
last boot  Sep 29 00:16, 0.1s to default.target
slowest units
    0.5s  xdg-desktop-portal.service
    0.3s  gnome-terminal-server.service
    0.2s  gvfs-goa-volume-monitor.service
```

The user session reached its goal in a tenth of a second. The units listed started later, when programs asked
for them, so they did not slow the login.

### Inside a container

```console
$ boottime
boottime: systemd is not PID 1 here, so there is no boot to time.
          Inside a container? Run it on the host.
```

## Troubleshooting

**`boottime: the boot has not finished yet, try again in a minute`** systemd is still starting units, or a unit
is stuck and the goal target was never reached. `svc` shows what is still starting or has failed.

**`boottime: no boot times in the journal you can read`** You are not in the `systemd-journal` group. Run
`sudo usermod -aG systemd-journal $USER` and log in again, or run `sudo boottime --history`.

**`--history` shows only one boot.** The journal is kept in memory, or it was vacuumed. `journalctl
--list-boots` shows which boots it holds.

**The total is much longer than it felt.** The firmware and loader stages count from power on, including the
time a boot menu waited for you.

**A unit is at the top every boot.** Check whether anything waits for it with `systemd-analyze critical-chain`.
If nothing does, it costs no time. If something does, `svc NAME` shows what it is doing.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | systemd is not PID 1, the boot has not finished, systemd-analyze failed, or `--history` found no boot times. |
| 2 | Bad usage, such as `-n 0` or a name. |
| 3 | systemd-analyze is missing, or journalctl for `--history`. |

## See also

`logs`, `svc`, `sysinfo`, `systemd-analyze(1)`, `bootup(7)`
