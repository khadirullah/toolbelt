# mem

Who uses the memory, and who goes first when it runs out.

## Synopsis

```
mem [-n COUNT] [-o] [-w [SECONDS]]
```

## Description

`free -h` tells you how much memory is used. It does not tell you by whom, how hard the machine is struggling, or
which process Linux will kill when it runs out. `mem` puts all of that on one screen.

The first line is the total. Used is total minus available, the same number `free` calls used plus the part of
the cache Linux cannot drop. Available is what programs can still get without swapping. Pressure is the share of
the last 10 seconds in which at least one task waited for memory, read from `/proc/pressure/memory`. At 0% the
machine has room. Above 20% or so you feel it as lag, and above 50% the desktop freezes for seconds at a time.

The next lines show zram and swap. zram is compressed swap that lives in RAM, which Fedora and many desktops turn
on by default. The zram line shows the algorithm, how much memory is stored, how much RAM it really takes and the
ratio between them. Each swap device or file gets a line with its use and priority. The kernel fills the highest
priority first, so zram at 100 fills before a swap file at -2.

When systemd-oomd runs, a line says at what pressure it acts and for how long. systemd-oomd is a service on Fedora
and Ubuntu that kills a whole app early, when pressure stays high, before the kernel's own OOM killer has to act.

The table lists the processes that use the most RAM, with their swap and OOM score. The OOM score runs from 0 to
1000 and says who the kernel kills first when memory runs out. It grows with the memory a process uses and with
its `oom_score_adj`, which apps can set. Browsers and Electron apps set it high on their helper processes on
purpose, so a tab dies before the browser does.

The `oom first` line names the process with the highest score and about how much memory killing it would free,
which is its RSS plus its swap. The last lines show the last OOM kill of the past day, from the kernel log and
from systemd-oomd, when the journal has one you can read.

`mem` only reads `/proc` and `/sys`. It never kills or changes anything.

## Options

| Option | What it does |
|---|---|
| `-n`, `--top COUNT` | Show COUNT processes, 6 by default. |
| `-o`, `--oom` | Rank by OOM score, and add the `oom_score_adj` column as ADJ. |
| `-w`, `--watch [SEC]` | Redraw every SEC seconds, 2 by default. Ctrl+C stops. Decimals such as `0.5` work. |
| `-q`, `--quiet` | One line with used, available and swap. |
| `-v`, `--verbose` | Show each file and command it reads. |
| `-h`, `--help` | Show the help. |

## The columns

| Column | What it means |
|---|---|
| RSS | Resident memory, the RAM the process holds right now. Shared libraries count in every process that maps them. |
| SWAP | The part of the process that sits in swap or zram. |
| OOM | The kernel's OOM score, 0 to 1000. The highest dies first. |
| ADJ | With `-o`, the `oom_score_adj` the process or its parent set, from -1000 (never kill) to 1000. |
| PID | The process id. Pass it to `proc` for the rest. |
| COMMAND | The process name, cut to 15 characters by the kernel. |

## Per-distro notes

Fedora
: zram swap and systemd-oomd are on by default, so the zram and oomd lines show on a fresh install.

Ubuntu
: systemd-oomd runs on desktop installs. Server installs use a swap file, `/swap.img`.

Debian, Arch and openSUSE
: Most installs have a swap partition or a swap file and no zram, unless you added `zram-tools` or
  `zram-generator`.

Alpine and containers
: There is no systemd and often no swap. The swap line says `none`, and the kill lines are left out. A container
  sees the host's total memory in `/proc/meminfo` unless LXCFS is in use, so the first line describes the host.

## Needs

`/proc`, which every Linux system has. `/proc/pressure/memory` needs kernel 4.20 or later with PSI turned on. When
it is missing the pressure part is left out. journalctl, from `systemd`, is optional and adds the last kills. On
Alpine and other systems without systemd those lines are left out.

## Examples

### What uses the memory

```console
$ mem
memory  4.9GB used of 7.7GB, 2.8GB available, pressure 0% (10s)
swap    /swapfile  4.6GB of 5.9GB   priority -2

    RSS    SWAP   OOM     PID  COMMAND
  414MB    50MB   888  513434  code
  395MB      0B   685 1655378  firefox-esr
  355MB    71MB   886  587323  code
  346MB    16MB   683  587994  node
  337MB    28MB   684  514331  node
  313MB    30MB   682    3067  node

oom first  code, pid 513434, score 888, frees about 465MB
```

### A Fedora laptop with zram and oomd, just after a kill

```console
$ mem -n 2
memory  7.2GB used of 7.6GB, 488MB available, pressure 38% (10s)
zram    zram0 zstd, 2.8GB of pages stored in 954MB of RAM, 3.0x
swap    zram0      2.9GB of 3.8GB   priority 100
        /swapfile  977MB of 1.9GB   priority -2
oomd    systemd-oomd on, kills in a watched slice at 50% pressure for 20s

    RSS    SWAP   OOM     PID  COMMAND
  1.3GB   400MB   194    2231  firefox
    1GB   606MB   257    4410  Isolated Web Co

oom first  Isolated Web Co, pid 4410, score 257, frees about 1.6GB
last kill  14:02 today, from the kernel log
  Out of memory: Killed process 3877 (Isolated Web Co)
  total-vm:3214580kB, anon-rss:2291044kB, oom_score_adj:167
oomd kill  14:05 today, from systemd-oomd
  Killed /user.slice/app-firefox.scope
```

Pressure at 38% means the machine spends more than a third of its time waiting on memory. The browser tab goes
first because its ADJ is 167.

### Who the kernel kills first

```console
$ mem --oom -n 3
memory  4.9GB used of 7.7GB, 2.8GB available, pressure 0% (10s)
swap    /swapfile  4.6GB of 5.9GB   priority -2

  OOM  ADJ     RSS    SWAP     PID  COMMAND
  888  300   414MB    50MB  513434  code
  886  300   355MB    71MB  587323  code
  882  300   244MB    81MB    2209  code

oom first  code, pid 513434, score 888, frees about 465MB
```

VS Code sets 300 on its helpers, so they rank above bigger processes that set nothing.

### One line for a script or a prompt

```console
$ mem -q
4.9GB of 7.7GB used, 2.8GB available, swap 4.6GB of 5.9GB
```

### Watch it while you work

```console
$ mem -w 5 -n 3
```

The screen redraws every 5 seconds until Ctrl+C. When the output goes to a file or a pipe, `mem` does not clear
the screen, so `mem -w 60 > mem.log` keeps one block per minute.

### A machine with no swap

```console
$ mem -n 1
memory  1.2GB used of 3.8GB, 2.6GB available, pressure 0% (10s)
swap    none

    RSS    SWAP   OOM     PID  COMMAND
  301MB      0B   676     812  java

oom first  java, pid 812, score 676, frees about 301MB
```

## Troubleshooting

No pressure on the first line
: The kernel has no PSI. Check with `ls /proc/pressure`. Some distros turn it off, and `psi=1` on the kernel
  command line turns it on.

No `last kill` line after a crash
: The system journal is readable only by root and the `adm` and `systemd-journal` groups. Run `sudo mem`, or join
  the group with `sudo usermod -aG systemd-journal $USER` and log in again. Only the past 24 hours count.

The table adds up to far less than used
: Tmpfs files in `/tmp` and `/dev/shm` and GPU memory count as used but belong to no process. Check `df -h /tmp
  /dev/shm`.

RSS adds up to more than the total
: Shared memory counts once in every process that maps it. Browsers and Electron apps share a lot between their
  processes.

`mem: cannot read /proc/meminfo, is /proc mounted?`
: `/proc` is missing, as in a chroot. Mount it with `sudo mount -t proc proc /proc`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | It worked. |
| 1 | `/proc/meminfo` could not be read. |
| 2 | Bad usage, such as `-n 0` or an argument. |

## See also

`proc`, `sysinfo`, `free(1)`, `systemd-oomd(8)`, `proc(5)`
